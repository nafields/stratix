// StreamMetricsExportWriter.swift
// Defines stream metrics export writer.
//

import Foundation
import StratixModels

public struct StreamMetricsExportWriter: Sendable {
    public init() {}

    public func export(snapshot: StreamMetricsSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(ExportPayload(snapshot: snapshot))
    }

    public func exportString(snapshot: StreamMetricsSnapshot) throws -> String {
        let data = try export(snapshot: snapshot)
        guard let string = String(data: data, encoding: .utf8) else {
            throw StreamMetricsExportError.invalidUTF8
        }
        return string
    }
}

public enum StreamMetricsExportError: Error {
    case invalidUTF8
}

private struct ExportPayload: Encodable {
    let recentRecords: [ExportRecord]
    let latestStatsSnapshot: ExportStatsSnapshot?
    let milestones: [String: ExportMilestone]
    let reconnectAttemptCount: Int
    let overlayOpenLatencyMs: Double?

    init(snapshot: StreamMetricsSnapshot) {
        self.recentRecords = snapshot.recentRecords.map(ExportRecord.init)
        self.latestStatsSnapshot = snapshot.latestStatsSnapshot.map(ExportStatsSnapshot.init)
        self.milestones = snapshot.latestMilestoneEvents
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key.rawValue] = ExportMilestone(entry.value)
            }
        self.reconnectAttemptCount = snapshot.reconnectAttemptCount
        self.overlayOpenLatencyMs = snapshot.overlayOpenLatencyMs
    }
}

private struct ExportRecord: Encodable {
    let timestamp: String
    let source: String
    let payload: ExportPayloadValue

    init(_ record: StreamMetricsRecord) {
        self.timestamp = ExportTimestampFormatter.string(from: record.timestamp)
        self.source = record.source.rawValue
        self.payload = ExportPayloadValue(record.payload)
    }
}

private enum ExportPayloadValue: Encodable {
    case performanceEvent(event: String, metadata: [String: String])
    case statsSnapshot(ExportStatsSnapshot)
    case milestone(ExportMilestone)

    init(_ payload: StreamMetricsRecordPayload) {
        switch payload {
        case .performanceEvent(let event, let metadata):
            self = .performanceEvent(event: event.rawValue, metadata: metadata)
        case .statsSnapshot(let snapshot):
            self = .statsSnapshot(ExportStatsSnapshot(snapshot))
        case .milestone(let record):
            self = .milestone(ExportMilestone(record))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .performanceEvent(let event, let metadata):
            try container.encode("performance_event", forKey: .kind)
            try container.encode(event, forKey: .event)
            try container.encode(metadata, forKey: .metadata)
        case .statsSnapshot(let snapshot):
            try container.encode("stats_snapshot", forKey: .kind)
            try container.encode(snapshot, forKey: .statsSnapshot)
        case .milestone(let record):
            try container.encode("milestone", forKey: .kind)
            try container.encode(record, forKey: .milestone)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case event
        case metadata
        case statsSnapshot
        case milestone
    }
}

private struct ExportMilestone: Encodable {
    let milestone: String
    let timestamp: String
    let context: String?
    let targetID: String?
    let disconnectIntent: String?
    let reconnectAttempt: Int?
    let reconnectTrigger: String?
    let reconnectOutcome: String?
    let overlayTrigger: String?
    let latencyMs: Double?
    let metadata: [String: String]

