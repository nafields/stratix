// StreamingSessionTrackReplayTests.swift
// Exercises streaming session track replay behavior.
//

import Foundation
import Testing
import DiagnosticsKit
import os
@testable import StreamingCore

@Suite(.serialized)
struct StreamingSessionTrackReplayTests {
    @MainActor
    @Test
    func videoTrackReplayStateLivesInSessionModel() {
        let bridge = SessionTestRecordingBridge(
            offerSDP: makeSessionTestOfferSDP(),
            localCandidates: [],
            connectionState: .connected
        )
        let session = StreamingSession(
            apiClient: makeSessionTestClient(responses: []),
            bridge: bridge
        )
        let track = NSObject()
        var deliveredTrackIDs: [ObjectIdentifier] = []

        session.runtimeDidReceiveVideoTrack(track)
        session.onVideoTrack = { deliveredTrackIDs.append(ObjectIdentifier($0)) }

        #expect(deliveredTrackIDs == [ObjectIdentifier(track)])
        #expect(session.model.videoTrackReplayCount == 1)
        #expect(session.model.latestVideoTrack === track)
    }

    @MainActor
    @Test
    func firstVideoTrackRecordsFirstFrameReceivedMilestone() {
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

        session.runtimeDidReceiveVideoTrack(NSObject())
        session.runtimeDidReceiveVideoTrack(NSObject())

        let firstFrameRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone.milestone == .firstFrameReceived ? milestone : nil
            }
        }
        #expect(firstFrameRecords.isEmpty == false)
    }
}
