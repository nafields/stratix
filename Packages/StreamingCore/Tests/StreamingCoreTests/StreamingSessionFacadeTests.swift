// StreamingSessionFacadeTests.swift
// Exercises streaming session facade behavior.
//

import Testing
import StratixModels
@testable import StreamingCore

@Suite
struct StreamingSessionFacadeTests {
    @MainActor
    @Test
    func diagnosticsPollingDelegatesIntoMetricsSupport() {
        let bridge = SessionTestRecordingBridge(
            offerSDP: makeSessionTestOfferSDP(),
            localCandidates: [],
            connectionState: .connected
        )
        let session = StreamingSession(
            apiClient: makeSessionTestClient(responses: []),
            bridge: bridge
        )

        #expect(session.model.metricsSupport.diagnosticsPollingEnabled == false)

        session.setDiagnosticsPollingEnabled(true)
        session.setRendererMode("metal")

        #expect(session.model.metricsSupport.diagnosticsPollingEnabled == true)
        #expect(session.statsCollector.snapshot.rendererMode == "metal")
    }
}
