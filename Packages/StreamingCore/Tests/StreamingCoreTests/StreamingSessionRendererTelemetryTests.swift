// StreamingSessionRendererTelemetryTests.swift
// Exercises streaming session renderer telemetry behavior.
//

import Testing
import StratixModels
@testable import StreamingCore

@Suite
struct StreamingSessionRendererTelemetryTests {
    @MainActor
    @Test
    func rendererTelemetryOwnershipIsIsolatedFromFacadeRootStorage() {
        let bridge = SessionTestRecordingBridge(
            offerSDP: makeSessionTestOfferSDP(),
            localCandidates: [],
            connectionState: .connected
        )
        let session = StreamingSession(
            apiClient: makeSessionTestClient(responses: []),
            bridge: bridge
        )

        session.setRendererMode("metal")
        session.setRendererTelemetry(
            framesReceived: 180,
            framesDrawn: 177,
            framesDroppedByCoalescing: 3,
            drawQueueDepthMax: 1,
            framesFailed: 0,
            processingStatus: "metalFXSpatial",
            processingInputWidth: 1280,
            processingInputHeight: 720,
            processingOutputWidth: 1920,
            processingOutputHeight: 1080,
            renderLatencyMs: 12.5,
            outputFamily: "metal",
            eligibleRungs: ["sampleBuffer", "metalFXSpatial"],
            deadRungs: [],
            lastError: nil
        )

        #expect(session.model.rendererTelemetry.mode == "metal")
        #expect(session.model.rendererTelemetry.framesDrawn == 177)
        #expect(session.statsCollector.snapshot.rendererFramesDrawn == 177)
        #expect(session.statsCollector.pipelineSnapshot.latestStatsSnapshot?.rendererMode == "metal")
    }
}
