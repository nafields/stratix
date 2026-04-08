// StreamView.swift
// Defines the main streaming screen, including render-surface attachment and overlay coordination.
//

import SwiftUI
import StratixModels
import StratixCore
import StreamingCore

// MARK: - Unified Stream View (xCloud or xHome)

/// Renders the active stream session and keeps the overlay, renderer, and exit behavior in sync.
struct StreamView: View {
    let context: StreamContext

    @Environment(StreamController.self) private var streamController
    @Environment(LibraryController.self) private var libraryController
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var surfaceModel = StreamSurfaceModel()
    @State private var renderSurfaceCoordinator = RenderSurfaceCoordinator()
    @State private var rendererAttachmentCoordinator = RendererAttachmentCoordinator()

    /// Reads the current stream-related user settings from the shared settings store.
    private var streamSettings: SettingsStore.StreamSettings {
        settingsStore.stream
    }

    private var showStatsHUD: Bool {
        streamSettings.showStreamStats
    }

    private var statsHUDPosition: String {
        streamSettings.statsHUDPosition
    }

    private var safeAreaPercent: Double {
        streamSettings.safeAreaPercent
    }

    /// Converts the configured safe-area percentage into a horizontal inset for the video surface.
    private func videoInset(containerWidth: CGFloat) -> CGFloat {
        // safe_area is 0–100: 100% = fill screen, 90% = 5% margin on each side.
        let margin = max(0, min(50, (100.0 - safeAreaPercent) / 2.0))
        return CGFloat(margin) / 100.0 * containerWidth
    }

    private var sessionIdentity: ObjectIdentifier? {
        streamController.streamingSession.map(ObjectIdentifier.init)
    }

    private var overlayVisible: Bool {
        streamController.isStreamOverlayVisible
    }

    private var overlayState: StreamOverlayState {
        StreamOverlayState(
            lifecycle: currentStreamLifecycle,
            overlayInfo: overlayInfo,
            overlayVisible: overlayVisible,
            hasSession: streamController.streamingSession != nil
        )
    }

    /// Builds the full-screen stream scene and wires lifecycle hooks into the stream controller.
    var body: some View {
        GeometryReader { proxy in
            streamViewport(proxy: proxy)
        }
        .ignoresSafeArea()
        .task {
            await startStreamIfNeeded()
        }
        .task(id: "stream-commands") {
            for await command in streamController.makeCommandStream() {
                await handleCommand(command)
            }
        }
        .onChange(of: sessionIdentity, initial: true) { _, _ in
            renderSurfaceCoordinator.handleSessionChange(
                session: streamController.streamingSession,
                surfaceModel: surfaceModel,
                overlayVisible: overlayVisible,
                showStatsHUD: showStatsHUD
            )
        }
        .onChange(of: settingsStore.stream.audioBoost) { _, newValue in
            renderSurfaceCoordinator.updateAudioBoost(newValue)
        }
        .onChange(of: streamController.isStreamOverlayVisible, initial: true) { _, _ in
            syncDiagnosticsPolling()
        }
        .onChange(of: settingsStore.stream.showStreamStats) { _, _ in
            syncDiagnosticsPolling()
        }
        .onDisappear {
            renderSurfaceCoordinator.handleDisappear(
                session: streamController.streamingSession,
                surfaceModel: surfaceModel,
                clearAttachment: { rendererAttachmentCoordinator.clear() },
                setOverlayVisible: { visible, trigger in
                    await streamController.setOverlayVisible(visible, trigger: trigger)
                },
                stopStreaming: { await streamController.stopStreaming() },
                exitPriorityMode: { await streamController.exitStreamPriorityMode() }
            )
        }
        .onPlayPauseCommand {
            Task {
                await streamController.setOverlayVisible(!overlayVisible, trigger: .userToggle)
            }
        }
        .onExitCommand {
            // Do not use controller B/Menu as an in-game escape shortcut.
            // Keep it available to the stream; if the overlay is open, treat Exit as "close overlay".
            guard overlayVisible else { return }
            Task {
                await streamController.setOverlayVisible(false, trigger: .explicitDismiss)
            }
        }
    }

    @ViewBuilder
    /// Composes the current stream viewport, artwork fallback, overlay, and reconnect banner.
    private func streamViewport(proxy: GeometryProxy) -> some View {
        let session = streamController.streamingSession

        ZStack {
            streamRuntimeStatusMarker
            streamFirstFrameMarker

            if !surfaceModel.hasRenderedFirstFrame {
                StreamLaunchArtworkView(imageURL: overlayInfo.imageURL)
            }

            if session != nil || surfaceModel.videoTrack != nil {
                videoSurface(proxy: proxy)
            }

            if let session {
                sessionOverlay(session: session)
            } else {
                StreamPreparingOverlay(overlayInfo: overlayInfo) {
                    requestStreamExit()
                }
            }

            if let session {
                StreamCompactStatsHUD(
                    session: session,
                    surfaceModel: surfaceModel,
                    showStatsHUD: showStatsHUD,
                    statsHUDPosition: statsHUDPosition,
                    overlayVisible: overlayVisible,
                    runtimeProbeValue: streamRuntimeProbeValue,
                    showRuntimeStatusProbe: StratixLaunchMode.isStreamRuntimeProbeUITestModeEnabled
                )
            }

            if streamController.isReconnecting {
                reconnectBanner
            }
        }
    }