    init(_ record: StreamMetricsMilestoneRecord) {
        self.milestone = record.milestone.rawValue
        self.timestamp = ExportTimestampFormatter.string(from: record.timestamp)
        self.context = record.context?.rawValue
        self.targetID = record.targetID
        self.disconnectIntent = record.disconnectIntent?.rawValue
        self.reconnectAttempt = record.reconnectAttempt
        self.reconnectTrigger = record.reconnectTrigger
        self.reconnectOutcome = record.reconnectOutcome?.rawValue
        self.overlayTrigger = record.overlayTrigger
        self.latencyMs = record.latencyMs
        self.metadata = record.metadata
    }
}

private struct ExportStatsSnapshot: Encodable {
    let timestamp: String
    let bitrateKbps: Int?
    let framesPerSecond: Double?
    let roundTripTimeMs: Double?
    let jitterMs: Double?
    let decodeTimeMs: Double?
    let packetsLost: Int?
    let framesLost: Int?
    let audioJitterMs: Double?
    let audioPacketsLost: Int?
    let audioBitrateKbps: Int?
    let audioJitterBufferDelayMs: Double?
    let audioConcealedSamples: Int?
    let audioTotalSamplesReceived: Int?
    let activeRegion: String?
    let negotiatedWidth: Int?
    let negotiatedHeight: Int?
    let controlPreferredWidth: Int?
    let controlPreferredHeight: Int?
    let messagePreferredWidth: Int?
    let messagePreferredHeight: Int?
    let rendererMode: String?
    let inputFlushHz: Double?
    let inputFlushJitterMs: Double?
    let rendererFramesReceived: Int?
    let rendererFramesDrawn: Int?
    let rendererFramesDroppedByCoalescing: Int?
    let rendererDrawQueueDepthMax: Int?
    let rendererFramesFailed: Int?
    let rendererProcessingStatus: String?
    let rendererProcessingInputWidth: Int?
    let rendererProcessingInputHeight: Int?
    let rendererProcessingOutputWidth: Int?
    let rendererProcessingOutputHeight: Int?
    let renderLatencyMs: Double?
    let rendererOutputFamily: String?
    let rendererEligibleRungs: [String]
    let rendererDeadRungs: [String]
    let rendererLastError: String?

    init(_ snapshot: StreamingStatsSnapshot) {
        self.timestamp = ExportTimestampFormatter.string(from: snapshot.timestamp)
        self.bitrateKbps = snapshot.bitrateKbps
        self.framesPerSecond = snapshot.framesPerSecond
        self.roundTripTimeMs = snapshot.roundTripTimeMs
        self.jitterMs = snapshot.jitterMs
        self.decodeTimeMs = snapshot.decodeTimeMs
        self.packetsLost = snapshot.packetsLost
        self.framesLost = snapshot.framesLost
        self.audioJitterMs = snapshot.audioJitterMs
        self.audioPacketsLost = snapshot.audioPacketsLost
        self.audioBitrateKbps = snapshot.audioBitrateKbps
        self.audioJitterBufferDelayMs = snapshot.audioJitterBufferDelayMs
        self.audioConcealedSamples = snapshot.audioConcealedSamples
        self.audioTotalSamplesReceived = snapshot.audioTotalSamplesReceived
        self.activeRegion = snapshot.activeRegion
        self.negotiatedWidth = snapshot.negotiatedWidth
        self.negotiatedHeight = snapshot.negotiatedHeight
        self.controlPreferredWidth = snapshot.controlPreferredWidth
        self.controlPreferredHeight = snapshot.controlPreferredHeight
        self.messagePreferredWidth = snapshot.messagePreferredWidth
        self.messagePreferredHeight = snapshot.messagePreferredHeight
        self.rendererMode = snapshot.rendererMode
        self.inputFlushHz = snapshot.inputFlushHz
        self.inputFlushJitterMs = snapshot.inputFlushJitterMs
        self.rendererFramesReceived = snapshot.rendererFramesReceived
        self.rendererFramesDrawn = snapshot.rendererFramesDrawn
        self.rendererFramesDroppedByCoalescing = snapshot.rendererFramesDroppedByCoalescing
        self.rendererDrawQueueDepthMax = snapshot.rendererDrawQueueDepthMax
        self.rendererFramesFailed = snapshot.rendererFramesFailed
        self.rendererProcessingStatus = snapshot.rendererProcessingStatus
        self.rendererProcessingInputWidth = snapshot.rendererProcessingInputWidth
        self.rendererProcessingInputHeight = snapshot.rendererProcessingInputHeight
        self.rendererProcessingOutputWidth = snapshot.rendererProcessingOutputWidth
        self.rendererProcessingOutputHeight = snapshot.rendererProcessingOutputHeight
        self.renderLatencyMs = snapshot.renderLatencyMs
        self.rendererOutputFamily = snapshot.rendererOutputFamily
        self.rendererEligibleRungs = snapshot.rendererEligibleRungs
        self.rendererDeadRungs = snapshot.rendererDeadRungs
        self.rendererLastError = snapshot.rendererLastError
    }
}

private enum ExportTimestampFormatter {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
