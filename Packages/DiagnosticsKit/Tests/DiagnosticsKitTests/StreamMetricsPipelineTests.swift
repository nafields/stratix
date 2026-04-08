// StreamMetricsPipelineTests.swift
// Exercises stream metrics pipeline behavior.
//

import XCTest
import os
import StratixModels
@testable import DiagnosticsKit

final class StreamMetricsPipelineTests: XCTestCase {
    func testRecordPerformanceEventRetainsMetadataAndCounts() {
        let pipeline = StreamMetricsPipeline(retentionLimit: 8)

        pipeline.recordPerformanceEvent(
            .streamIntent,
            metadata: [
                "kind": "cloud",
                "phase": "launch"
            ]
        )

        let snapshot = pipeline.snapshot()
        XCTAssertEqual(snapshot.recentRecords.count, 1)
        XCTAssertEqual(snapshot.performanceEventCounts[.streamIntent], 1)

        guard case let .performanceEvent(event, metadata) = snapshot.recentRecords[0].payload else {
            return XCTFail("Expected performance event record")
        }

        XCTAssertEqual(event, .streamIntent)
        XCTAssertEqual(metadata["kind"], "cloud")
        XCTAssertEqual(metadata["phase"], "launch")
        XCTAssertEqual(snapshot.latestPerformanceEvents[.streamIntent], snapshot.recentRecords[0])
    }

    func testRequiredMilestonesUpdateRetainedSnapshotState() {
        let pipeline = StreamMetricsPipeline(retentionLimit: 16)
        let launchDate = Date(timeIntervalSince1970: 10)
        let overlayDate = Date(timeIntervalSince1970: 11.25)

        pipeline.recordMilestone(.authReady, timestamp: Date(timeIntervalSince1970: 1))
        pipeline.recordMilestone(.launchRequested, context: .cloud, targetID: "title-123", timestamp: launchDate)
        pipeline.recordMilestone(.runtimePrepared, context: .cloud, targetID: "title-123", timestamp: Date(timeIntervalSince1970: 10.25))
        pipeline.recordMilestone(.peerConnected, timestamp: Date(timeIntervalSince1970: 10.5))
        pipeline.recordMilestone(.firstFrameReceived, timestamp: Date(timeIntervalSince1970: 10.75))
        pipeline.recordMilestone(.firstFrameRendered, timestamp: Date(timeIntervalSince1970: 11))
        pipeline.recordMilestone(.overlayOpened, context: .cloud, targetID: "title-123", overlayTrigger: "automatic", timestamp: overlayDate)
        pipeline.recordMilestone(.disconnectIntent, disconnectIntent: .userInitiated, timestamp: Date(timeIntervalSince1970: 12))
        pipeline.recordMilestone(.reconnectAttempt, reconnectAttempt: 1, reconnectTrigger: "failed", timestamp: Date(timeIntervalSince1970: 13))
        pipeline.recordMilestone(.reconnectFailure, reconnectAttempt: 1, reconnectOutcome: .failure, timestamp: Date(timeIntervalSince1970: 14))

        let snapshot = pipeline.snapshot()
        XCTAssertEqual(snapshot.authReady?.milestone, .authReady)
        XCTAssertEqual(snapshot.launchRequested?.context, .cloud)
        XCTAssertEqual(snapshot.launchRequested?.targetID, "title-123")
        XCTAssertEqual(snapshot.runtimePrepared?.milestone, .runtimePrepared)
        XCTAssertEqual(snapshot.peerConnected?.milestone, .peerConnected)
        XCTAssertEqual(snapshot.firstFrameReceived?.milestone, .firstFrameReceived)
        XCTAssertEqual(snapshot.firstFrameRendered?.milestone, .firstFrameRendered)
        XCTAssertEqual(snapshot.overlayOpened?.overlayTrigger, "automatic")
        XCTAssertEqual(snapshot.overlayOpenLatencyMs ?? -1, 1250, accuracy: 0.001)
        XCTAssertEqual(snapshot.disconnectIntent?.disconnectIntent, .userInitiated)
        XCTAssertEqual(snapshot.reconnectAttemptCount, 1)
        XCTAssertEqual(snapshot.latestReconnectAttempt?.reconnectAttempt, 1)
        XCTAssertEqual(snapshot.reconnectFailure?.reconnectOutcome, .failure)
    }