    @ViewBuilder
    private var streamRuntimeStatusMarker: some View {
        if StratixLaunchMode.isStreamRuntimeProbeUITestModeEnabled {
            Text(streamRuntimeProbeValue)
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityValue(streamRuntimeProbeValue)
                .accessibilityIdentifier("stream_runtime_status")
        }
    }

    @ViewBuilder
    private var streamFirstFrameMarker: some View {
        if surfaceModel.hasRenderedFirstFrame {
            Text("first_frame_rendered")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("stream_first_frame_rendered")
        }
    }

    /// Produces the runtime probe string used by stream-runtime UI harness checks.
    private var streamRuntimeProbeValue: String {
        renderSurfaceCoordinator.runtimeProbeValue(
            lifecycle: currentStreamLifecycle,
            runtimePhase: streamController.runtimePhase,
            hasSession: streamController.streamingSession != nil,
            overlayVisible: overlayVisible,
            surfaceModel: surfaceModel
        )
    }

    private var currentStreamLifecycle: StreamLifecycleState {
        streamController.streamingSession?.lifecycle ?? .idle
    }

    /// Creates the active WebRTC-backed video surface with the current renderer callbacks attached.
    private func videoSurface(proxy: GeometryProxy) -> some View {
        WebRTCVideoSurfaceView(
            videoTrack: surfaceModel.videoTrack,
            attachmentCoordinator: rendererAttachmentCoordinator,
            callbacks: renderSurfaceCoordinator.rendererCallbacks(
                surfaceModel: surfaceModel,
                currentSession: { streamController.streamingSession },
                overlayVisible: { overlayVisible },
                showStatsHUD: { showStatsHUD }
            )
        )
        .padding(safeAreaPercent < 100 ? videoInset(containerWidth: proxy.size.width) : 0)
        .ignoresSafeArea(edges: safeAreaPercent >= 100 ? .all : [])
    }

    @ViewBuilder
    /// Renders the stream overlay for an active session and exposes explicit exit handling.
    private func sessionOverlay(session: any StreamingSessionFacade) -> some View {
        StreamStatusOverlay(
            overlayState: overlayState,
            session: session,
            surfaceModel: surfaceModel,
            onCloseOverlay: {
                Task {
                    await streamController.setOverlayVisible(false, trigger: .explicitDismiss)
                }
            }
        ) {
            requestStreamExit()
        }

        if case .failed(let error) = session.lifecycle {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cloud Stream Failed")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(error.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Press Play/Pause to open controls.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 720, alignment: .leading)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 40)
        }
    }

    private var reconnectBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Reconnecting…")
                    .font(.callout.bold())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.78))
            .clipShape(Capsule())
            .padding(.bottom, 52)
        }
    }

    private var overlayInfo: StreamOverlayInfo {
        switch context {
        case .cloud(let titleId):
            return .cloud(
                item: libraryController.item(titleID: titleId),
                heroOverride: streamController.launchHeroURL,
                achievementSnapshot: streamController.currentStreamAchievementSnapshot,
                achievementErrorText: streamController.lastStreamAchievementError
            )
        case .home(let console):
            return .home(console: console)
        }
    }

    @MainActor
    private func requestStreamExit() {
        renderSurfaceCoordinator.requestExit(
            session: streamController.streamingSession,
            setOverlayVisible: { visible, trigger in
                await streamController.setOverlayVisible(visible, trigger: trigger)
            },
            stopStreaming: { await streamController.stopStreaming() },
            exitPriorityMode: { await streamController.exitStreamPriorityMode() },
            dismiss: { dismiss() }
        )
    }

    @MainActor
    private func startStreamIfNeeded() async {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            return
        }
        await renderSurfaceCoordinator.startStream(
            context: context,
            streamController: streamController,
            surfaceModel: surfaceModel
        )
    }

    @MainActor
    private func handleCommand(_ command: StreamUICommand) async {
        switch command {
        case .toggleOverlay:
            await streamController.setOverlayVisible(!overlayVisible, trigger: .userToggle)
        case .disconnect:
            requestStreamExit()
        case .toggleStatsHUD:
            updateStreamSettings { $0.showStreamStats.toggle() }
        }
    }

    @MainActor
    private func syncDiagnosticsPolling() {
        renderSurfaceCoordinator.syncDiagnosticsPolling(
            session: streamController.streamingSession,
            overlayVisible: overlayVisible,
            showStatsHUD: showStatsHUD
        )
    }

    @MainActor
    private func updateStreamSettings(_ update: (inout SettingsStore.StreamSettings) -> Void) {
        var next = settingsStore.stream
        update(&next)
        settingsStore.stream = next
    }
}

#if DEBUG
private struct StreamViewPreviewHost: View {
    @State private var coordinator = AppCoordinator()

    var body: some View {
        StreamView(context: .cloud(titleId: TitleID("preview-title-id")))
            .environment(coordinator.streamController)
            .environment(coordinator.libraryController)
            .environment(coordinator.settingsStore)
    }
}

#Preview("StreamView", traits: .fixedLayout(width: 1920, height: 1080)) {
    StreamViewPreviewHost()
}
#endif
