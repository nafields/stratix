// StreamLaunchConfigurationServiceTests.swift
// Exercises stream launch configuration service behavior.
//

import Foundation
import Testing
@testable import StratixCore
import XCloudAPI

@Suite(.serialized)
struct StreamLaunchConfigurationServiceTests {
    @Test
    func resolvedHomeLaunchConfiguration_buildsConfigAndPreferences() {
        let service = StreamLaunchConfigurationService()
        let launch = service.resolvedHomeLaunchConfiguration(
            environment: makeStreamLaunchEnvironment()
        )

        #expect(launch.profile.qualityPreset.isEmpty == false)
        #expect(launch.config.preferredFrameRate > 0)
        #expect(launch.preferences.locale.isEmpty == false)
        #expect(launch.resolvedHost == nil)
    }

    @Test
    func resolvedCloudLaunchConfiguration_usesRegionSelectionPolicyForPreferredHost() {
        var streamSettings = SettingsStore.StreamSettings()
        streamSettings.regionOverride = "Auto"
        streamSettings.preferredRegionID = "weu"
        let environment = makeStreamLaunchEnvironment(
            streamSettings: streamSettings,
            availableRegions: [
            LoginRegion(name: "weu", baseUri: "https://weu.example.com", isDefault: true)
            ]
        )

        let service = StreamLaunchConfigurationService()
        let launch = service.resolvedCloudLaunchConfiguration(
            environment: environment,
            tokens: StreamTokens(
                xhomeToken: "xhome",
                xhomeHost: "https://xhome.example.com",
                xcloudToken: "xcloud",
                xcloudHost: "https://fallback.example.com",
                webToken: nil,
                webTokenUHS: nil,
                xcloudRegions: []
            ),
            targetId: "1234"
        )

        #expect(launch.resolvedHost == "https://weu.example.com")
        #expect(launch.diagnosticsLines.isEmpty == false)
    }

    @Test
    func resolvedCloudLaunchConfiguration_usesHardcodedOfferProfileWhenEnabled() {
        let defaults = UserDefaults.standard
        let key = "stratix.debug.forceHardcodedCloudOfferProfile"
        let oldValue = defaults.object(forKey: key)
        defaults.set(true, forKey: key)
        defer {
            if let oldValue {
                defaults.set(oldValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let environment = makeStreamLaunchEnvironment(
            availableRegions: [LoginRegion(name: "eastus", baseUri: "https://east.example.com", isDefault: true)]
        )
        let service = StreamLaunchConfigurationService()
        let launch = service.resolvedCloudLaunchConfiguration(
            environment: environment,
            tokens: StreamTokens(
                xhomeToken: "xhome",
                xhomeHost: "https://xhome.example.com",
                xcloudToken: "xcloud",
                xcloudHost: "https://fallback.example.com",
                webToken: nil,
                webTokenUHS: nil,
                xcloudRegions: []
            ),
            targetId: "1234"
        )

        #expect(launch.resolvedHost == "https://east.example.com")
        #expect(launch.profile.qualityPreset.isEmpty == false)
    }
}
