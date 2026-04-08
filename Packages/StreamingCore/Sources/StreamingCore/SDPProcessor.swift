// SDPProcessor.swift
// Defines sdp processor.
//

import Foundation
import StratixModels
import os

private let sdpLogger = Logger(subsystem: "com.stratix.app", category: "SDPProcessor")

// MARK: - SDP Processor
// Mirrors sdp.ts — manipulates SDP strings for Xbox streaming requirements.
// H.264 codec priority: profile-level-id=4d > 42e > 420 > others.
// Note: actual RTCPeerConnection codec preference setting is done in WebRTCClient
// using the codec capability list ordering returned here.

public struct SDPProcessor: Sendable {

    public init() {}

    /// Hardcoded baseline used for testing when UI-driven offer tuning should be ignored.
    /// This is applied to a generated offer so ICE/DTLS/session attributes stay valid.
    public struct HardcodedDefaultOfferProfile: Sendable, Equatable {
        public let maxVideoBitrateKbps: Int?
        public let maxAudioBitrateKbps: Int?
        public let stereoAudio: Bool
        public let preferredVideoCodec: String?
        public let maxVideoFrameRate: Int?
        public let h264ProfileLevelIdOverride: String?

        public init(
            maxVideoBitrateKbps: Int?,
            maxAudioBitrateKbps: Int?,
            stereoAudio: Bool,
            preferredVideoCodec: String?,
            maxVideoFrameRate: Int?,
            h264ProfileLevelIdOverride: String?
        ) {
            self.maxVideoBitrateKbps = maxVideoBitrateKbps
            self.maxAudioBitrateKbps = maxAudioBitrateKbps
            self.stereoAudio = stereoAudio
            self.preferredVideoCodec = preferredVideoCodec
            self.maxVideoFrameRate = maxVideoFrameRate
            self.h264ProfileLevelIdOverride = h264ProfileLevelIdOverride
        }
    }

    public static let hardcodedDefaultOfferProfile = HardcodedDefaultOfferProfile(
        maxVideoBitrateKbps: 120000,
        maxAudioBitrateKbps: 48000,
        stereoAudio: true,
        preferredVideoCodec: "H264",
        maxVideoFrameRate: 60,
        h264ProfileLevelIdOverride: "640029"
    )

    // MARK: - Codec Preference Ordering

    /// Returns a sorted list of H.264 profile tokens matching the JS codec preference order.
    /// Used to sort RTCRtpCodecCapability objects from the WebRTC framework.
    public func h264ProfilePriority(fmtp: String?) -> Int {
        guard let fmtp = fmtp else { return 99 }
        if fmtp.contains("profile-level-id=4d") { return 0 }   // High
        if fmtp.contains("profile-level-id=42e") { return 1 }  // Constrained Baseline (High compat)
        if fmtp.contains("profile-level-id=420") { return 2 }  // Baseline
        return 3
    }

    // MARK: - Modify Local Offer SDP

    /// Apply bitrate limits, codec preference reordering, and stereo audio to the local SDP offer.
    /// Mirrors sdp.ts setLocalSDP().
    /// - Parameter preferredVideoCodec: SDP codec name to move to the front of the video section
    ///   (e.g. "VP9", "VP8", "H265"). nil or "H264" keeps the default H.264-first ordering.
    public func processLocalSDP(
        sdp: String,
        maxVideoBitrateKbps: Int? = nil,
        maxAudioBitrateKbps: Int? = nil,
        stereoAudio: Bool = true,
        preferredVideoCodec: String? = nil,
        maxVideoFrameRate: Int? = nil,
        h264ProfileLevelIdOverride: String? = nil
    ) -> String {
        var result = sdp

        // Reorder video codecs before bitrate injection (bitrate applies after m= line)
        if let codec = preferredVideoCodec?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codec.isEmpty,
           codec.uppercased() != "H264" {
            result = reorderVideoCodecs(sdp: result, preferredSDPCodecName: codec)
        }

        if let videoBitrate = maxVideoBitrateKbps, videoBitrate > 0 {
            sdpLogger.info("Applying video bitrate cap via SDP: \(videoBitrate, privacy: .public) kbps")
            result = setBitrate(sdp: result, mediaType: "video", bitrateKbps: videoBitrate)
        }
        if let audioBitrate = maxAudioBitrateKbps, audioBitrate > 0 {
            sdpLogger.info("Applying audio bitrate cap via SDP: \(audioBitrate, privacy: .public) kbps")
            result = setBitrate(sdp: result, mediaType: "audio", bitrateKbps: audioBitrate)
        }
        if let maxVideoFrameRate, maxVideoFrameRate > 0 {
            sdpLogger.info("Applying video max-fr via SDP: \(maxVideoFrameRate, privacy: .public)")
            result = setVideoMaxFrameRate(sdp: result, maxFrameRate: maxVideoFrameRate)
        }
        if let h264ProfileLevelIdOverride, !h264ProfileLevelIdOverride.isEmpty {
            sdpLogger.info("Applying H264 profile-level-id override via SDP: \(h264ProfileLevelIdOverride, privacy: .public)")
            result = overrideH264ProfileLevelId(sdp: result, profileLevelId: h264ProfileLevelIdOverride)
        }
        if stereoAudio {
            result = enableOpusStereo(sdp: result)
        }
        return result
    }

