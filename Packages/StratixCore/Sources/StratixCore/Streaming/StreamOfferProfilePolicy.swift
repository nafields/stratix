// StreamOfferProfilePolicy.swift
// Defines stream offer profile policy for the Streaming surface.
//

import Foundation
import StratixModels
import XCloudAPI

struct StreamResolvedCloudOfferProfile: Sendable {
    let profile: StreamConfigBuilder.ResolvedStreamProfile
    let config: StreamingConfig
    let preferences: StreamPreferences
    let migrationNote: String?
}

struct StreamOfferProfilePolicy: Sendable {
    private let forceHardcodedCloudOfferProfile: @Sendable () -> Bool

    init(
        forceHardcodedCloudOfferProfile: @escaping @Sendable () -> Bool = {
            #if DEBUG
            UserDefaults.standard.bool(forKey: "stratix.debug.forceHardcodedCloudOfferProfile")
            #else
            false
            #endif
        }
    ) {
        self.forceHardcodedCloudOfferProfile = forceHardcodedCloudOfferProfile
    }

    func shouldForceHardcodedCloudOfferProfile() -> Bool {
        forceHardcodedCloudOfferProfile()
    }

    func makeHardcodedCloudOfferProfile(
        configBuilder: StreamConfigBuilder,
        preferredRegionName: String
    ) -> StreamConfigBuilder.HardcodedCloudOfferProfile {
        configBuilder.makeHardcodedCloudOfferProfile(preferredRegionName: preferredRegionName)
    }

    func resolvedCloudOfferProfile(
        configBuilder: StreamConfigBuilder,
        streamSettings: SettingsStore.StreamSettings,
        availableRegions: [LoginRegion],
        regionSelectionPolicy: StreamRegionSelectionPolicy,
        preferredRegionID: String?
    ) -> StreamResolvedCloudOfferProfile {
        if shouldForceHardcodedCloudOfferProfile() {
            let hardcoded = makeHardcodedCloudOfferProfile(
                configBuilder: configBuilder,
                preferredRegionName: regionSelectionPolicy.preferredRegionName(
                    preferredTokens: ["eastus", "east us", "us east", "eus", "east us 2", "us east 2"],
                    fallback: "eastus",
                    availableRegions: availableRegions
                )
            )
            return StreamResolvedCloudOfferProfile(
                profile: hardcoded.profile,
                config: hardcoded.config,
                preferences: hardcoded.preferences,
                migrationNote: nil
            )
        }

        let resolved = configBuilder.resolveProfile(streamSettings: streamSettings)
        return StreamResolvedCloudOfferProfile(
            profile: resolved.profile,
            config: configBuilder.makeStreamingConfig(
                profile: resolved.profile,
                streamSettings: streamSettings
            ),
            preferences: configBuilder.makeStreamPreferences(
                profile: resolved.profile,
                streamSettings: streamSettings,
                preferredRegionId: preferredRegionID
            ),
            migrationNote: resolved.migrationNote
        )
    }
}
