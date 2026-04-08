// RegionPreferenceResolver.swift
// Defines region preference resolver.
//

import Foundation
import XCloudAPI

public final class RegionPreferenceResolver: Sendable {
    public struct Selection: Sendable {
        public let regionId: String?
        public let diagnosticsNote: String?

        public init(regionId: String?, diagnosticsNote: String?) {
            self.regionId = regionId
            self.diagnosticsNote = diagnosticsNote
        }
    }

    public init() {}

    public func effectiveSelection(
        streamSettings: SettingsStore.StreamSettings,
        availableRegions: [LoginRegion]
    ) -> Selection {
        StreamRegionSelectionPolicy().effectiveSelection(
            streamSettings: streamSettings,
            availableRegions: availableRegions
        )
    }

    public func regionOverrideDiagnostics(rawValue: String, availableRegions: [LoginRegion]) -> String? {
        StreamRegionSelectionPolicy().regionOverrideDiagnostics(
            rawValue: rawValue,
            availableRegions: availableRegions
        )
    }

    public func preferredRegion(
        from availableRegions: [LoginRegion],
        preference preferredRegionID: String?
    ) -> LoginRegion? {
        StreamRegionSelectionPolicy().preferredRegion(
            from: availableRegions,
            preference: preferredRegionID
        )
    }

    public func preferredRegionName(
        preferredTokens: [String],
        fallback: String,
        availableRegions: [LoginRegion]
    ) -> String {
        StreamRegionSelectionPolicy().preferredRegionName(
            preferredTokens: preferredTokens,
            fallback: fallback,
            availableRegions: availableRegions
        )
    }

    public func resolvedCloudStreamHost(
        tokens: StreamTokens,
        preferredRegionIDOverride: String?,
        availableRegions: [LoginRegion],
        fallbackHost: String
    ) -> (host: String, usedFallbackBecauseNoStoredHost: Bool) {
        StreamRegionSelectionPolicy().resolvedCloudHost(
            tokens: tokens,
            preferredRegionIDOverride: preferredRegionIDOverride,
            availableRegions: availableRegions,
            fallbackHost: fallbackHost
        )
    }
}
