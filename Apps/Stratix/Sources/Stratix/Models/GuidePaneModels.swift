// GuidePaneModels.swift
// Defines the guide pane models.
//

import SwiftUI
import StratixCore
import StratixModels

/// Enumerates the guide overlay panes that can be shown from the in-stream guide.
enum GuideOverlayPane: String, CaseIterable, Identifiable {
    case overview
    case stream
    case controller
    case videoAudio
    case interface
    case diagnostics

    var id: String { rawValue }

    /// Provides the user-facing pane title shown in the guide sidebar.
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .stream: return "Cloud Stream Settings"
        case .controller: return "Controller"
        case .videoAudio: return "Video / Audio"
        case .interface: return "Interface / Accessibility"
        case .diagnostics: return "Diagnostics / Advanced"
        }
    }

    /// Provides the sidebar/supporting copy used to explain each guide pane at a glance.
    var subtitle: String {
        switch self {
        case .overview:
            return "Profile, quick actions, and controller guide controls"
        case .stream:
            return "Quality, codec, bitrate, latency, and stream overlay settings"
        case .controller:
            return "Input feel, mappings, deadzone, and sensitivity tuning"
        case .videoAudio:
            return "Display and audio preferences modeled after the web client"
        case .interface:
            return "TV comfort and guide presentation controls"
        case .diagnostics:
            return "Advanced diagnostics and debug toggles"
        }
    }

    /// Maps each pane to the SF Symbol used in the guide sidebar.
    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .stream: return "cloud.fill"
        case .controller: return "gamecontroller.fill"
        case .videoAudio: return "display"
        case .interface: return "figure.wave"
        case .diagnostics: return "wrench.and.screwdriver.fill"
        }
    }
}

/// Captures the focusable guide-sidebar destinations used by the overlay’s focus system.
enum GuideSidebarFocusTarget: Hashable {
    case destination(AppShellSection)
    case pane(GuideOverlayPane)
    case settingsMode
    case closeGuide
}

/// Controls whether the guide exposes only the basic pane set or the full advanced configuration surface.
enum GuideSettingsMode: String, CaseIterable {
    case basic
    case advanced

    /// Provides the user-facing label for the current guide settings mode.
    var title: String {
        switch self {
        case .basic:
            return "Basic"
        case .advanced:
            return "Advanced"
        }
    }
}

/// Describes one guide setting row, including where it belongs and whether it is live, guide-only, or persisted-only.
struct GuideSettingDefinition: Identifiable, Hashable {
    /// Groups settings by the guide pane that renders them.
    enum Scope: String, Hashable {
        case stream
        case controller
        case videoAudio
        case interface
        case diagnostics
    }

    /// Explains whether a setting currently affects live runtime state, guide-only state, or only persisted settings.
    enum WiringState: String, Hashable {
        case appliedNow
        case guideOnly
        case savedOnly

        var label: String {
            switch self {
            case .appliedNow:
                return "Applied now"
            case .guideOnly:
                return "Guide only"
            case .savedOnly:
                return "Saved only"
            }
        }
    }

    let id: String
    let title: String
    let wiringState: WiringState
    let scope: Scope
    let defaultValue: String
    let description: String
}

/// Provides guide-overlay-only derivations such as pane visibility, pane restoration, and stream presentation summaries.
struct StreamGuideOverlayState: Equatable {
    /// Captures the normalized stream settings presentation used by the guide overview and stream panes.
    struct StreamPresentation: Equatable {
        let normalizedQualityPreset: String
        let effectiveStreamProfileLabel: String
        let normalizedClientProfileSelection: String
        let effectiveClientProfileOSName: String
        let streamConfigConflictWarning: String?
        let effectiveVideoBitrateCapKbps: Int?
        let bitrateCapSourceLabel: String
    }

    /// Returns the panes that should be visible for the current guide mode.
    static func visiblePanes(for settingsMode: GuideSettingsMode) -> [GuideOverlayPane] {
        settingsMode == .basic ? basicVisiblePanes : GuideOverlayPane.allCases
    }

    /// Resolves the pane that should be shown after applying requested overrides, remembered state, and mode filtering.
    static func resolvedSelectedPane(
        requestedPaneRawValue: String?,
        lastPaneRawValue: String,
        rememberLastSection: Bool,
        settingsMode: GuideSettingsMode
    ) -> GuideOverlayPane {
        let visible = visiblePanes(for: settingsMode)
        let requestedPane = requestedPaneRawValue.flatMap(GuideOverlayPane.init(rawValue:))
        let rememberedPane = rememberLastSection ? GuideOverlayPane(rawValue: lastPaneRawValue) : nil
        let preferredPane = requestedPane ?? rememberedPane ?? .overview
        return visible.contains(preferredPane) ? preferredPane : (visible.first ?? .overview)
    }

    /// Toggles between the basic and advanced guide mode selections.
    static func toggledSettingsMode(from settingsMode: GuideSettingsMode) -> GuideSettingsMode {
        settingsMode == .basic ? .advanced : .basic
    }

