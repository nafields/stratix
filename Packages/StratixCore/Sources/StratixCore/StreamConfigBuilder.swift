// StreamConfigBuilder.swift
// Defines stream config builder.
//

import Foundation
import StratixModels

public final class StreamConfigBuilder: Sendable {
    public struct ResolvedStreamProfile: Sendable {
        public let qualityPreset: String
        public let profileId: StreamResolutionProfileId
        public let apiResolutionMode: StreamResolutionMode
        public let dimensions: StreamDimensions
        public let preferredFPS: Int
        public let lowLatencyMode: Bool
        public let maxVideoBitrateKbps: Int?
        public let bitrateCapSource: String
    }

    public struct HardcodedCloudOfferProfile: Sendable {
        public let profile: ResolvedStreamProfile
        public let config: StreamingConfig
        public let preferences: StreamPreferences
    }

    public struct ProfileResolutionResult: Sendable {
        public let profile: ResolvedStreamProfile
        public let migrationNote: String?
    }

    public init() {}

    public func resolveProfile(streamSettings: SettingsStore.StreamSettings) -> ProfileResolutionResult {
        let rawQualityPreset = streamSettings.qualityPreset
        let qualityPreset = normalizedQualityPreset(rawQualityPreset)
        let isUnknownQualityPreset = !["Low Data", "Low", "Balanced", "High Quality", "High", "Competitive"].contains(rawQualityPreset)

        let preferredFPS = preferredFrameRate(from: streamSettings.preferredFPS)
        let preferredResolution = streamSettings.preferredResolution
        let lowLatencyPreference = streamSettings.lowLatencyMode
        let manualBitrateMbps = streamSettings.bitrateCapMbps

        let profileId: StreamResolutionProfileId
        let lowLatencyMode: Bool
        let maxVideoBitrateKbps: Int?
        let bitrateCapSource: String

        switch qualityPreset {
        case "Low Data":
            profileId = .p720
            lowLatencyMode = false
            maxVideoBitrateKbps = 8_000
            bitrateCapSource = "preset"
        case "High Quality":
            profileId = .p1440
            lowLatencyMode = true
            maxVideoBitrateKbps = 20_000
            bitrateCapSource = "preset"
        case "Competitive":
            profileId = .p1080
            lowLatencyMode = true
            maxVideoBitrateKbps = 12_000
            bitrateCapSource = "preset"
        default:
            if isUnknownQualityPreset {
                profileId = .p1080
                lowLatencyMode = true
                maxVideoBitrateKbps = nil
                bitrateCapSource = "none"
            } else {
                profileId = self.profileId(forResolution: preferredResolution)
                lowLatencyMode = lowLatencyPreference
                if manualBitrateMbps > 0 {
                    maxVideoBitrateKbps = Int(manualBitrateMbps * 1_000)
                    bitrateCapSource = "manual override"
                } else {
                    maxVideoBitrateKbps = nil
                    bitrateCapSource = "none"
                }
            }
        }

        let dimensions = dimensions(for: profileId)
        let profile = ResolvedStreamProfile(
            qualityPreset: qualityPreset,
            profileId: profileId,
            apiResolutionMode: apiResolutionMode(for: profileId),
            dimensions: dimensions,
            preferredFPS: qualityPreset == "Competitive" ? 60 : preferredFPS,
            lowLatencyMode: lowLatencyMode,
            maxVideoBitrateKbps: maxVideoBitrateKbps,
            bitrateCapSource: bitrateCapSource
        )

        let migrationNote: String? = rawQualityPreset == qualityPreset
            ? nil
            : "Legacy/unknown quality preset '\(rawQualityPreset)' migrated to '\(qualityPreset)'"

        return ProfileResolutionResult(profile: profile, migrationNote: migrationNote)
    }