    /// Applies a deterministic hardcoded offer profile for testing.
    /// Use this when stream startup should not depend on UI/UX tuning values.
    public func processLocalSDPWithHardcodedDefaults(sdp: String) -> String {
        let profile = Self.hardcodedDefaultOfferProfile
        return processLocalSDP(
            sdp: sdp,
            maxVideoBitrateKbps: profile.maxVideoBitrateKbps,
            maxAudioBitrateKbps: profile.maxAudioBitrateKbps,
            stereoAudio: profile.stereoAudio,
            preferredVideoCodec: profile.preferredVideoCodec,
            maxVideoFrameRate: profile.maxVideoFrameRate,
            h264ProfileLevelIdOverride: profile.h264ProfileLevelIdOverride
        )
    }

    // MARK: - Codec reordering

    /// Move the preferred video codec to the front of the m=video payload type list.
    /// Compares case-insensitively against SDP codec names from a=rtpmap lines.
    private func reorderVideoCodecs(sdp: String, preferredSDPCodecName: String) -> String {
        var lines = sdp.components(separatedBy: "\n")

        // Find m=video line
        guard let videoMLineIndex = lines.firstIndex(where: { $0.hasPrefix("m=video") }) else {
            return sdp
        }

        // Parse payload types from m=video line
        // "m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99" → header=["m=video","9","UDP/..."], pts=["96","97","98","99"]
        let mComponents = lines[videoMLineIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
        guard mComponents.count > 3 else { return sdp }
        let headerParts = Array(mComponents.prefix(3))
        var payloadTypes = Array(mComponents.dropFirst(3))

        // Build map of payload type → SDP codec name from a=rtpmap lines in the video section
        var ptToCodec: [String: String] = [:]
        var inVideoSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("m=") { inVideoSection = trimmed.hasPrefix("m=video"); continue }
            guard inVideoSection, trimmed.hasPrefix("a=rtpmap:") else { continue }
            // "a=rtpmap:96 H264/90000" → pt="96", codec="H264"
            let rest = String(trimmed.dropFirst("a=rtpmap:".count))
            let parts = rest.components(separatedBy: " ")
            if parts.count >= 2, let codecName = parts[1].components(separatedBy: "/").first {
                ptToCodec[parts[0]] = codecName.uppercased()
            }
        }

        // Partition: preferred codec payload types first, others after
        let preferred = preferredSDPCodecName.uppercased()
        let preferredPTs = payloadTypes.filter { ptToCodec[$0]?.uppercased() == preferred }
        guard !preferredPTs.isEmpty else { return sdp }  // codec not in offer — no change
        let otherPTs    = payloadTypes.filter { ptToCodec[$0]?.uppercased() != preferred }
        payloadTypes = preferredPTs + otherPTs

        // Rewrite m=video line
        lines[videoMLineIndex] = (headerParts + payloadTypes).joined(separator: " ")
        return lines.joined(separator: "\n")
    }

    /// Pass-through for remote SDP (no modifications needed).
    public func processRemoteSDP(sdp: String) -> String {
        sdp
    }

    /// Formats SDP for readable diagnostics while redacting transport secrets.
    public func formatSDPForLogging(sdp: String, redactSensitive: Bool = true) -> String {
        let normalized = sdp
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rawLines = normalized.components(separatedBy: "\n")
        var output: [String] = []

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("m="), !output.isEmpty {
                output.append("")
            }

            output.append(redactSensitive ? redactSDPLogLine(line) : line)
        }

