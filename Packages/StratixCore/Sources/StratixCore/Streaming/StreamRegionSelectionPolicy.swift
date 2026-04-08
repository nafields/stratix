// StreamRegionSelectionPolicy.swift
// Defines stream region selection policy for the Streaming surface.
//

import Foundation
import XCloudAPI

struct StreamRegionSelectionPolicy: Sendable {
    typealias Selection = RegionPreferenceResolver.Selection
    
    init() {}

    func effectiveSelection(
        streamSettings: SettingsStore.StreamSettings,
        availableRegions: [LoginRegion]
    ) -> Selection {
        let guideOverrideRaw = streamSettings.regionOverride
        let normalized = guideOverrideRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized == "auto" || normalized.isEmpty {
            let preferredRegionId = streamSettings.preferredRegionID
            return Selection(
                regionId: preferredRegionId.isEmpty ? nil : preferredRegionId,
                diagnosticsNote: nil
            )
        }

        if let mapped = mapGuideRegionOverrideToRegionId(
            guideOverrideRaw,
            availableRegions: availableRegions
        ) {
            return Selection(regionId: mapped, diagnosticsNote: nil)
        }

        let requested = guideOverrideRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let note: String
        if availableRegions.isEmpty {
            note = "Region override '\(requested)' is unavailable because region metadata is not loaded yet. Falling back to Auto."
        } else {
            let preview = availableRegions.map(\.name).prefix(6).joined(separator: ", ")
            note = "Region override '\(requested)' is unavailable for this account. Falling back to Auto. Available: \(preview)"
        }
        return Selection(regionId: nil, diagnosticsNote: note)
    }

    func regionOverrideDiagnostics(rawValue: String, availableRegions: [LoginRegion]) -> String? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized != "auto", !normalized.isEmpty else { return nil }
        if mapGuideRegionOverrideToRegionId(rawValue, availableRegions: availableRegions) != nil {
            return nil
        }
        if availableRegions.isEmpty {
            return "The selected region will fall back to Auto until xCloud region metadata loads."
        }
        return "The selected region is not available for this account and will fall back to Auto."
    }

    func diagnostics(
        rawValue: String,
        availableRegions: [LoginRegion]
    ) -> String? {
        regionOverrideDiagnostics(rawValue: rawValue, availableRegions: availableRegions)
    }

    func preferredRegion(
        from availableRegions: [LoginRegion],
        preference preferredRegionID: String?
    ) -> LoginRegion? {
        guard !availableRegions.isEmpty else { return nil }
        let trimmedPreference = preferredRegionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPreference, !trimmedPreference.isEmpty {
            let lowered = trimmedPreference.lowercased()
            if let exact = availableRegions.first(where: { $0.name.lowercased() == lowered }) {
                return exact
            }
            if let contains = availableRegions.first(where: { $0.name.lowercased().contains(lowered) }) {
                return contains
            }
        }
        return availableRegions.first(where: \.isDefault) ?? availableRegions.first
    }

    func preferredRegionName(
        preferredTokens: [String],
        fallback: String,
        availableRegions: [LoginRegion]
    ) -> String {
        guard !availableRegions.isEmpty else { return fallback }
        let normalizedTokens = preferredTokens.map { $0.lowercased() }
        if let exact = availableRegions.first(where: { region in
            let lower = region.name.lowercased()
            return normalizedTokens.contains(where: { $0 == lower })
        }) {
            return exact.name
        }
        if let containsMatch = availableRegions.first(where: { region in
            let lower = region.name.lowercased()
            return normalizedTokens.contains(where: { lower.contains($0) })
        }) {
            return containsMatch.name
        }
        return fallback
    }

    func resolvedCloudHost(
        tokens: StreamTokens,
        preferredRegionIDOverride: String?,
        availableRegions: [LoginRegion],
        fallbackHost: String
    ) -> (host: String, usedFallbackBecauseNoStoredHost: Bool) {
        if let region = preferredRegion(from: availableRegions, preference: preferredRegionIDOverride) {
            return (region.baseUri, false)
        }
        guard let raw = tokens.xcloudHost, !raw.isEmpty else {
            return (fallbackHost, true)
        }
        return (raw, false)
    }

    private func mapGuideRegionOverrideToRegionId(
        _ rawValue: String,
        availableRegions: [LoginRegion]
    ) -> String? {
        guard !availableRegions.isEmpty else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized != "auto", !normalized.isEmpty else { return nil }

        let candidates: [String]
        switch normalized {
        case "us east":
            candidates = ["us east", "east us", "us-east", "eastus", "use", "na east"]
        case "us west":
            candidates = ["us west", "west us", "us-west", "westus", "usw", "na west"]
        case "europe":
            candidates = ["europe", "weu", "neu", "northeurope", "westeurope", "eu"]
        case "uk":
            candidates = ["uk", "united kingdom", "uk south", "uksouth", "uk west", "ukwest", "great britain"]
        default:
            return nil
        }

        let match = availableRegions.first { region in
            let regionName = region.name.lowercased()
            return candidates.contains { token in regionName.contains(token) }
        }
        return match?.name
    }
}