    func testRegisterSinkReceivesTypedRecordsInOrder() {
        let pipeline = StreamMetricsPipeline(retentionLimit: 8)
        let receivedState = OSAllocatedUnfairLock(initialState: [StreamMetricsRecord]())
        let token = pipeline.registerSink(
            StreamMetricsSink(name: "test-recorder") { record in
                receivedState.withLock { $0.append(record) }
            }
        )

        pipeline.recordPerformanceEvent(.streamIntent, metadata: ["kind": "home"])
        pipeline.recordStatsSnapshot(
            StreamingStatsSnapshot(
                bitrateKbps: 25_000,
                framesPerSecond: 60
            )
        )
        pipeline.unregisterSink(token)
        pipeline.recordPerformanceEvent(.overlayInteractive)

        let received = receivedState.withLock { $0 }
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0].source, StreamMetricsRecordSource.performanceEvent)
        XCTAssertEqual(received[1].source, StreamMetricsRecordSource.statsSnapshot)
    }

    func testRetentionLimitEvictsOldestRecords() {
        let pipeline = StreamMetricsPipeline(retentionLimit: 2)

        pipeline.recordPerformanceEvent(.streamIntent)
        pipeline.recordPerformanceEvent(.sessionStartRequest)
        pipeline.recordPerformanceEvent(.readyToConnect)

        let snapshot = pipeline.snapshot()
        XCTAssertEqual(snapshot.recentRecords.count, 2)

        guard case let .performanceEvent(firstRetainedEvent, _) = snapshot.recentRecords[0].payload else {
            return XCTFail("Expected retained performance event")
        }
        guard case let .performanceEvent(lastRetainedEvent, _) = snapshot.recentRecords[1].payload else {
            return XCTFail("Expected retained performance event")
        }

        XCTAssertEqual(firstRetainedEvent, .sessionStartRequest)
        XCTAssertEqual(lastRetainedEvent, .readyToConnect)
    }

    func testStatsCollectorPublishesSnapshotIntoPipeline() {
        let pipeline = StreamMetricsPipeline(retentionLimit: 8)
        let collector = StatsCollector(pipeline: pipeline)

        collector.update(
            bitrateKbps: 40_000,
            framesPerSecond: 59.94,
            roundTripTimeMs: 18,
            jitterMs: 2,
            decodeTimeMs: 8,
            packetsLost: 1,
            framesLost: 0,
            activeRegion: "eastus",
            negotiatedWidth: 1920,
            negotiatedHeight: 1080,
            rendererMode: "metal",
            rendererFramesReceived: 120,
            rendererFramesDrawn: 119,
            rendererFramesDroppedByCoalescing: 1,
            rendererDrawQueueDepthMax: 1,
            rendererFramesFailed: 0,
            rendererProcessingStatus: "metalFXSpatial",
            rendererProcessingInputWidth: 1280,
            rendererProcessingInputHeight: 720,
            rendererProcessingOutputWidth: 1920,
            rendererProcessingOutputHeight: 1080,
            renderLatencyMs: 14.5,
            rendererOutputFamily: "metal",
            rendererEligibleRungs: ["sampleBuffer", "metalFXSpatial"],
            rendererDeadRungs: [],
            rendererLastError: nil
        )

        let pipelineSnapshot = collector.pipelineSnapshot
        XCTAssertEqual(pipelineSnapshot.recentRecords.count, 1)
        XCTAssertEqual(pipelineSnapshot.latestStatsSnapshot?.bitrateKbps, 40_000)
        XCTAssertEqual(pipelineSnapshot.latestStatsSnapshot?.rendererMode, "metal")
        XCTAssertEqual(pipelineSnapshot.latestStatsSnapshot?.rendererFramesDrawn, 119)
    }
}
