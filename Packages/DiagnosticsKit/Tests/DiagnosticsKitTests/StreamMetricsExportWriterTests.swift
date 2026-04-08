// StreamMetricsExportWriterTests.swift
// Exercises stream metrics export writer behavior.
//

import XCTest
import StratixModels
@testable import DiagnosticsKit

final class StreamMetricsExportWriterTests: XCTestCase {
    func testExportOutputIsDeterministicAndStructured() throws {
        let timestamp = Date(timeIntervalSince1970: 100)
        let pipeline = StreamMetricsPipeline(retentionLimit: 8)
        pipeline.recordMilestone(.authReady, metadata: ["mode": "full"], timestamp: Date(timeIntervalSince1970: 90))
        pipeline.recordMilestone(.launchRequested, context: .cloud, targetID: "title-42", timestamp: timestamp)
        pipeline.recordMilestone(.runtimePrepared, context: .cloud, targetID: "title-42", timestamp: Date(timeIntervalSince1970: 100.25))
        pipeline.recordMilestone(.peerConnected, timestamp: Date(timeIntervalSince1970: 100.5))
        pipeline.recordMilestone(.firstFrameReceived, timestamp: Date(timeIntervalSince1970: 100.75))
        pipeline.recordMilestone(.firstFrameRendered, timestamp: Date(timeIntervalSince1970: 100.9))
        pipeline.recordMilestone(.overlayOpened, context: .cloud, targetID: "title-42", overlayTrigger: "automatic", timestamp: Date(timeIntervalSince1970: 101))
        pipeline.recordMilestone(.disconnectIntent, disconnectIntent: .reconnectable, timestamp: Date(timeIntervalSince1970: 102))
        pipeline.recordMilestone(.reconnectAttempt, reconnectAttempt: 1, reconnectTrigger: "failed", timestamp: Date(timeIntervalSince1970: 103))
        pipeline.recordMilestone(.reconnectSuccess, reconnectAttempt: 1, reconnectOutcome: .success, timestamp: Date(timeIntervalSince1970: 104))
        pipeline.recordStatsSnapshot(StreamingStatsSnapshot(timestamp: timestamp, framesPerSecond: 60, rendererMode: "metal"))

        let writer = StreamMetricsExportWriter()
        let first = try writer.exportString(snapshot: pipeline.snapshot())
        let second = try writer.exportString(snapshot: pipeline.snapshot())
        let exportedViaPipeline = String(decoding: try pipeline.export(using: writer), as: UTF8.self)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, exportedViaPipeline)
        XCTAssertTrue(first.contains("\"auth_ready\""))
        XCTAssertTrue(first.contains("\"launch_requested\""))
        XCTAssertTrue(first.contains("\"runtime_prepared\""))
        XCTAssertTrue(first.contains("\"peer_connected\""))
        XCTAssertTrue(first.contains("\"first_frame_received\""))
        XCTAssertTrue(first.contains("\"first_frame_rendered\""))
        XCTAssertTrue(first.contains("\"overlay_opened\""))
        XCTAssertTrue(first.contains("\"disconnect_intent\""))
        XCTAssertTrue(first.contains("\"reconnect_attempt\""))
        XCTAssertTrue(first.contains("\"reconnect_success\""))
        XCTAssertTrue(first.contains("\"overlayOpenLatencyMs\""))
        XCTAssertTrue(first.contains("\"rendererMode\":\"metal\""))
        XCTAssertTrue(first.contains("\"reconnectAttemptCount\":1"))
    }
}
