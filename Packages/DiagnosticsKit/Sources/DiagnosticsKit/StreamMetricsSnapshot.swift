// StreamMetricsSnapshot.swift
// Defines stream metrics snapshot.
//

import Foundation
import StratixModels

public enum StreamMetricsMilestone: String, Sendable, Equatable, Hashable, CaseIterable {
    case authReady = "auth_ready"
    case launchRequested = "launch_requested"
    case runtimePrepared = "runtime_prepared"
    case peerConnected = "peer_connected"
    case firstFrameReceived = "first_frame_received"
    case firstFrameRendered = "first_frame_rendered"
    case overlayOpened = "overlay_opened"
    case disconnectIntent = "disconnect_intent"
    case reconnectAttempt = "reconnect_attempt"
    case reconnectSuccess = "reconnect_success"
    case reconnectFailure = "reconnect_failure"
}

public enum StreamMetricsLaunchContext: String, Sendable, Equatable, Hashable {
    case cloud
    case home
}

public enum StreamMetricsDisconnectIntent: String, Sendable, Equatable, Hashable {
    case userInitiated = "user_initiated"
    case reconnectable = "reconnectable"
    case reconnectTransition = "reconnect_transition"
    case serverInitiated = "server_initiated"
}

public enum StreamMetricsReconnectOutcome: String, Sendable, Equatable, Hashable {
    case success
    case failure
}

public struct StreamMetricsMilestoneRecord: Sendable, Equatable {
    public let milestone: StreamMetricsMilestone
    public let timestamp: Date
    public let context: StreamMetricsLaunchContext?
    public let targetID: String?
    public let disconnectIntent: StreamMetricsDisconnectIntent?
    public let reconnectAttempt: Int?
    public let reconnectTrigger: String?
    public let reconnectOutcome: StreamMetricsReconnectOutcome?
    public let overlayTrigger: String?
    public let latencyMs: Double?
    public let metadata: [String: String]

    public init(
        milestone: StreamMetricsMilestone,
        timestamp: Date = .now,
        context: StreamMetricsLaunchContext? = nil,
        targetID: String? = nil,
        disconnectIntent: StreamMetricsDisconnectIntent? = nil,
        reconnectAttempt: Int? = nil,
        reconnectTrigger: String? = nil,
        reconnectOutcome: StreamMetricsReconnectOutcome? = nil,
        overlayTrigger: String? = nil,
        latencyMs: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        self.milestone = milestone
        self.timestamp = timestamp
        self.context = context
        self.targetID = targetID
        self.disconnectIntent = disconnectIntent
        self.reconnectAttempt = reconnectAttempt
        self.reconnectTrigger = reconnectTrigger
        self.reconnectOutcome = reconnectOutcome
        self.overlayTrigger = overlayTrigger
        self.latencyMs = latencyMs
        self.metadata = metadata
    }

    func withLatency(_ latencyMs: Double?) -> Self {
        Self(
            milestone: milestone,
            timestamp: timestamp,
            context: context,
            targetID: targetID,
            disconnectIntent: disconnectIntent,
            reconnectAttempt: reconnectAttempt,
            reconnectTrigger: reconnectTrigger,
            reconnectOutcome: reconnectOutcome,
            overlayTrigger: overlayTrigger,
            latencyMs: latencyMs,
            metadata: metadata
        )
    }
}

public struct StreamMetricsSnapshot: Sendable, Equatable {
    public let recentRecords: [StreamMetricsRecord]
    public let latestStatsSnapshot: StreamingStatsSnapshot?
    public let performanceEventCounts: [StreamPerformanceEvent: Int]
    public let latestPerformanceEvents: [StreamPerformanceEvent: StreamMetricsRecord]
    public let latestMilestoneEvents: [StreamMetricsMilestone: StreamMetricsMilestoneRecord]
    public let authReady: StreamMetricsMilestoneRecord?
    public let launchRequested: StreamMetricsMilestoneRecord?
    public let runtimePrepared: StreamMetricsMilestoneRecord?
    public let peerConnected: StreamMetricsMilestoneRecord?
    public let firstFrameReceived: StreamMetricsMilestoneRecord?
    public let firstFrameRendered: StreamMetricsMilestoneRecord?
    public let overlayOpened: StreamMetricsMilestoneRecord?
    public let disconnectIntent: StreamMetricsMilestoneRecord?
    public let latestReconnectAttempt: StreamMetricsMilestoneRecord?
    public let reconnectSuccess: StreamMetricsMilestoneRecord?
    public let reconnectFailure: StreamMetricsMilestoneRecord?
    public let reconnectAttemptCount: Int
    public let overlayOpenLatencyMs: Double?

    public init(
        recentRecords: [StreamMetricsRecord],
        latestStatsSnapshot: StreamingStatsSnapshot?,
        performanceEventCounts: [StreamPerformanceEvent: Int],
        latestPerformanceEvents: [StreamPerformanceEvent: StreamMetricsRecord],
        latestMilestoneEvents: [StreamMetricsMilestone: StreamMetricsMilestoneRecord],
        authReady: StreamMetricsMilestoneRecord?,
        launchRequested: StreamMetricsMilestoneRecord?,
        runtimePrepared: StreamMetricsMilestoneRecord?,
        peerConnected: StreamMetricsMilestoneRecord?,
        firstFrameReceived: StreamMetricsMilestoneRecord?,
        firstFrameRendered: StreamMetricsMilestoneRecord?,
        overlayOpened: StreamMetricsMilestoneRecord?,
        disconnectIntent: StreamMetricsMilestoneRecord?,
        latestReconnectAttempt: StreamMetricsMilestoneRecord?,
        reconnectSuccess: StreamMetricsMilestoneRecord?,
        reconnectFailure: StreamMetricsMilestoneRecord?,
        reconnectAttemptCount: Int,
        overlayOpenLatencyMs: Double?
    ) {
        self.recentRecords = recentRecords
        self.latestStatsSnapshot = latestStatsSnapshot
        self.performanceEventCounts = performanceEventCounts
        self.latestPerformanceEvents = latestPerformanceEvents
        self.latestMilestoneEvents = latestMilestoneEvents
        self.authReady = authReady
        self.launchRequested = launchRequested
        self.runtimePrepared = runtimePrepared
        self.peerConnected = peerConnected
        self.firstFrameReceived = firstFrameReceived
        self.firstFrameRendered = firstFrameRendered
        self.overlayOpened = overlayOpened
        self.disconnectIntent = disconnectIntent
        self.latestReconnectAttempt = latestReconnectAttempt
        self.reconnectSuccess = reconnectSuccess
        self.reconnectFailure = reconnectFailure
        self.reconnectAttemptCount = reconnectAttemptCount
        self.overlayOpenLatencyMs = overlayOpenLatencyMs
    }
}

public typealias StreamMetricsPipelineSnapshot = StreamMetricsSnapshot
