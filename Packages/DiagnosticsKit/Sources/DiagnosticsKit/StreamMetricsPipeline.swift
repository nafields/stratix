// StreamMetricsPipeline.swift
// Defines stream metrics pipeline.
//

import Foundation
import StratixModels
import os

/// Identifies which stream subsystem produced a metrics record.
public enum StreamMetricsRecordSource: String, Sendable, Equatable {
    case performanceEvent = "performance_event"
    case milestone = "milestone"
    case statsSnapshot = "stats_snapshot"
}

/// Carries the typed payload stored in the metrics pipeline ring buffer and exports.
public enum StreamMetricsRecordPayload: Sendable, Equatable {
    case performanceEvent(StreamPerformanceEvent, metadata: [String: String])
    case milestone(StreamMetricsMilestoneRecord)
    case statsSnapshot(StreamingStatsSnapshot)
}

/// Timestamped metrics event captured by the diagnostics pipeline.
public struct StreamMetricsRecord: Sendable, Equatable {
    public let timestamp: Date
    public let source: StreamMetricsRecordSource
    public let payload: StreamMetricsRecordPayload

    public init(
        timestamp: Date = .now,
        source: StreamMetricsRecordSource,
        payload: StreamMetricsRecordPayload
    ) {
        self.timestamp = timestamp
        self.source = source
        self.payload = payload
    }
}

/// A named observer that receives every record as it flows through the pipeline.
public struct StreamMetricsSink: Sendable {
    public let name: String
    private let handler: @Sendable (StreamMetricsRecord) -> Void

    public init(
        name: String,
        handler: @escaping @Sendable (StreamMetricsRecord) -> Void
    ) {
        self.name = name
        self.handler = handler
    }

    /// Forwards one record to the sink's registered handler closure.
    func record(_ record: StreamMetricsRecord) {
        handler(record)
    }
}

private struct StreamMetricsPipelineState: Sendable {
    var recentRecords: [StreamMetricsRecord] = []
    var latestStatsSnapshot: StreamingStatsSnapshot?
    var performanceEventCounts: [StreamPerformanceEvent: Int] = [:]
    var latestPerformanceEvents: [StreamPerformanceEvent: StreamMetricsRecord] = [:]
    var latestMilestoneEvents: [StreamMetricsMilestone: StreamMetricsMilestoneRecord] = [:]
    var authReady: StreamMetricsMilestoneRecord?
    var launchRequested: StreamMetricsMilestoneRecord?
    var runtimePrepared: StreamMetricsMilestoneRecord?
    var peerConnected: StreamMetricsMilestoneRecord?
    var firstFrameReceived: StreamMetricsMilestoneRecord?
    var firstFrameRendered: StreamMetricsMilestoneRecord?
    var overlayOpened: StreamMetricsMilestoneRecord?
    var disconnectIntent: StreamMetricsMilestoneRecord?
    var latestReconnectAttempt: StreamMetricsMilestoneRecord?
    var reconnectSuccess: StreamMetricsMilestoneRecord?
    var reconnectFailure: StreamMetricsMilestoneRecord?
    var reconnectAttemptCount = 0
    var overlayOpenLatencyMs: Double?
    var sinks: [UUID: StreamMetricsSink] = [:]

    mutating func resetSessionMetrics() {
        launchRequested = nil
        runtimePrepared = nil
        peerConnected = nil
        firstFrameReceived = nil
        firstFrameRendered = nil
        overlayOpened = nil
        disconnectIntent = nil
        latestReconnectAttempt = nil
        reconnectSuccess = nil
        reconnectFailure = nil
        reconnectAttemptCount = 0
        overlayOpenLatencyMs = nil
        latestMilestoneEvents.removeValue(forKey: .launchRequested)
        latestMilestoneEvents.removeValue(forKey: .runtimePrepared)
        latestMilestoneEvents.removeValue(forKey: .peerConnected)
        latestMilestoneEvents.removeValue(forKey: .firstFrameReceived)
        latestMilestoneEvents.removeValue(forKey: .firstFrameRendered)
        latestMilestoneEvents.removeValue(forKey: .overlayOpened)
        latestMilestoneEvents.removeValue(forKey: .disconnectIntent)
        latestMilestoneEvents.removeValue(forKey: .reconnectAttempt)
        latestMilestoneEvents.removeValue(forKey: .reconnectSuccess)
        latestMilestoneEvents.removeValue(forKey: .reconnectFailure)
    }
}

