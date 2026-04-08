// RenderSurfaceCoordinator.swift
// Defines the render surface coordinator for the Features / Streaming surface.
//

import Foundation
import DiagnosticsKit
import StratixCore
import StratixModels
import StreamingCore

private extension StreamLifecycleState {
    var runtimeStatusLabel: String {
        switch self {
        case .idle:
            return "idle"
        case .startingSession:
            return "starting_session"
        case .provisioning:
            return "provisioning"
        case .waitingForResources:
            return "waiting_for_resources"
        case .readyToConnect:
            return "ready_to_connect"
        case .connectingWebRTC:
            return "connecting_webrtc"
        case .connected:
            return "connected"
        case .disconnecting:
            return "disconnecting"
        case .disconnected:
            return "disconnected"
        case .failed:
            return "failed"
        }
    }
}

private extension StreamRuntimePhase {
    var runtimeStatusLabel: String {
        switch self {
        case .shellActive:
            return "shell_active"
        case .preparingStream:
            return "preparing_stream"
        case .streaming:
            return "streaming"
        case .restoringShell:
            return "restoring_shell"
        }
    }
}

@MainActor
/// Owns stream-surface policy for starting, stopping, and instrumenting render attachment.
final class RenderSurfaceCoordinator {
    private var bridge: WebRTCClientImpl?
    private var attachedSessionObjectID: ObjectIdentifier?
    private var isExitingStream = false

    /// Starts the requested cloud or home stream using the prepared render bridge.
    func startStream(
        context: StreamContext,
        streamController: StreamController,
        surfaceModel: StreamSurfaceModel
    ) async {
        let activeBridge = prepareBridge(
            surfaceModel: surfaceModel,
            session: streamController.streamingSession
        )
        switch context {
        case .cloud(let titleID):
            await streamController.startCloudStream(titleId: titleID, bridge: activeBridge)
        case .home(let console):
            await streamController.startHomeStream(console: console, bridge: activeBridge)
        }
    }

    /// Resets stream-surface state and reattaches callbacks when the session changes.
    func handleSessionChange(
        session: (any StreamingSessionFacade)?,
        surfaceModel: StreamSurfaceModel,
        overlayVisible: Bool,
        showStatsHUD: Bool
    ) {
        surfaceModel.reset()
        attachVideoTrackHandler(to: session, surfaceModel: surfaceModel)
        syncDiagnosticsPolling(
            session: session,
            overlayVisible: overlayVisible,
            showStatsHUD: showStatsHUD
        )
    }

    /// Propagates the audio-boost setting into the underlying WebRTC bridge.
    func updateAudioBoost(_ value: Double) {
        #if WEBRTC_AVAILABLE
        bridge?.updateAudioBoost(dB: value)
        #endif
    }

    /// Builds the callback bundle that feeds renderer diagnostics back into surface state.
    func rendererCallbacks(
        surfaceModel: StreamSurfaceModel,
        currentSession: @escaping @MainActor () -> (any StreamingSessionFacade)?,
        overlayVisible: @escaping @MainActor () -> Bool,
        showStatsHUD: @escaping @MainActor () -> Bool
    ) -> RendererAttachmentCoordinator.Callbacks {
        RendererAttachmentCoordinator.Callbacks(
            onRendererModeChanged: { [weak self] mode in
                guard let self else { return }
                guard self.shouldAcceptRendererDiagnostics(
                    overlayVisible: overlayVisible(),
                    showStatsHUD: showStatsHUD(),
                    hasRenderedFirstFrame: surfaceModel.hasRenderedFirstFrame
                ) else {
                    return
                }
                surfaceModel.updateRendererMode(mode)
            },
            onRendererTelemetryChanged: { [weak self] snapshot in
                guard let self else { return }
                guard self.shouldAcceptRendererDiagnostics(
                    overlayVisible: overlayVisible(),
                    showStatsHUD: showStatsHUD(),
                    hasRenderedFirstFrame: surfaceModel.hasRenderedFirstFrame
                ) else {
                    return
                }
                surfaceModel.updateTelemetry(snapshot)
            },
            onRendererDecodeFailure: { details in
                surfaceModel.reportDecodeFailure(details)
                currentSession()?.reportRendererDecodeFailure(details)
            },
            onFirstVideoFrameDrawn: {
                let shouldRecordFirstFrame = !surfaceModel.hasRenderedFirstFrame
                surfaceModel.markRenderedFirstFrame()
                if shouldRecordFirstFrame {
                    StreamMetricsPipeline.shared.recordMilestone(.firstFrameRendered)
                }
            }
        )
    }

