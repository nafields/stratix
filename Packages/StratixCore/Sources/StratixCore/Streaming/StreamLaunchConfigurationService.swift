// StreamLaunchConfigurationService.swift
// Defines stream launch configuration service for the Streaming surface.
//

import Foundation
import StratixModels
import StreamingCore
import XCloudAPI

struct StreamLaunchConfiguration: Sendable {
    let profile: StreamConfigBuilder.ResolvedStreamProfile
    let config: StreamingConfig
    let preferences: StreamPreferences
    let resolvedHost: String?
    let diagnosticsLines: [String]
    let diagnosticsNote: String?
    let migrationNote: String?
}

struct StreamLaunchConfigurationService: Sendable {
    private let configBuilder: StreamConfigBuilder
    private let regionSelectionPolicy: StreamRegionSelectionPolicy
    private let offerProfilePolicy: StreamOfferProfilePolicy

    init(
        configBuilder: StreamConfigBuilder = StreamConfigBuilder(),
        regionSelectionPolicy: StreamRegionSelectionPolicy = StreamRegionSelectionPolicy(),
        offerProfilePolicy: StreamOfferProfilePolicy = StreamOfferProfilePolicy()
    ) {
        self.configBuilder = configBuilder
        self.regionSelectionPolicy = regionSelectionPolicy
        self.offerProfilePolicy = offerProfilePolicy
    }

    func resolvedHomeLaunchConfiguration(
        environment: StreamLaunchEnvironment
    ) -> StreamLaunchConfiguration {
        let resolved = configBuilder.resolveProfile(streamSettings: environment.streamSettings)
        let preferences = configBuilder.makeStreamPreferences(
            profile: resolved.profile,
            streamSettings: environment.streamSettings,
            preferredRegionId: regionSelectionPolicy.effectiveSelection(
                streamSettings: environment.streamSettings,
                availableRegions: environment.availableRegions
            ).regionId
        )
        let config = configBuilder.makeStreamingConfig(profile: resolved.profile, streamSettings: environment.streamSettings)
        let diagnosticsLines = configBuilder.makeDiagnosticLogLines(
            config: config,
            preferences: preferences,
            profile: resolved.profile,
            kind: "home",
            targetId: "home",
            streamSettings: environment.streamSettings,
            diagnosticsSettings: environment.diagnosticsSettings,
            controllerSettings: environment.controllerSettings
        )
        return StreamLaunchConfiguration(
            profile: resolved.profile,
            config: config,
            preferences: preferences,
            resolvedHost: nil,
            diagnosticsLines: diagnosticsLines,
            diagnosticsNote: nil,
            migrationNote: resolved.migrationNote
        )
    }

    func resolvedHomeLaunchConfigurationOffMain(
        environment: StreamLaunchEnvironment
    ) async -> StreamLaunchConfiguration {
        await Task.detached(priority: .userInitiated) { [self, environment] in
            resolvedHomeLaunchConfiguration(environment: environment)
        }.value
    }

    func resolvedCloudLaunchConfiguration(
        environment: StreamLaunchEnvironment,
        tokens: StreamTokens,
        targetId: String
    ) -> StreamLaunchConfiguration {
        let streamSettings = environment.streamSettings
        let availableRegions = environment.availableRegions
        let selection = regionSelectionPolicy.effectiveSelection(
            streamSettings: streamSettings,
            availableRegions: availableRegions
        )

        let offerProfile = offerProfilePolicy.resolvedCloudOfferProfile(
            configBuilder: configBuilder,
            streamSettings: streamSettings,
            availableRegions: availableRegions,
            regionSelectionPolicy: regionSelectionPolicy,
            preferredRegionID: selection.regionId
        )

        let resolvedHost = regionSelectionPolicy.resolvedCloudHost(
            tokens: tokens,
            preferredRegionIDOverride: offerProfile.preferences.preferredRegionId,
            availableRegions: availableRegions,
            fallbackHost: "https://xgpuweb.gssv-play-prod.xboxlive.com"
        )

        let diagnosticsLines = configBuilder.makeDiagnosticLogLines(
            config: offerProfile.config,
            preferences: offerProfile.preferences,
            profile: offerProfile.profile,
            kind: "cloud",
            targetId: targetId,
            streamSettings: streamSettings,
            diagnosticsSettings: environment.diagnosticsSettings,
            controllerSettings: environment.controllerSettings
        )

        return StreamLaunchConfiguration(
            profile: offerProfile.profile,
            config: offerProfile.config,
            preferences: offerProfile.preferences,
            resolvedHost: resolvedHost.host,
            diagnosticsLines: diagnosticsLines,
            diagnosticsNote: selection.diagnosticsNote,
            migrationNote: offerProfile.migrationNote
        )
    }

    func resolvedCloudLaunchConfigurationOffMain(
        environment: StreamLaunchEnvironment,
        tokens: StreamTokens,
        targetId: String
    ) async -> StreamLaunchConfiguration {
        await Task.detached(priority: .userInitiated) { [self, environment, tokens, targetId] in
            resolvedCloudLaunchConfiguration(
                environment: environment,
                tokens: tokens,
                targetId: targetId
            )
        }.value
    }

    func regionOverrideDiagnostics(
        rawValue: String,
        availableRegions: [LoginRegion]
    ) -> String? {
        regionSelectionPolicy.diagnostics(rawValue: rawValue, availableRegions: availableRegions)
    }
}