/// Collects recent stream diagnostics, milestone timing, and sink fan-out in one thread-safe boundary.
public final class StreamMetricsPipeline: Sendable {
    public static let shared = StreamMetricsPipeline()

    private let retentionLimit: Int
    private let state = OSAllocatedUnfairLock(initialState: StreamMetricsPipelineState())

    public init(retentionLimit: Int = 256) {
        self.retentionLimit = max(retentionLimit, 1)
    }

    /// Registers a sink and returns a token that can later be used to remove it.
    @discardableResult
    public func registerSink(_ sink: StreamMetricsSink) -> UUID {
        let token = UUID()
        state.withLock { $0.sinks[token] = sink }
        return token
    }

    public func unregisterSink(_ token: UUID) {
        _ = state.withLock { $0.sinks.removeValue(forKey: token) }
    }

    /// Clears retained metrics state while optionally keeping the current sink subscriptions.
    public func reset(retainingSinks: Bool = true) {
        state.withLock { currentState in
            let sinks = retainingSinks ? currentState.sinks : [:]
            currentState = StreamMetricsPipelineState()
            currentState.sinks = sinks
        }
    }

    /// Records a point-in-time performance event such as first frame or render fallback.
    public func recordPerformanceEvent(
        _ event: StreamPerformanceEvent,
        metadata: [String: String] = [:],
        timestamp: Date = .now
    ) {
        record(
            StreamMetricsRecord(
                timestamp: timestamp,
                source: .performanceEvent,
                payload: .performanceEvent(event, metadata: metadata)
            )
        )
    }

    /// Builds and records a milestone event from the launch and reconnect state machine.
    public func recordMilestone(
        _ milestone: StreamMetricsMilestone,
        context: StreamMetricsLaunchContext? = nil,
        targetID: String? = nil,
        disconnectIntent: StreamMetricsDisconnectIntent? = nil,
        reconnectAttempt: Int? = nil,
        reconnectTrigger: String? = nil,
        reconnectOutcome: StreamMetricsReconnectOutcome? = nil,
        overlayTrigger: String? = nil,
        metadata: [String: String] = [:],
        timestamp: Date = .now
    ) {
        let record = StreamMetricsMilestoneRecord(
            milestone: milestone,
            timestamp: timestamp,
            context: context,
            targetID: targetID,
            disconnectIntent: disconnectIntent,
            reconnectAttempt: reconnectAttempt,
            reconnectTrigger: reconnectTrigger,
            reconnectOutcome: reconnectOutcome,
            overlayTrigger: overlayTrigger,
            metadata: metadata
        )
        recordMilestone(record)
    }

    /// Stores the latest streaming stats sample for later export and diagnostics review.
    public func recordStatsSnapshot(
        _ snapshot: StreamingStatsSnapshot,
        timestamp: Date = .now
    ) {
        record(
            StreamMetricsRecord(
                timestamp: timestamp,
                source: .statsSnapshot,
                payload: .statsSnapshot(snapshot)
            )
        )
    }

    /// Returns the current in-memory snapshot used by export and debug tooling.
    public func snapshot() -> StreamMetricsPipelineSnapshot {
        state.withLock { currentState in
            let snapshot = StreamMetricsSnapshot(
                recentRecords: currentState.recentRecords,
                latestStatsSnapshot: currentState.latestStatsSnapshot,
                performanceEventCounts: currentState.performanceEventCounts,
                latestPerformanceEvents: currentState.latestPerformanceEvents,
                latestMilestoneEvents: currentState.latestMilestoneEvents,
                authReady: currentState.authReady,
                launchRequested: currentState.launchRequested,
                runtimePrepared: currentState.runtimePrepared,
                peerConnected: currentState.peerConnected,
                firstFrameReceived: currentState.firstFrameReceived,
                firstFrameRendered: currentState.firstFrameRendered,
                overlayOpened: currentState.overlayOpened,
                disconnectIntent: currentState.disconnectIntent,
                latestReconnectAttempt: currentState.latestReconnectAttempt,
                reconnectSuccess: currentState.reconnectSuccess,
                reconnectFailure: currentState.reconnectFailure,
                reconnectAttemptCount: currentState.reconnectAttemptCount,
                overlayOpenLatencyMs: currentState.overlayOpenLatencyMs
            )
            return snapshot
        }
    }