    public func makeStreamingConfig(
        profile: ResolvedStreamProfile,
        streamSettings: SettingsStore.StreamSettings
    ) -> StreamingConfig {
        let preferredSdpCodec: String? = {
            switch streamSettings.codecPreference {
            case "VP9": return "VP9"
            case "VP8": return "VP8"
            case "H.265/HEVC": return "H265"
            default: return nil
            }
        }()

        let preferredColorRange: String? = streamSettings.colorRange == "Auto" ? nil : streamSettings.colorRange

        return StreamingConfig(
            preferredSdpCodec: preferredSdpCodec,
            maxVideoBitrateKbps: profile.maxVideoBitrateKbps,
            keyframeRequestIntervalSeconds: profile.lowLatencyMode ? 2 : 5,
            videoDimensionsHint: CGSizeValue(
                width: Double(profile.dimensions.width),
                height: Double(profile.dimensions.height)
            ),
            preferredFrameRate: profile.preferredFPS,
            lowLatencyModeEnabled: profile.lowLatencyMode,
            preferredColorRange: preferredColorRange,
            resolutionProfileId: profile.profileId,
            upscalingEnabled: streamSettings.upscalingEnabled,
            messageChannelDimensions: profile.dimensions
        )
    }

    public func makeStreamPreferences(
        profile: ResolvedStreamProfile,
        streamSettings: SettingsStore.StreamSettings,
        preferredRegionId: String?
    ) -> StreamPreferences {
        var prefs = StreamPreferences()
        prefs.resolution = profile.apiResolutionMode
        prefs.locale = streamSettings.locale
        prefs.preferIPv6 = streamSettings.preferIPv6
        prefs.preferredRegionId = preferredRegionId
        prefs.osNameOverride = normalizedClientProfileOSName(streamSettings.clientProfileOSName)
        return prefs
    }

    public func makeHardcodedCloudOfferProfile(preferredRegionName: String) -> HardcodedCloudOfferProfile {
        let dimensions = StreamDimensions(width: 2560, height: 1440)
        let profile = ResolvedStreamProfile(
            qualityPreset: "Competitive",
            profileId: .p1440,
            apiResolutionMode: .p1440,
            dimensions: dimensions,
            preferredFPS: 60,
            lowLatencyMode: true,
            maxVideoBitrateKbps: nil,
            bitrateCapSource: "none (uncapped hardcoded)"
        )

        let config = StreamingConfig(
            preferredSdpCodec: "H264",
            maxVideoBitrateKbps: nil,
            maxAudioBitrateKbps: nil,
            stereoAudioEnabled: true,
            keyframeRequestIntervalSeconds: 2,
            videoDimensionsHint: CGSizeValue(width: 2560, height: 1440),
            preferredFrameRate: 60,
            lowLatencyModeEnabled: true,
            preferredColorRange: nil,
            resolutionProfileId: .p1440,
            upscalingEnabled: true,
            messageChannelDimensions: dimensions,
            logLocalSDPOffer: true,
            requestedVideoMaxFrameRate: 60,
            h264FallbackProfileLevelId: "640c1f"
        )

        var preferences = StreamPreferences()
        preferences.resolution = .p1440
        preferences.locale = "en-US"
        preferences.preferIPv6 = false
        preferences.preferredRegionId = preferredRegionName
        preferences.fallbackRegionNames = ["eastus", "centralus", "westus2"]
        preferences.osNameOverride = "tizen"

        return HardcodedCloudOfferProfile(
            profile: profile,
            config: config,
            preferences: preferences
        )
    }

