// StreamingSessionModelTests.swift
// Exercises streaming session model behavior.
//

import Foundation
import Testing
import StratixModels
@testable import StreamingCore

@Suite
struct StreamingSessionModelTests {
    @MainActor
    @Test
    func resetHelpersOwnRuntimeReplayAndTelemetryState() {
        let bridge = SessionTestRecordingBridge(
            offerSDP: makeSessionTestOfferSDP(),
            localCandidates: [],
            connectionState: .connected
        )
        let model = StreamingSessionModel(
            apiClient: makeSessionTestClient(responses: []),
            bridge: bridge,
            config: StreamingConfig(),
            preferences: StreamPreferences(),
            delegateBox: StreamingRuntimeDelegateBox()
        )

        model.runtimeSnapshot.negotiatedDimensions = StreamDimensions(width: 1280, height: 720)
        model.runtimeSnapshot.inputFlushHz = 120
        model.runtimeSnapshot.inputFlushJitterMs = 3
        model.latestVideoTrack = NSObject()
        model.latestAudioTrack = NSObject()
        model.videoTrackReplayCount = 2
        model.rendererTelemetry.mode = "metal"
        model.rendererTelemetry.framesDrawn = 6

        model.resetForStreamStart()

        #expect(model.runtimeSnapshot.negotiatedDimensions == nil)
        #expect(model.runtimeSnapshot.inputFlushHz == nil)
        #expect(model.runtimeSnapshot.inputFlushJitterMs == nil)
        #expect(model.latestVideoTrack == nil)
        #expect(model.latestAudioTrack == nil)
        #expect(model.videoTrackReplayCount == 0)
        #expect(model.rendererTelemetry.mode == "sampleBuffer")
        #expect(model.rendererTelemetry.framesDrawn == nil)

        model.runtimeSnapshot.negotiatedDimensions = StreamDimensions(width: 1920, height: 1080)
        model.runtimeSnapshot.inputFlushHz = 240
        model.runtimeSnapshot.inputFlushJitterMs = 1
        model.rendererTelemetry.framesReceived = 10

        model.resetForStreamStop()

        #expect(model.runtimeSnapshot.negotiatedDimensions == nil)
        #expect(model.runtimeSnapshot.inputFlushHz == nil)
        #expect(model.runtimeSnapshot.inputFlushJitterMs == nil)
        #expect(model.rendererTelemetry.framesReceived == nil)
    }
}
