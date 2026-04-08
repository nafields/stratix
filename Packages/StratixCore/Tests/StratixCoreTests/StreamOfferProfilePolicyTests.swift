// StreamOfferProfilePolicyTests.swift
// Exercises stream offer profile policy behavior.
//

import Testing
@testable import StratixCore
import XCloudAPI

@Suite(.serialized)
struct StreamOfferProfilePolicyTests {
    @Test
    func resolvedCloudOfferProfile_usesResolvedStreamProfileWhenHardcodedOverrideIsDisabled() {
        var streamSettings = SettingsStore.StreamSettings()
        streamSettings.qualityPreset = "High Quality"
        streamSettings.regionOverride = "Auto"

        let decision = StreamOfferProfilePolicy(
            forceHardcodedCloudOfferProfile: { false }
        ).resolvedCloudOfferProfile(
            configBuilder: StreamConfigBuilder(),
            streamSettings: streamSettings,
            availableRegions: [LoginRegion(name: "weu", baseUri: "https://weu.example.com", isDefault: true)],
            regionSelectionPolicy: StreamRegionSelectionPolicy(),
            preferredRegionID: "weu"
        )

        #expect(decision.profile.qualityPreset == "High Quality")
        #expect(decision.preferences.preferredRegionId == "weu")
        #expect(decision.migrationNote == nil)
    }

    @Test
    func resolvedCloudOfferProfile_usesHardcodedOfferProfileWhenOverrideIsEnabled() {
        let decision = StreamOfferProfilePolicy(
            forceHardcodedCloudOfferProfile: { true }
        ).resolvedCloudOfferProfile(
            configBuilder: StreamConfigBuilder(),
            streamSettings: SettingsStore.StreamSettings(),
            availableRegions: [LoginRegion(name: "eastus", baseUri: "https://east.example.com", isDefault: true)],
            regionSelectionPolicy: StreamRegionSelectionPolicy(),
            preferredRegionID: nil
        )

        #expect(decision.profile.profileId == .p1440)
        #expect(decision.preferences.preferredRegionId == "eastus")
        #expect(decision.migrationNote == nil)
    }
}