    /// Builds the compact per-pane summary string from the wiring-state counts for that pane’s settings.
    static func paneSettingSummaryText(
        selectedPane: GuideOverlayPane,
        definitionsByScope: [GuideSettingDefinition.Scope: [GuideSettingDefinition]]
    ) -> String? {
        let scope = paneScope(for: selectedPane)
        guard let scope else { return nil }
        let definitions = definitionsByScope[scope] ?? []
        guard !definitions.isEmpty else { return nil }

        let appliedNowCount = definitions.filter { $0.wiringState == .appliedNow }.count
        let guideOnlyCount = definitions.filter { $0.wiringState == .guideOnly }.count
        let savedOnlyCount = definitions.filter { $0.wiringState == .savedOnly }.count
        let segments = [
            appliedNowCount > 0 ? "\(appliedNowCount) applied now" : nil,
            guideOnlyCount > 0 ? "\(guideOnlyCount) guide only" : nil,
            savedOnlyCount > 0 ? "\(savedOnlyCount) saved only" : nil
        ].compactMap { $0 }
        return segments.isEmpty ? nil : segments.joined(separator: " • ")
    }

    private static let basicVisiblePanes: [GuideOverlayPane] = [.overview, .stream, .interface]

    /// Maps a visible guide pane onto the settings-definition scope that feeds its summary and rows.
    private static func paneScope(for pane: GuideOverlayPane) -> GuideSettingDefinition.Scope? {
        switch pane {
        case .overview:
            return nil
        case .stream:
            return .stream
        case .controller:
            return .controller
        case .videoAudio:
            return .videoAudio
        case .interface:
            return .interface
        case .diagnostics:
            return .diagnostics
        }
    }

    /// Normalizes raw stream settings into the guide-friendly profile labels and warnings shown in the stream pane.
    static func streamPresentation(
        streamSettings: SettingsStore.StreamSettings
    ) -> StreamPresentation {
        let normalizedQualityPreset: String = {
            switch streamSettings.qualityPreset {
            case "Low Data", "Low":
                return "Low Data"
            case "High Quality", "High":
                return "High Quality"
            case "Competitive":
                return "Competitive"
            default:
                return "Balanced"
            }
        }()

        let effectiveStreamProfileLabel: String = {
            switch normalizedQualityPreset {
            case "Low Data":
                return "720p60"
            case "High Quality":
                return "1440p60 High Quality"
            case "Competitive":
                return "1080p60 Low Latency"
            default:
                switch streamSettings.preferredResolution {
                case "720p":
                    return "720p60"
                case "1440p":
                    return "1440p60"
                default:
                    return streamSettings.lowLatencyMode ? "1080p60 Low Latency" : "1080p60"
                }
            }
        }()

        let normalizedClientProfileSelection: String = {
            switch streamSettings.clientProfileOSName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "android":
                return "Android"
            case "windows":
                return "Windows"
            case "tizen":
                return "Tizen"
            default:
                return "Auto"
            }
        }()

        let effectiveClientProfileOSName: String = {
            switch normalizedClientProfileSelection {
            case "Android":
                return "android"
            case "Windows":
                return "windows"
            case "Tizen":
                return "tizen"
            default:
                switch normalizedQualityPreset {
                case "Low Data":
                    return "android"
                case "High Quality":
                    return "tizen"
                case "Competitive":
                    return "windows"
                default:
                    switch streamSettings.preferredResolution {
                    case "720p":
                        return "android"
                    case "1440p":
                        return "tizen"
                    default:
                        return "windows"
                    }
                }
            }
        }()

        let streamConfigConflictWarning: String? = {
            switch normalizedQualityPreset {
            case "Low Data":
                return streamSettings.preferredResolution == "720p" ? nil : "Low Data enforces 720p profile; manual resolution applies only in Balanced."
            case "High Quality":
                return streamSettings.preferredResolution == "1440p" ? nil : "High Quality enforces a 1440p profile; manual resolution applies only in Balanced."
            case "Competitive":
                return streamSettings.preferredResolution == "1080p" ? nil : "Competitive enforces 1080p low-latency profile; manual resolution applies only in Balanced."
            default:
                return nil
            }
        }()

        let effectiveVideoBitrateCapKbps: Int? = {
            switch normalizedQualityPreset {
            case "Low Data":
                return 8_000
            case "High Quality":
                return 20_000
            case "Competitive":
                return 12_000
            default:
                return streamSettings.bitrateCapMbps > 0 ? Int(streamSettings.bitrateCapMbps * 1_000) : nil
            }
        }()

        let bitrateCapSourceLabel = normalizedQualityPreset != "Balanced"
            ? "preset"
            : (streamSettings.bitrateCapMbps > 0 ? "manual override" : "none")

        return StreamPresentation(
            normalizedQualityPreset: normalizedQualityPreset,
            effectiveStreamProfileLabel: effectiveStreamProfileLabel,
            normalizedClientProfileSelection: normalizedClientProfileSelection,
            effectiveClientProfileOSName: effectiveClientProfileOSName,
            streamConfigConflictWarning: streamConfigConflictWarning,
            effectiveVideoBitrateCapKbps: effectiveVideoBitrateCapKbps,
            bitrateCapSourceLabel: bitrateCapSourceLabel
        )
    }
}
