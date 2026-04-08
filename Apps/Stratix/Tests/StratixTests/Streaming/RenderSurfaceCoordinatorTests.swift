// RenderSurfaceCoordinatorTests.swift
// Exercises render surface coordinator behavior.
//

import Foundation
import Testing
import DiagnosticsKit
import StratixCore
import StratixModels
import InputBridge
import os
@testable import Stratix
import StreamingCore

@MainActor
@Suite(.serialized)
struct RenderSurfaceCoordinatorTests {
    @Test
    func runtimeProbeValueReflectsSurfaceModelState() {
        let coordinator = RenderSurfaceCoordinator()
        let surfaceModel = StreamSurfaceModel()
        surfaceModel.setVideoTrack(NSString(string: "track"))
        surfaceModel.markRenderedFirstFrame()

        let value = coordinator.runtimeProbeValue(
            lifecycle: .connected,
            runtimePhase: .streaming,
            hasSession: true,
            overlayVisible: true,
            surfaceModel: surfaceModel
        )

        #expect(value.contains("session=present"))
        #expect(value.contains("track=attached"))
        #expect(value.contains("frame=first_frame_rendered"))
        #expect(value.contains("overlay=visible"))
        #expect(value.contains("phase=streaming"))
    }

    @Test
    func rendererCallbacksUpdateSurfaceModel() {
        let coordinator = RenderSurfaceCoordinator()
        let surfaceModel = StreamSurfaceModel()
        let callbacks = coordinator.rendererCallbacks(
            surfaceModel: surfaceModel,
            currentSession: { nil },
            overlayVisible: { true },
            showStatsHUD: { false }
        )

        callbacks.onRendererModeChanged("metal")
        callbacks.onRendererTelemetryChanged(
            .init(
                framesReceived: 12,
                framesDrawn: 11,
                framesDroppedByCoalescing: 1,
                drawQueueDepthMax: 2,
                framesFailed: nil,
                processingStatus: "warming",
                processingInputWidth: 1280,
                processingInputHeight: 720,
                processingOutputWidth: 1920,
                processingOutputHeight: 1080,
                renderLatencyMs: 7.1,
                outputFamily: "metal",
                eligibleRungs: ["sampleBuffer", "metalFXSpatial"],
                deadRungs: [],
                lastError: nil
            )
        )
        callbacks.onRendererDecodeFailure("decode failed")

        #expect(surfaceModel.activeRendererMode == "metal")
        #expect(surfaceModel.framesDrawn == 11)
        #expect(surfaceModel.lastError == "decode failed")
    }

    @Test
    func firstFrameRenderedMilestoneRecordsWithoutHUDOrOverlayVisibility() {
        let coordinator = RenderSurfaceCoordinator()
        let surfaceModel = StreamSurfaceModel()
        let records = OSAllocatedUnfairLock(initialState: [StreamMetricsRecord]())
        let token = StreamMetricsPipeline.shared.registerSink(
            StreamMetricsSink(name: #function) { record in
                records.withLock { $0.append(record) }
            }
        )
        defer { StreamMetricsPipeline.shared.unregisterSink(token) }

        let callbacks = coordinator.rendererCallbacks(
            surfaceModel: surfaceModel,
            currentSession: { nil },
            overlayVisible: { false },
            showStatsHUD: { false }
        )

        callbacks.onFirstVideoFrameDrawn()

        let firstFrameRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone.milestone == .firstFrameRendered ? milestone : nil
            }
        }
        #expect(surfaceModel.hasRenderedFirstFrame == true)
        #expect(firstFrameRecords.isEmpty == false)
    }

    @Test
    func syncDiagnosticsPollingTracksOverlayOrHUDVisibility() {
        let coordinator = RenderSurfaceCoordinator()
        let session = RenderSurfaceTestSession()

        coordinator.syncDiagnosticsPolling(
            session: session,
            overlayVisible: true,
            showStatsHUD: false
        )
        coordinator.syncDiagnosticsPolling(
            session: session,
            overlayVisible: false,
            showStatsHUD: false
        )

        #expect(session.diagnosticsPollingValues == [true, false])
    }

    @Test
    func requestExitDisablesDiagnosticsAndDelegatesStopPriorityAndDismiss() async {
        let coordinator = RenderSurfaceCoordinator()
        let session = RenderSurfaceTestSession()
        var overlayTransitions: [(Bool, StreamOverlayTrigger)] = []
        var stopCalls = 0
        var exitPriorityCalls = 0
        var dismissCalls = 0

        coordinator.requestExit(
            session: session,
            setOverlayVisible: { visible, trigger in
                overlayTransitions.append((visible, trigger))
            },
            stopStreaming: {
                stopCalls += 1
            },
            exitPriorityMode: {
                exitPriorityCalls += 1
            },
            dismiss: {
                dismissCalls += 1
            }
        )

        try? await Task.sleep(for: .milliseconds(50))

        #expect(session.diagnosticsPollingValues == [false])
        #expect(overlayTransitions.count == 1)
        #expect(overlayTransitions.first?.0 == false)
        #expect(overlayTransitions.first?.1 == .explicitExit)
        #expect(stopCalls == 1)
        #expect(exitPriorityCalls == 1)
        #expect(dismissCalls == 1)
    }
}

@MainActor
private final class RenderSurfaceTestSession: StreamingSessionFacade {
    var lifecycle: StreamLifecycleState = .connected
    var stats: StreamingStatsSnapshot = .init()
    var disconnectIntent: StreamingDisconnectIntent = .reconnectable
    let inputQueueRef = InputQueue()
    var onLifecycleChange: (@MainActor (StreamLifecycleState) -> Void)?
    var onVideoTrack: ((AnyObject) -> Void)?
    var diagnosticsPollingValues: [Bool] = []

    func connect(type: StreamKind, targetId: String, msaUserToken: String?) async {}

    func setVibrationHandler(_ handler: @escaping (VibrationReport) -> Void) {}

    func setDiagnosticsPollingEnabled(_ enabled: Bool) {
        diagnosticsPollingValues.append(enabled)
    }

    func reportRendererDecodeFailure(_ details: String) {}

    func setGamepadConnectionState(index: Int, connected: Bool) {}

    func disconnect(reason: StreamingDisconnectIntent) async {}
}