    public func makeDiagnosticLogLines(
        config: StreamingConfig,
        preferences: StreamPreferences,
        profile: ResolvedStreamProfile,
        kind: String,
        targetId: String,
        streamSettings: SettingsStore.StreamSettings,
        diagnosticsSettings: SettingsStore.DiagnosticsSettings,
        controllerSettings: SettingsStore.ControllerSettings
    ) -> [String] {
        let codecPref = config.preferredSdpCodec ?? "default (offer order)"
        let bitrateKbps = config.maxVideoBitrateKbps.map { "\($0) kbps" } ?? "unlimited"
        let keyframeInterval = config.keyframeRequestIntervalSeconds.map(String.init) ?? "none"
        let maxFrOverride = config.requestedVideoMaxFrameRate.map(String.init) ?? "none"
        let h264ProfileOverride = config.h264FallbackProfileLevelId ?? "none"
        let effectiveOSName = preferences.osNameOverride ?? preferences.resolution.osName

        return [
            "[STREAM CONFIG] ==========================================",
            "[STREAM CONFIG] Kind: \(kind) | Target: \(targetId)",
            "[STREAM CONFIG] Resolution: \(preferences.resolution.rawValue) (osName: \(effectiveOSName), \(preferences.resolution.displayWidth)x\(preferences.resolution.displayHeight))",
            "[STREAM CONFIG] Bitrate cap: \(bitrateKbps) | FPS: \(config.preferredFrameRate) | Keyframe interval: \(keyframeInterval)s",
            "[STREAM CONFIG] SDP overrides: max-fr=\(maxFrOverride) | H264 profile-level-id=\(h264ProfileOverride)",
            "[STREAM CONFIG] Low latency: \(config.lowLatencyModeEnabled) | Locale: \(preferences.locale)",
            "[STREAM CONFIG] Region: \(preferences.preferredRegionId ?? "auto (server default)") | IPv6: \(preferences.preferIPv6)",
            "[STREAM CONFIG] Quality preset: \(profile.qualityPreset) | Profile: \(profile.profileId.rawValue) | Codec pref: \(codecPref)",
            "[STREAM CONFIG] Signals api=\(preferences.resolution.displayWidth)x\(preferences.resolution.displayHeight) control=\(Int(config.videoDimensionsHint.width))x\(Int(config.videoDimensionsHint.height)) message=\(config.messageChannelDimensions.width)x\(config.messageChannelDimensions.height)",
            "[STREAM CONFIG] Bitrate source: \(profile.bitrateCapSource)",
            "[STREAM CONFIG] Upscaling: \(config.upscalingEnabled) | Floor: \(diagnosticsSettings.upscalingFloorBehavior.rawValue)",
            "[STREAM CONFIG] HDR: \(streamSettings.hdrEnabled) | Color range: \(streamSettings.colorRange)",
            "[STREAM CONFIG] Audio boost: \(String(format: "%.2f", streamSettings.audioBoost)) | Safe area: \(Int(streamSettings.safeAreaPercent))%",
            "[STREAM CONFIG] Vibration intensity: \(Int(controllerSettings.vibrationIntensity * 100))%",
            "[STREAM CONFIG] Stats HUD: \(streamSettings.showStreamStats) @ \(streamSettings.statsHUDPosition) | Block tracking: \(diagnosticsSettings.blockTracking)",
            "[STREAM CONFIG] =========================================="
        ]
    }

    public func normalizedClientProfileOSName(_ rawValue: String) -> String? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "auto":
            return nil
        case "android":
            return "android"
        case "windows":
            return "windows"
        case "tizen":
            return "tizen"
        default:
            return nil
        }
    }

    private func normalizedQualityPreset(_ rawValue: String) -> String {
        switch rawValue {
        case "Low Data", "Low":
            return "Low Data"
        case "Balanced":
            return "Balanced"
        case "High Quality", "High":
            return "High Quality"
        case "Competitive":
            return "Competitive"
        default:
            return "Balanced"
        }
    }

    private func profileId(forResolution resolution: String) -> StreamResolutionProfileId {
        switch resolution {
        case "720p":
            return .p720
        case "1440p":
            return .p1440
        default:
            return .p1080
        }
    }

    private func apiResolutionMode(for profileId: StreamResolutionProfileId) -> StreamResolutionMode {
        switch profileId {
        case .p720:
            return .p720
        case .p1080:
            return .p1080
        case .p1440:
            return .p1440
        case .p1080HQ:
            return .p1080HQ
        }
    }

    private func dimensions(for profileId: StreamResolutionProfileId) -> StreamDimensions {
        switch profileId {
        case .p720:
            return .init(width: 1280, height: 720)
        case .p1080:
            return .init(width: 1920, height: 1080)
        case .p1440:
            return .init(width: 2560, height: 1440)
        case .p1080HQ:
            return .init(width: 3840, height: 2160)
        }
    }

    private func preferredFrameRate(from rawValue: String) -> Int {
        if let value = Int(rawValue) {
            if value <= 30 {
                return 30
            }
            return 60
        }
        return 60
    }
}