    /// Produces the hidden runtime probe string used by UI harnesses and shell tests.
    func runtimeProbeValue(
        lifecycle: StreamLifecycleState,
        runtimePhase: StreamRuntimePhase,
        hasSession: Bool,
        overlayVisible: Bool,
        surfaceModel: StreamSurfaceModel
    ) -> String {
        let firstFrameState = surfaceModel.hasRenderedFirstFrame ? "first_frame_rendered" : "waiting_for_first_frame"
        let trackState = surfaceModel.videoTrack == nil ? "detached" : "attached"
        let sessionState = hasSession ? "present" : "missing"
        let overlayState = overlayVisible ? "visible" : "hidden"
        let disconnectState = (overlayVisible && hasSession) ? "armed" : "idle"
        return "session=\(sessionState);lifecycle=\(lifecycle.runtimeStatusLabel);track=\(trackState);frame=\(firstFrameState);overlay=\(overlayState);disconnect=\(disconnectState);phase=\(runtimePhase.runtimeStatusLabel)"
    }

    /// Enables diagnostics polling only while the overlay or HUD needs live stream data.
    func syncDiagnosticsPolling(
        session: (any StreamingSessionFacade)?,
        overlayVisible: Bool,
        showStatsHUD: Bool
    ) {
        session?.setDiagnosticsPollingEnabled(overlayVisible || showStatsHUD)
    }

    /// Requests a stream exit and performs the teardown path before dismissing the surface.
    func requestExit(
        session: (any StreamingSessionFacade)?,
        setOverlayVisible: @escaping @MainActor (Bool, StreamOverlayTrigger) async -> Void,
        stopStreaming: @escaping @MainActor () async -> Void,
        exitPriorityMode: @escaping @MainActor () async -> Void,
        dismiss: @escaping @MainActor () -> Void
    ) {
        guard !isExitingStream else { return }
        isExitingStream = true
        session?.setDiagnosticsPollingEnabled(false)
        Task {
            await setOverlayVisible(false, .explicitExit)
            await stopStreaming()
            await exitPriorityMode()
        }
        dismiss()
    }

    /// Performs the non-explicit stream teardown path when the surface disappears.
    func handleDisappear(
        session: (any StreamingSessionFacade)?,
        surfaceModel: StreamSurfaceModel,
        clearAttachment: @escaping @MainActor () -> Void,
        setOverlayVisible: @escaping @MainActor (Bool, StreamOverlayTrigger) async -> Void,
        stopStreaming: @escaping @MainActor () async -> Void,
        exitPriorityMode: @escaping @MainActor () async -> Void
    ) {
        let wasExplicitExit = isExitingStream
        session?.setDiagnosticsPollingEnabled(false)
        session?.onVideoTrack = nil
        clearAttachment()
        surfaceModel.reset()
        attachedSessionObjectID = nil
        bridge = nil
        isExitingStream = false

        guard !wasExplicitExit else { return }

        Task {
            await setOverlayVisible(false, .explicitExit)
            await stopStreaming()
            await exitPriorityMode()
        }
    }

    /// Lazily creates the WebRTC bridge and clears any stale surface state before reuse.
    private func prepareBridge(
        surfaceModel: StreamSurfaceModel,
        session: (any StreamingSessionFacade)?
    ) -> WebRTCClientImpl {
        surfaceModel.reset()
        if bridge == nil {
            bridge = WebRTCClientImpl()
        }
        attachVideoTrackHandler(to: session, surfaceModel: surfaceModel)
        return bridge!
    }

    /// Attaches the session's video-track callback exactly once per active session identity.
    private func attachVideoTrackHandler(
        to session: (any StreamingSessionFacade)?,
        surfaceModel: StreamSurfaceModel
    ) {
        let newIdentifier = session.map(ObjectIdentifier.init)
        guard newIdentifier != attachedSessionObjectID else {
            streamLog("[StreamView] skipping redundant video track handler attach (same session)")
            return
        }

        attachedSessionObjectID = newIdentifier
        surfaceModel.setVideoTrack(nil)
        guard let session else { return }

        streamLog("[StreamView] attaching video track handler")
        session.onVideoTrack = { [weak surfaceModel] track in
            streamLog("[StreamView] onVideoTrack callback type=\(String(describing: type(of: track)))")
            Task { @MainActor in
                surfaceModel?.setVideoTrack(track)
            }
        }
    }

    /// Filters renderer diagnostics to the cases where the UI is ready to consume them.
    private func shouldAcceptRendererDiagnostics(
        overlayVisible: Bool,
        showStatsHUD: Bool,
        hasRenderedFirstFrame: Bool
    ) -> Bool {
        guard !isExitingStream else { return false }
        return overlayVisible || showStatsHUD || !hasRenderedFirstFrame
    }
}
