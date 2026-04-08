// RegionPreferenceResolverTests.swift
// Exercises region preference resolver behavior.
//

import Testing
@testable import StratixCore
import XCloudAPI

@MainActor
@Suite(.serialized)
struct RegionPreferenceResolverTests {
    @Test
    func effectiveSelection_mapsGuideOverrideWhenRegionExists() {
        let resolver = RegionPreferenceResolver()
        var settings = SettingsStore.StreamSettings()
        settings.regionOverride = "US East"
        let regions = [
            LoginRegion(name: "eastus", baseUri: "https://eastus.example.com", isDefault: false),
            LoginRegion(name: "westus", baseUri: "https://westus.example.com", isDefault: true)
        ]

        let selection = resolver.effectiveSelection(streamSettings: settings, availableRegions: regions)

        #expect(selection.regionId == "eastus")
        #expect(selection.diagnosticsNote == nil)
    }

    @Test
    func effectiveSelection_fallsBackWhenOverrideUnavailable() {
        let resolver = RegionPreferenceResolver()
        var settings = SettingsStore.StreamSettings()
        settings.regionOverride = "UK"
        let regions = [
            LoginRegion(name: "eastus", baseUri: "https://eastus.example.com", isDefault: true)
        ]

        let selection = resolver.effectiveSelection(streamSettings: settings, availableRegions: regions)

        #expect(selection.regionId == nil)
        #expect(selection.diagnosticsNote != nil)
    }

    @Test
    func resolvedCloudStreamHost_usesFallbackWhenNoStoredHost() {
        let resolver = RegionPreferenceResolver()
        let tokens = StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: nil,
            webToken: nil,
            webTokenUHS: nil,
            xcloudRegions: []
        )

        let resolved = resolver.resolvedCloudStreamHost(
            tokens: tokens,
            preferredRegionIDOverride: nil,
            availableRegions: [],
            fallbackHost: "https://fallback.example.com"
        )

        #expect(resolved.host == "https://fallback.example.com")
        #expect(resolved.usedFallbackBecauseNoStoredHost == true)
    }
}
