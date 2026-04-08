// StreamingRuntimeTests.swift
// Exercises streaming runtime behavior.
//

import Testing
import DiagnosticsKit
import StratixModels
import os
@testable import StreamingCore

@Suite(.serialized)
struct StreamingRuntimeTests {
    @MainActor
    @Test
    func runtimeLifecycleCallbacksUpdateFacadeStateOutsideRootFile() {
        let bridge = SessionTestRecordingBridge(
            offerSDP: makeSessionTestOfferSDP(),
            localCandidates: [],
            connectionState: .connected
        )
        let session = StreamingSession(
            apiClient: makeSessionTestClient(responses: []),
            bridge: bridge
        )

        session.setDiagnosticsPollingEnabled(true)
        session.runtimeDidUpdateLifecycle(.connected)

        #expect(session.lifecycle == .connected)
        #expect(session.model.metricsSupport.diagnosticsPollingEnabled == true)

        session.runtimeDidUpdateSnapshot(
            .init(
                negotiatedDimensions: StreamDimensions(width: 1920, height: 1080),
                controlPreferredDimensions: StreamDimensions(width: 1280, height: 720),
                messagePreferredDimensions: StreamDimensions(width: 1280, height: 720),
                inputFlushHz: 120,
                inputFlushJitterMs: 2
            )
        )

        #expect(session.model.runtimeSnapshot.negotiatedDimensions?.width == 1920)
        #expect(session.stats.negotiatedWidth == 1920)
    }

    @MainActor
    @Test
    func connectedLifecycleAndDisconnectRecordMilestones() async {
        let bridge = SessionTestRecordingBridge(
            offerSDP: makeSessionTestOfferSDP(),
            localCandidates: [],
            connectionState: .connected
        )
        let session = StreamingSession(
            apiClient: makeSessionTestClient(responses: []),
            bridge: bridge
        )
        let records = OSAllocatedUnfairLock(initialState: [StreamMetricsRecord]())
        let token = StreamMetricsPipeline.shared.registerSink(
            StreamMetricsSink(name: #function) { record in
                records.withLock { $0.append(record) }
            }
        )
        defer { StreamMetricsPipeline.shared.unregisterSink(token) }

        session.runtimeDidUpdateLifecycle(.connected)
        await session.disconnect(reason: .serverInitiated)

        let milestoneRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone
            }
        }
        #expect(milestoneRecords.contains { $0.milestone == .peerConnected })
        #expect(milestoneRecords.contains { $0.milestone == .disconnectIntent && $0.disconnectIntent == .serverInitiated })
    }
}
