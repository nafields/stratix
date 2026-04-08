// StreamRegionSelectionPolicyTests.swift
// Exercises stream region selection policy behavior.
//

import Testing
@testable import StratixCore
import XCloudAPI

@MainActor
@Suite(.serialized)
struct StreamRegionSelectionPolicyTests {
    @Test
    func effectiveSelection_mapsGuideOverrideWhenRegionExists() {
        let policy = StreamRegionSelectionPolicy()
        var settings = SettingsStore.StreamSettings()
        settings.regionOverride = "US East"
        let regions = [
            LoginRegion(name: "eastus", baseUri: "https://eastus.example.com", isDefault: false),
            LoginRegion(name: "westus", baseUri: "https://westus.example.com", isDefault: true)
        ]

        let selection = policy.effectiveSelection(streamSettings: settings, availableRegions: regions)

        #expect(selection.regionId == "eastus")
        #expect(selection.diagnosticsNote == nil)
    }

    @Test
    func effectiveSelection_fallsBackWhenOverrideUnavailable() {
        let policy = StreamRegionSelectionPolicy()
        var settings = SettingsStore.StreamSettings()
        settings.regionOverride = "UK"
        let regions = [
            LoginRegion(name: "eastus", baseUri: "https://eastus.example.com", isDefault: true)
        ]

        let selection = policy.effectiveSelection(streamSettings: settings, availableRegions: regions)

        #expect(selection.regionId == nil)
        #expect(selection.diagnosticsNote != nil)
    }

    @Test
    func resolvedCloudHost_usesFallbackWhenNoStoredHost() {
        let policy = StreamRegionSelectionPolicy()
        let tokens = StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: nil,
            webToken: nil,
            webTokenUHS: nil,
            xcloudRegions: []
        )

        let resolved = policy.resolvedCloudHost(
            tokens: tokens,
            preferredRegionIDOverride: nil,
            availableRegions: [],
            fallbackHost: "https://fallback.example.com"
        )

        #expect(resolved.host == "https://fallback.example.com")
        #expect(resolved.usedFallbackBecauseNoStoredHost == true)
    }
}
