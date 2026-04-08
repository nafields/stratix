// StreamMetricsSnapshotTests.swift
// Exercises stream metrics snapshot behavior.
//

import XCTest
import StratixModels
@testable import DiagnosticsKit

final class StreamMetricsSnapshotTests: XCTestCase {
    func testSnapshotIsDeterministicForEquivalentInputs() {
        let timestamp = Date(timeIntervalSince1970: 42)
        let authRecord = StreamMetricsMilestoneRecord(
            milestone: .authReady,
            timestamp: Date(timeIntervalSince1970: 1),
            metadata: ["mode": "full"]
        )
        let launchRecord = StreamMetricsMilestoneRecord(
            milestone: .launchRequested,
            timestamp: timestamp,
            context: .home,
            targetID: "console-1"
        )
        let runtimeRecord = StreamMetricsMilestoneRecord(
            milestone: .runtimePrepared,
            timestamp: Date(timeIntervalSince1970: 43),
            context: .home,
            targetID: "console-1"
        )
        let peerRecord = StreamMetricsMilestoneRecord(
            milestone: .peerConnected,
            timestamp: Date(timeIntervalSince1970: 44)
        )
        let firstFrameReceivedRecord = StreamMetricsMilestoneRecord(
            milestone: .firstFrameReceived,
            timestamp: Date(timeIntervalSince1970: 45)
        )
        let firstFrameRenderedRecord = StreamMetricsMilestoneRecord(
            milestone: .firstFrameRendered,
            timestamp: Date(timeIntervalSince1970: 46)
        )
        let overlayRecord = StreamMetricsMilestoneRecord(
            milestone: .overlayOpened,
            timestamp: Date(timeIntervalSince1970: 47),
            context: .home,
            targetID: "console-1",
            overlayTrigger: "automatic",
            latencyMs: 500
        )
        let disconnectRecord = StreamMetricsMilestoneRecord(
            milestone: .disconnectIntent,
            timestamp: Date(timeIntervalSince1970: 48),
            disconnectIntent: .userInitiated
        )
        let reconnectAttemptRecord = StreamMetricsMilestoneRecord(
            milestone: .reconnectAttempt,
            timestamp: Date(timeIntervalSince1970: 49),
            reconnectAttempt: 1,
            reconnectTrigger: "failed"
        )
        let reconnectSuccessRecord = StreamMetricsMilestoneRecord(
            milestone: .reconnectSuccess,
            timestamp: Date(timeIntervalSince1970: 50),
            reconnectAttempt: 1,
            reconnectOutcome: .success
        )
        let reconnectFailureRecord = StreamMetricsMilestoneRecord(
            milestone: .reconnectFailure,
            timestamp: Date(timeIntervalSince1970: 51),
            reconnectAttempt: 2,
            reconnectOutcome: .failure
        )

        let lhs = StreamMetricsSnapshot(
            recentRecords: [
                StreamMetricsRecord(
                    timestamp: timestamp,
                    source: .milestone,
                    payload: .milestone(launchRecord)
                )
            ],
            latestStatsSnapshot: StreamingStatsSnapshot(timestamp: timestamp, framesPerSecond: 60),
            performanceEventCounts: [.streamIntent: 1],
            latestPerformanceEvents: [:],
            latestMilestoneEvents: [
                .authReady: authRecord,
                .launchRequested: launchRecord,
                .runtimePrepared: runtimeRecord,
                .peerConnected: peerRecord,
                .firstFrameReceived: firstFrameReceivedRecord,
                .firstFrameRendered: firstFrameRenderedRecord,
                .overlayOpened: overlayRecord,
                .disconnectIntent: disconnectRecord,
                .reconnectAttempt: reconnectAttemptRecord,
                .reconnectSuccess: reconnectSuccessRecord,
                .reconnectFailure: reconnectFailureRecord,
            ],
            authReady: authRecord,
            launchRequested: launchRecord,
            runtimePrepared: runtimeRecord,
            peerConnected: peerRecord,
            firstFrameReceived: firstFrameReceivedRecord,
            firstFrameRendered: firstFrameRenderedRecord,
            overlayOpened: overlayRecord,
            disconnectIntent: disconnectRecord,
            latestReconnectAttempt: reconnectAttemptRecord,
            reconnectSuccess: reconnectSuccessRecord,
            reconnectFailure: reconnectFailureRecord,
            reconnectAttemptCount: 2,
            overlayOpenLatencyMs: 500
        )

        let rhs = StreamMetricsSnapshot(
            recentRecords: [
                StreamMetricsRecord(
                    timestamp: timestamp,
                    source: .milestone,
                    payload: .milestone(launchRecord)
                )
            ],
            latestStatsSnapshot: StreamingStatsSnapshot(timestamp: timestamp, framesPerSecond: 60),
            performanceEventCounts: [.streamIntent: 1],
            latestPerformanceEvents: [:],
            latestMilestoneEvents: [
                .authReady: authRecord,
                .launchRequested: launchRecord,
                .runtimePrepared: runtimeRecord,
                .peerConnected: peerRecord,
                .firstFrameReceived: firstFrameReceivedRecord,
                .firstFrameRendered: firstFrameRenderedRecord,
                .overlayOpened: overlayRecord,
                .disconnectIntent: disconnectRecord,
                .reconnectAttempt: reconnectAttemptRecord,
                .reconnectSuccess: reconnectSuccessRecord,
                .reconnectFailure: reconnectFailureRecord,
            ],
            authReady: authRecord,
            launchRequested: launchRecord,
            runtimePrepared: runtimeRecord,
            peerConnected: peerRecord,
            firstFrameReceived: firstFrameReceivedRecord,
            firstFrameRendered: firstFrameRenderedRecord,
            overlayOpened: overlayRecord,
            disconnectIntent: disconnectRecord,
            latestReconnectAttempt: reconnectAttemptRecord,
            reconnectSuccess: reconnectSuccessRecord,
            reconnectFailure: reconnectFailureRecord,
            reconnectAttemptCount: 2,
            overlayOpenLatencyMs: 500
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.authReady?.metadata["mode"], "full")
        XCTAssertEqual(lhs.launchRequested?.context, .home)
        XCTAssertEqual(lhs.runtimePrepared?.targetID, "console-1")
        XCTAssertEqual(lhs.peerConnected?.milestone, .peerConnected)
        XCTAssertEqual(lhs.firstFrameReceived?.milestone, .firstFrameReceived)
        XCTAssertEqual(lhs.firstFrameRendered?.milestone, .firstFrameRendered)
        XCTAssertEqual(lhs.overlayOpened?.overlayTrigger, "automatic")
        XCTAssertEqual(lhs.disconnectIntent?.disconnectIntent, .userInitiated)
        XCTAssertEqual(lhs.latestReconnectAttempt?.reconnectAttempt, 1)
        XCTAssertEqual(lhs.reconnectSuccess?.reconnectOutcome, .success)
        XCTAssertEqual(lhs.reconnectFailure?.reconnectOutcome, .failure)
        XCTAssertEqual(lhs.overlayOpenLatencyMs, 500)
        XCTAssertEqual(lhs.latestStatsSnapshot?.framesPerSecond, 60)
    }
}
