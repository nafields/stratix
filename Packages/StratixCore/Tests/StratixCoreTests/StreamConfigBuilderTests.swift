// StreamConfigBuilderTests.swift
// Exercises stream config builder behavior.
//

import Testing
@testable import StratixCore
import XCloudAPI

@MainActor
@Suite(.serialized)
struct StreamConfigBuilderTests {
    @Test
    func resolveProfile_normalizesLegacyQualityPreset() {
        let builder = StreamConfigBuilder()
        var settings = SettingsStore.StreamSettings()
        settings.qualityPreset = "Low"

        let result = builder.resolveProfile(streamSettings: settings)

        #expect(result.profile.qualityPreset == "Low Data")
        #expect(result.profile.profileId == .p720)
        #expect(result.profile.maxVideoBitrateKbps == 8_000)
        #expect(result.migrationNote != nil)
    }

    @Test
    func resolveProfile_appliesManualBitrateForBalancedPreset() {
        let builder = StreamConfigBuilder()
        var settings = SettingsStore.StreamSettings()
        settings.qualityPreset = "Balanced"
        settings.preferredResolution = "1440p"
        settings.bitrateCapMbps = 18.5

        let result = builder.resolveProfile(streamSettings: settings)

        #expect(result.profile.profileId == .p1440)
        #expect(result.profile.maxVideoBitrateKbps == 18_500)
        #expect(result.profile.bitrateCapSource == "manual override")
    }

    @Test
    func resolveProfile_highQualityStopsAt1440p() {
        let builder = StreamConfigBuilder()
        var settings = SettingsStore.StreamSettings()
        settings.qualityPreset = "High Quality"

        let result = builder.resolveProfile(streamSettings: settings)

        #expect(result.profile.profileId == .p1440)
        #expect(result.profile.apiResolutionMode == .p1440)
    }

    @Test
    func resolveProfile_clampsUnsupportedResolutionAndFrameRate() {
        let builder = StreamConfigBuilder()
        var settings = SettingsStore.StreamSettings()
        settings.qualityPreset = "Balanced"
        settings.preferredResolution = "4K"
        settings.preferredFPS = "120"

        let result = builder.resolveProfile(streamSettings: settings)

        #expect(result.profile.profileId == .p1080)
        #expect(result.profile.preferredFPS == 60)
    }

    @Test
    func makeStreamPreferences_normalizesOSNameOverride() {
        let builder = StreamConfigBuilder()
        var settings = SettingsStore.StreamSettings()
        settings.clientProfileOSName = "Windows"
        let profile = builder.resolveProfile(streamSettings: settings).profile

        let prefs = builder.makeStreamPreferences(
            profile: profile,
            streamSettings: settings,
            preferredRegionId: "eastus"
        )

        #expect(prefs.preferredRegionId == "eastus")
        #expect(prefs.osNameOverride == "windows")
    }

    @Test
    func makeStreamingConfig_propagatesUpscalingToggle() {
        let builder = StreamConfigBuilder()
        var settings = SettingsStore.StreamSettings()
        settings.upscalingEnabled = false
        let profile = builder.resolveProfile(streamSettings: settings).profile

        let config = builder.makeStreamingConfig(profile: profile, streamSettings: settings)

        #expect(config.upscalingEnabled == false)
        #expect(config.messageChannelDimensions == profile.dimensions)
        #expect(Int(config.videoDimensionsHint.width) == profile.dimensions.width)
        #expect(Int(config.videoDimensionsHint.height) == profile.dimensions.height)
    }
}