        return output.joined(separator: "\n")
    }

    private func redactSDPLogLine(_ line: String) -> String {
        if line.hasPrefix("a=ice-ufrag:") {
            return "a=ice-ufrag:<redacted>"
        }
        if line.hasPrefix("a=ice-pwd:") {
            return "a=ice-pwd:<redacted>"
        }
        if line.hasPrefix("a=fingerprint:") {
            let prefix = line.components(separatedBy: " ").prefix(1).joined(separator: " ")
            return prefix + " <redacted>"
        }
        if line.hasPrefix("a=candidate:") {
            return "a=candidate:<redacted>"
        }
        return line
    }

    // MARK: - Opus stereo fmtp

    /// Adds `stereo=1` only to Opus fmtp lines and only when absent.
    /// This avoids broad string replacements that can touch unrelated codec parameters.
    private func enableOpusStereo(sdp: String) -> String {
        var lines = sdp.components(separatedBy: "\n")
        var opusPayloadTypes = Set<String>()

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("a=rtpmap:") else { continue }
            let rest = String(line.dropFirst("a=rtpmap:".count))
            let parts = rest.components(separatedBy: " ")
            guard parts.count >= 2 else { continue }
            let payloadType = parts[0]
            let codecName = parts[1].components(separatedBy: "/").first?.uppercased() ?? ""
            if codecName == "OPUS" {
                opusPayloadTypes.insert(payloadType)
            }
        }

        guard !opusPayloadTypes.isEmpty else { return sdp }

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("a=fmtp:") else { continue }
            let rest = String(trimmed.dropFirst("a=fmtp:".count))
            let parts = rest.components(separatedBy: " ")
            guard let payloadType = parts.first, opusPayloadTypes.contains(payloadType) else { continue }
            guard parts.count >= 2 else { continue }

            var parameters = parts.dropFirst().joined(separator: " ")
            if parameters.range(of: "stereo=1", options: .caseInsensitive) == nil {
                if parameters.isEmpty {
                    parameters = "stereo=1"
                } else {
                    parameters.append(";stereo=1")
                }
                lines[index] = "a=fmtp:\(payloadType) \(parameters)"
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Bitrate injection

    /// Injects a `b=AS:{kbps}` line after the `m={type}` line in the SDP.
    /// Mirrors sdp.ts _setBitrate().
    private func setBitrate(sdp: String, mediaType: String, bitrateKbps: Int) -> String {
        var lines = sdp.components(separatedBy: "\n")
        var mediaLineIndex = -1

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("m=\(mediaType)") {
                mediaLineIndex = i
                break
            }
        }
        guard mediaLineIndex >= 0 else { return sdp }

        var insertIndex = mediaLineIndex + 1
        // Skip i= and c= lines
        while insertIndex < lines.count &&
              (lines[insertIndex].hasPrefix("i=") || lines[insertIndex].hasPrefix("c=")) {
            insertIndex += 1
        }

        let bLine = "b=AS:\(bitrateKbps)"
        if insertIndex < lines.count && lines[insertIndex].hasPrefix("b=") {
            lines[insertIndex] = bLine
        } else {
            lines.insert(bLine, at: insertIndex)
        }
        return lines.joined(separator: "\n")
    }

    private func setVideoMaxFrameRate(sdp: String, maxFrameRate: Int) -> String {
        var lines = sdp.components(separatedBy: "\n")
        guard let mediaStart = lines.firstIndex(where: { $0.hasPrefix("m=video") }) else { return sdp }
        let mediaEnd = lines[(mediaStart + 1)...].firstIndex(where: { $0.hasPrefix("m=") }) ?? lines.count

        for idx in mediaStart..<mediaEnd where lines[idx].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("a=max-fr:") {
            lines[idx] = "a=max-fr:\(maxFrameRate)"
            return lines.joined(separator: "\n")
        }

        var insertIndex = mediaStart + 1
        while insertIndex < mediaEnd {
            let trimmed = lines[insertIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("c=") || trimmed.hasPrefix("i=") || trimmed.hasPrefix("b=") {
                insertIndex += 1
                continue
            }
            break
        }
        lines.insert("a=max-fr:\(maxFrameRate)", at: insertIndex)
        return lines.joined(separator: "\n")
    }

    private func overrideH264ProfileLevelId(sdp: String, profileLevelId: String) -> String {
        var lines = sdp.components(separatedBy: "\n")
        var inVideoSection = false
        var h264PayloadType: String?

        // First H264 payload in m=video order.
        if let videoMLine = lines.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("m=video") }) {
            let components = videoMLine.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
            if components.count > 3 {
                let payloadTypes = Array(components.dropFirst(3))
                var ptToCodec: [String: String] = [:]
                for raw in lines {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("m=") {
                        inVideoSection = trimmed.hasPrefix("m=video")
                        continue
                    }
                    guard inVideoSection, trimmed.hasPrefix("a=rtpmap:") else { continue }
                    let rest = String(trimmed.dropFirst("a=rtpmap:".count))
                    let parts = rest.components(separatedBy: " ")
                    guard parts.count >= 2 else { continue }
                    let payloadType = parts[0]
                    let codecName = parts[1].components(separatedBy: "/").first?.uppercased() ?? ""
                    ptToCodec[payloadType] = codecName
                }
                h264PayloadType = payloadTypes.first(where: { ptToCodec[$0] == "H264" })
            }
        }

        guard let targetPayloadType = h264PayloadType else { return sdp }

        for idx in lines.indices {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("a=fmtp:") else { continue }
            let rest = String(trimmed.dropFirst("a=fmtp:".count))
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard let payloadType = parts.first, payloadType == targetPayloadType else { continue }

            let paramsString = parts.count == 2 ? parts[1] : ""
            var params = paramsString.split(separator: ";").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }

            var replaced = false
            for i in params.indices {
                if params[i].lowercased().hasPrefix("profile-level-id=") {
                    params[i] = "profile-level-id=\(profileLevelId)"
                    replaced = true
                    break
                }
            }
            if !replaced {
                params.insert("profile-level-id=\(profileLevelId)", at: 0)
            }

            let joined = params.joined(separator: ";")
            lines[idx] = "a=fmtp:\(payloadType) \(joined)"
            break
        }

        return lines.joined(separator: "\n")
    }
}
