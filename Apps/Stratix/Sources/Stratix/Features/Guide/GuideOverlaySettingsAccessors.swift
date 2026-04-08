// GuideOverlaySettingsAccessors.swift
// Defines guide overlay settings accessors for the Features / Guide surface.
//

import SwiftUI
import StratixCore
import StratixModels

extension StreamGuideOverlayView {
    /// Derived stream presentation state used by the guide overlay rows and summary labels.
    private var streamPresentation: StreamGuideOverlayState.StreamPresentation {
        StreamGuideOverlayState.streamPresentation(streamSettings: settingsStore.stream)
    }

    /// Binds the diagnostics upscaling floor selector to the live settings store.
    var diagnosticsFloorBehaviorBinding: Binding<String> {
        Binding(
            get: { settingsStore.diagnostics.upscalingFloorBehavior.label },
            set: { newValue in
                guard let matched = UpscalingFloorBehavior.allCases.first(where: { $0.label == newValue }) else {
                    return
                }
                var diagnostics = settingsStore.diagnostics
                diagnostics.upscalingFloorBehavior = matched
                settingsStore.diagnostics = diagnostics
            }
        )
    }

    /// Produces a two-way binding into shell settings for guide rows.
    func shellBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.ShellSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.shell[keyPath: keyPath] },
            set: { newValue in
                var shell = settingsStore.shell
                shell[keyPath: keyPath] = newValue
                settingsStore.shell = shell
            }
        )
    }

    /// Produces a two-way binding into stream settings for guide rows.
    func streamBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.StreamSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.stream[keyPath: keyPath] },
            set: { newValue in
                var stream = settingsStore.stream
                stream[keyPath: keyPath] = newValue
                settingsStore.stream = stream
            }
        )
    }

    /// Produces a two-way binding into controller settings for guide rows.
    func controllerBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.ControllerSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.controller[keyPath: keyPath] },
            set: { newValue in
                var controller = settingsStore.controller
                controller[keyPath: keyPath] = newValue
                settingsStore.controller = controller
            }
        )
    }

    /// Produces a two-way binding into accessibility settings for guide rows.
    func accessibilityBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.AccessibilitySettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.accessibility[keyPath: keyPath] },
            set: { newValue in
                var accessibility = settingsStore.accessibility
                accessibility[keyPath: keyPath] = newValue
                settingsStore.accessibility = accessibility
            }
        )
    }

    /// Produces a two-way binding into diagnostics settings for guide rows.
    func diagnosticsBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.DiagnosticsSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.diagnostics[keyPath: keyPath] },
            set: { newValue in
                var diagnostics = settingsStore.diagnostics
                diagnostics[keyPath: keyPath] = newValue
                settingsStore.diagnostics = diagnostics
            }
        )
    }

    /// Maps the controller trigger-interpretation enum to the guide's string-backed picker.
    var triggerModeBinding: Binding<String> {
        Binding(
            get: { settingsStore.controller.triggerInterpretationMode.rawValue },
            set: { newValue in
                guard let mode = StratixModels.ControllerSettings.TriggerInterpretationMode(rawValue: newValue) else {
                    return
                }
                var controller = settingsStore.controller
                controller.triggerInterpretationMode = mode
                settingsStore.controller = controller
            }
        )
    }

    /// Keeps the guide's mirror-profile toggle aligned with the current shell profile name.
    var profileMirrorBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.shell.profileName == profileName },
            set: { newValue in
                if newValue {
                    settingsStore.updateProfile(name: profileName, imageURLString: nil)
                } else if settingsStore.shell.profileName == profileName {
                    settingsStore.updateProfile(name: "Player", imageURLString: nil)
                }
            }
        )
    }

    /// Normalizes the current quality preset for guide display and restore logic.
    var normalizedQualityPreset: String {
        streamPresentation.normalizedQualityPreset
    }

    /// Returns the effective stream profile label shown in the guide.
    var effectiveStreamProfileLabel: String {
        streamPresentation.effectiveStreamProfileLabel
    }

    /// Normalizes the current client profile selection for guide display and restore logic.
    var normalizedClientProfileSelection: String {
        streamPresentation.normalizedClientProfileSelection
    }

    /// Returns the effective spoofed OS name shown in the guide.
    var effectiveClientProfileOSName: String {
        streamPresentation.effectiveClientProfileOSName
    }

    /// Returns the current stream-config conflict warning when one is present.
    var streamConfigConflictWarning: String? {
        streamPresentation.streamConfigConflictWarning
    }

    /// Returns the effective bitrate cap after guide-side normalization.
    var effectiveVideoBitrateCapKbps: Int? {
        streamPresentation.effectiveVideoBitrateCapKbps
    }

    /// Describes which setting source currently owns the bitrate cap value.
    var bitrateCapSourceLabel: String {
        streamPresentation.bitrateCapSourceLabel
    }

    /// Returns the accent color used for the profile presence badge.
    var profilePresenceColor: Color {
        let lower = profileStatusText.lowercased()
        if lower.contains("offline") { return Color.white.opacity(0.45) }
        if lower.contains("busy") || lower.contains("away") { return Color.orange }
        return StratixTheme.Colors.focusTint
    }

    /// Returns the fill color used for the profile presence badge.
    var profilePresenceBadgeFill: Color {
        let lower = profileStatusText.lowercased()
        if lower.contains("offline") {
            return Color.white.opacity(0.10)
        }
        if lower.contains("busy") || lower.contains("away") {
            return Color.orange.opacity(0.20)
        }
        return StratixTheme.Colors.focusTint
    }

    /// Indicates whether the presence badge should use dark text for contrast.
    var profilePresenceUsesDarkBadgeText: Bool {
        let lower = profileStatusText.lowercased()
        return !(lower.contains("offline") || lower.contains("busy") || lower.contains("away"))
    }

    /// Produces the short shell destination label shown in the guide sidebar.
    func destinationDetail(for section: AppShellSection) -> String {
        switch section {
        case .gamePass:
            return isLoadingCloudLibrary ? "Syncing cloud library…" : "Home and library"
        case .consoles:
            return "xHome console streaming"
        }
    }

    /// Reconciles guide-backed fields back into the canonical settings representation.
    func normalizeGuideState() {
        if settingsStore.stream.qualityPreset != normalizedQualityPreset {
            var stream = settingsStore.stream
            stream.qualityPreset = normalizedQualityPreset
            settingsStore.stream = stream
        }
        if settingsStore.stream.clientProfileOSName != normalizedClientProfileSelection {
            var stream = settingsStore.stream
            stream.clientProfileOSName = normalizedClientProfileSelection
            settingsStore.stream = stream
        }
    }
}