    /// Serializes the current pipeline snapshot into the export writer's JSON format.
    public func export(
        using writer: StreamMetricsExportWriter = StreamMetricsExportWriter()
    ) throws -> Data {
        try writer.export(snapshot: snapshot())
    }

    private func record(_ record: StreamMetricsRecord) {
        let sinks = state.withLock { currentState -> [StreamMetricsSink] in
            currentState.recentRecords.append(record)
            if currentState.recentRecords.count > retentionLimit {
                currentState.recentRecords.removeFirst(currentState.recentRecords.count - retentionLimit)
            }

            switch record.payload {
            case .performanceEvent(let event, _):
                currentState.performanceEventCounts[event, default: 0] += 1
                currentState.latestPerformanceEvents[event] = record
            case .milestone:
                break
            case .statsSnapshot(let snapshot):
                currentState.latestStatsSnapshot = snapshot
            }

            return Array(currentState.sinks.values)
        }

        for sink in sinks {
            sink.record(record)
        }
    }

    /// Applies milestone-specific retention and derived latency bookkeeping before fan-out.
    private func recordMilestone(_ milestoneRecord: StreamMetricsMilestoneRecord) {
        let (record, sinks) = state.withLock { currentState -> (StreamMetricsRecord, [StreamMetricsSink]) in
            var resolvedRecord = milestoneRecord

            if milestoneRecord.milestone == .launchRequested {
                currentState.resetSessionMetrics()
            }

            if milestoneRecord.milestone == .overlayOpened {
                let latencyMs = currentState.launchRequested.map {
                    max(0, milestoneRecord.timestamp.timeIntervalSince($0.timestamp) * 1000)
                }
                resolvedRecord = milestoneRecord.withLatency(latencyMs)
                currentState.overlayOpenLatencyMs = latencyMs
            }

            currentState.latestMilestoneEvents[resolvedRecord.milestone] = resolvedRecord

            switch resolvedRecord.milestone {
            case .authReady:
                currentState.authReady = resolvedRecord
            case .launchRequested:
                currentState.launchRequested = resolvedRecord
            case .runtimePrepared:
                currentState.runtimePrepared = resolvedRecord
            case .peerConnected:
                currentState.peerConnected = resolvedRecord
            case .firstFrameReceived:
                currentState.firstFrameReceived = resolvedRecord
            case .firstFrameRendered:
                currentState.firstFrameRendered = resolvedRecord
            case .overlayOpened:
                currentState.overlayOpened = resolvedRecord
            case .disconnectIntent:
                currentState.disconnectIntent = resolvedRecord
            case .reconnectAttempt:
                currentState.latestReconnectAttempt = resolvedRecord
                currentState.reconnectAttemptCount = max(currentState.reconnectAttemptCount, resolvedRecord.reconnectAttempt ?? 0)
                currentState.reconnectSuccess = nil
                currentState.reconnectFailure = nil
            case .reconnectSuccess:
                currentState.reconnectSuccess = resolvedRecord
            case .reconnectFailure:
                currentState.reconnectFailure = resolvedRecord
            }

            let record = StreamMetricsRecord(
                timestamp: resolvedRecord.timestamp,
                source: .milestone,
                payload: .milestone(resolvedRecord)
            )
            currentState.recentRecords.append(record)
            if currentState.recentRecords.count > retentionLimit {
                currentState.recentRecords.removeFirst(currentState.recentRecords.count - retentionLimit)
            }

            return (record, Array(currentState.sinks.values))
        }

        for sink in sinks {
            sink.record(record)
        }
    }
}
