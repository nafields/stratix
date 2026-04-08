// WebRTCClientImplStats.swift
// Defines web rtc client impl stats for the Integration / WebRTC surface.
//

import Foundation
import StratixModels
import StreamingCore

#if WEBRTC_AVAILABLE
import WebRTC

extension WebRTCClientImpl {
    public func collectStats() async -> StreamingStatsSnapshot {
        guard let peerConnection else { return StreamingStatsSnapshot() }
        return await withCheckedContinuation { continuation in
            peerConnection.statistics { [weak self] report in
                guard let self else {
                    continuation.resume(returning: StreamingStatsSnapshot())
                    return
                }
                continuation.resume(returning: parseStatsReport(report))
            }
        }
    }

    func parseStatsReport(_ report: RTCStatisticsReport) -> StreamingStatsSnapshot {
        var fps: Double?
        var jitterMs: Double?
        var packetsLost: Int?
        var framesLost: Int?
        var rttMs: Double?
        var remoteInboundVideoRTTMs: Double?
        var remoteInboundAudioRTTMs: Double?
        var selectedCandidatePairID: String?
        var candidatePairRTTByID: [String: Double] = [:]
        var activeCandidatePairRTTMs: Double?
        var videoBytesReceived: UInt64?
        var videoStatsTimestamp: TimeInterval?
        var videoEstimatedPlayoutTimestampMs: Double?
        var videoFrameWidth: Int?
        var videoFrameHeight: Int?
        var videoCodecID: String?
        var videoCodecMimeType: String?

        var audioJitterMs: Double?
        var audioPacketsLost: Int?
        var audioBytesReceived: UInt64?
        var audioStatsTimestamp: TimeInterval?
        var audioEstimatedPlayoutTimestampMs: Double?
        var audioJitterBufferDelaySeconds: Double?
        var audioJitterBufferTargetDelaySeconds: Double?
        var audioJitterBufferMinimumDelaySeconds: Double?
        var audioJitterBufferEmittedCount: Double?
        var audioConcealedSamples: Int?
        var audioTotalSamplesReceived: Int?

        for (statsID, stats) in report.statistics {
            let values = stats.values
            if stats.type == "inbound-rtp",
               let kind = values["kind"] as? String {
                if kind == "video" {
                    fps = numericDouble(values["framesPerSecond"])
                    if let jitter = numericDouble(values["jitter"]) { jitterMs = jitter * 1000 }
                    packetsLost = numericInt(values["packetsLost"])
                    framesLost = numericInt(values["framesLost"])
                    videoBytesReceived = numericUInt64(values["bytesReceived"])
                    videoFrameWidth = numericInt(values["frameWidth"])
                    videoFrameHeight = numericInt(values["frameHeight"])
                    videoCodecID = values["codecId"] as? String
                    videoStatsTimestamp = Double(stats.timestamp_us) / 1_000_000
                    if let ts = numericDouble(values["estimatedPlayoutTimestamp"]) {
                        videoEstimatedPlayoutTimestampMs = ts * 1000.0
                    }
                } else if kind == "audio" {
                    if let jitter = numericDouble(values["jitter"]) { audioJitterMs = jitter * 1000 }
                    audioPacketsLost = numericInt(values["packetsLost"])
                    audioBytesReceived = numericUInt64(values["bytesReceived"])
                    audioStatsTimestamp = Double(stats.timestamp_us) / 1_000_000
                    if let ts = numericDouble(values["estimatedPlayoutTimestamp"]) {
                        audioEstimatedPlayoutTimestampMs = ts * 1000.0
                    }
                    audioJitterBufferDelaySeconds = numericDouble(values["jitterBufferDelay"])
                    audioJitterBufferTargetDelaySeconds = numericDouble(values["jitterBufferTargetDelay"])
                    audioJitterBufferMinimumDelaySeconds = numericDouble(values["jitterBufferMinimumDelay"])
                    audioJitterBufferEmittedCount = numericDouble(values["jitterBufferEmittedCount"])
                    audioConcealedSamples = numericInt(values["concealedSamples"])
                    audioTotalSamplesReceived = numericInt(values["totalSamplesReceived"])
                }
            }
            if stats.type == "remote-inbound-rtp",
               let kind = values["kind"] as? String {
                let remoteRTTMs = (numericDouble(values["roundTripTime"]) ?? numericDouble(values["currentRoundTripTime"]))
                    .map { $0 * 1000.0 }
                if kind == "video" {
                    remoteInboundVideoRTTMs = remoteRTTMs ?? remoteInboundVideoRTTMs
                } else if kind == "audio" {
                    remoteInboundAudioRTTMs = remoteRTTMs ?? remoteInboundAudioRTTMs
                }
            }
            if stats.type == "transport",
               let pairID = values["selectedCandidatePairId"] as? String,
               !pairID.isEmpty {
                selectedCandidatePairID = pairID
            }
            if stats.type == "candidate-pair",
               let pairRTT = (numericDouble(values["currentRoundTripTime"]) ?? numericDouble(values["roundTripTime"])) {
                let pairRTTMs = pairRTT * 1000.0
                candidatePairRTTByID[statsID] = pairRTTMs

                let state = (values["state"] as? String)?.lowercased()
                let isSelected = numericBool(values["selected"]) ?? false
                let isUsablePair = isSelected || state == "succeeded" || state == "in-progress"
                if activeCandidatePairRTTMs == nil, isUsablePair {
                    activeCandidatePairRTTMs = pairRTTMs
                }
            }
        }

        let selectedCandidatePairRTTMs = selectedCandidatePairID.flatMap { candidatePairRTTByID[$0] }
        rttMs = remoteInboundVideoRTTMs ?? remoteInboundAudioRTTMs ?? selectedCandidatePairRTTMs ?? activeCandidatePairRTTMs

        if let videoCodecID,
           let codecStats = report.statistics[videoCodecID],
           codecStats.type == "codec",
           let mimeType = codecStats.values["mimeType"] as? String {
            videoCodecMimeType = mimeType
        }

        let metricsWindow = statsStateBox.consumeMetricsWindow(
            videoBytesReceived: videoBytesReceived,
            videoStatsTimestamp: videoStatsTimestamp,
            audioBytesReceived: audioBytesReceived,
            audioStatsTimestamp: audioStatsTimestamp,
            audioJitterBufferDelaySeconds: audioJitterBufferDelaySeconds,
            audioJitterBufferTargetDelaySeconds: audioJitterBufferTargetDelaySeconds,
            audioJitterBufferMinimumDelaySeconds: audioJitterBufferMinimumDelaySeconds,
            audioJitterBufferEmittedCount: audioJitterBufferEmittedCount
        )
        let videoBitrateKbps = metricsWindow.videoBitrateKbps
        let audioBitrateKbps = metricsWindow.audioBitrateKbps

        var audioJitterBufferDelayMs: Double?
        if let delay = audioJitterBufferDelaySeconds,
           let emitted = audioJitterBufferEmittedCount,
           emitted > 0 {
            audioJitterBufferDelayMs = (delay / emitted) * 1000.0
        }
        let audioJitterBufferWindowDelayMs = metricsWindow.audioJitterBufferWindowDelayMs
        let audioJitterBufferWindowTargetMs = metricsWindow.audioJitterBufferWindowTargetMs
        let audioJitterBufferWindowUncappedMs = metricsWindow.audioJitterBufferWindowUncappedMs
        let audioPlayoutRatePct = metricsWindow.audioPlayoutRatePct
        let audioVideoPlayoutDeltaMs: Double? = {
            guard let audioTimestamp = audioEstimatedPlayoutTimestampMs,
                  let videoTimestamp = videoEstimatedPlayoutTimestampMs else { return nil }
            return audioTimestamp - videoTimestamp
        }()
        maybeTriggerAudioResyncWatchdog(
            audioJitterBufferDelayMs: audioJitterBufferDelayMs,
            audioJitterBufferWindowDelayMs: audioJitterBufferWindowDelayMs,
            audioJitterBufferWindowTargetMs: audioJitterBufferWindowTargetMs,
            audioJitterMs: audioJitterMs,
            audioPacketsLost: audioPacketsLost,
            audioJitterBufferEmittedCount: audioJitterBufferEmittedCount,
            audioVideoPlayoutDeltaMs: audioVideoPlayoutDeltaMs
        )

        if metricsWindow.shouldLogAudio {
            let jitterString = audioJitterMs.map { String(format: "%.1f", $0) } ?? "n/a"
            let lostString = audioPacketsLost.map(String.init) ?? "n/a"
            let bitrateString = audioBitrateKbps.map { "\($0)" } ?? "n/a"
            let jitterBufferString = audioJitterBufferDelayMs.map { String(format: "%.1f", $0) } ?? "n/a"
            let jitterBufferWindowString = audioJitterBufferWindowDelayMs.map { String(format: "%.1f", $0) } ?? "n/a"
            let emittedString = audioJitterBufferEmittedCount.map { String(format: "%.0f", $0) } ?? "n/a"
            let audioVideoDeltaString: String = {
                guard let delta = audioVideoPlayoutDeltaMs else { return "n/a" }
                return String(format: "%.1f", delta)
            }()
            let concealedPercent: String = {
                guard let concealed = audioConcealedSamples,
                      let total = audioTotalSamplesReceived,
                      total > 0 else { return "n/a" }
                return String(format: "%.2f", (Double(concealed) / Double(total)) * 100.0)
            }()
            let targetWindowString = audioJitterBufferWindowTargetMs.map { String(format: "%.1f", $0) } ?? "n/a"
            let uncappedWindowString = audioJitterBufferWindowUncappedMs.map { String(format: "%.1f", $0) } ?? "n/a"
            let playoutRateString = audioPlayoutRatePct.map { String(format: "%.1f", $0) } ?? "n/a"
            logAudioStats("jitterMs=\(jitterString) lost=\(lostString) bitrateKbps=\(bitrateString) jbAvgMs=\(jitterBufferString) jbWinMs=\(jitterBufferWindowString) jbTargetWinMs=\(targetWindowString) jbUncappedWinMs=\(uncappedWindowString) playoutRate=\(playoutRateString)% emitted=\(emittedString) concealedPct=\(concealedPercent) avSyncDeltaMs=\(audioVideoDeltaString)")
        }

        if metricsWindow.shouldLogVideo {
            let widthString = videoFrameWidth.map(String.init) ?? "n/a"
            let heightString = videoFrameHeight.map(String.init) ?? "n/a"
            let fpsString = fps.map { String(format: "%.1f", $0) } ?? "n/a"
            let codecString = videoCodecMimeType ?? "n/a"
            logVideoStats("frameWidth=\(widthString) frameHeight=\(heightString) fps=\(fpsString) codec=\(codecString)")
        }

        return StreamingStatsSnapshot(
            bitrateKbps: videoBitrateKbps,
            framesPerSecond: fps,
            roundTripTimeMs: rttMs,
            jitterMs: jitterMs,
            packetsLost: packetsLost,
            framesLost: framesLost,
            audioJitterMs: audioJitterMs,
            audioPacketsLost: audioPacketsLost,
            audioBitrateKbps: audioBitrateKbps,
            audioJitterBufferDelayMs: audioJitterBufferDelayMs,
            audioConcealedSamples: audioConcealedSamples,
            audioTotalSamplesReceived: audioTotalSamplesReceived
        )
    }

    private func numericDouble(_ raw: Any?) -> Double? {
        switch raw {
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Int:
            return Double(value)
        case let value as Int64:
            return Double(value)
        case let value as UInt64:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private func numericInt(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as UInt64:
            return Int(value)
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private func numericBool(_ raw: Any?) -> Bool? {
        switch raw {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            switch value.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func numericUInt64(_ raw: Any?) -> UInt64? {
        switch raw {
        case let value as UInt64:
            return value
        case let value as Int:
            return value >= 0 ? UInt64(value) : nil
        case let value as Int64:
            return value >= 0 ? UInt64(value) : nil
        case let value as Double:
            return value >= 0 ? UInt64(value) : nil
        case let value as NSNumber:
            return value.int64Value >= 0 ? value.uint64Value : nil
        case let value as String:
            return UInt64(value)
        default:
            return nil
        }
    }
}
#endif
