// CloudLibrarySettingsBindings.swift
// Defines cloud library settings bindings for the CloudLibrary / Settings surface.
//

import SwiftUI
import StratixCore
import StratixModels

enum CloudLibrarySettingsBindings {
    static func resolvedPane(
        currentPane: CloudLibrarySettingsPane,
        storedRawValue: String,
        isAdvancedMode: Bool,
        restoreStoredSelection: Bool
    ) -> CloudLibrarySettingsPane {
        let visiblePanes = CloudLibrarySettingsPane.visibleCases(isAdvanced: isAdvancedMode)
        let storedPane = CloudLibrarySettingsPane(rawValue: storedRawValue)

        if restoreStoredSelection, let storedPane, visiblePanes.contains(storedPane) {
            return storedPane
        }
        if visiblePanes.contains(currentPane) {
            return currentPane
        }
        return storedPane.flatMap { visiblePanes.contains($0) ? $0 : nil } ?? visiblePanes.first ?? .overview
    }
}

extension CloudLibrarySettingsView {
    var triggerModeBinding: Binding<String> {
        Binding(
            get: { settingsStore.controller.triggerInterpretationMode.rawValue },
            set: { newValue in
                guard let mode = StratixModels.ControllerSettings.TriggerInterpretationMode(rawValue: newValue) else {
                    return
                }
                var next = settingsStore.controller
                next.triggerInterpretationMode = mode
                settingsStore.controller = next
            }
        )
    }

    func shellBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.ShellSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.shell[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.shell
                next[keyPath: keyPath] = newValue
                settingsStore.shell = next
            }
        )
    }

    func streamBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.StreamSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.stream[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.stream
                next[keyPath: keyPath] = newValue
                settingsStore.stream = next
            }
        )
    }

    var diagnosticsFloorBehaviorBinding: Binding<String> {
        Binding(
            get: { settingsStore.diagnostics.upscalingFloorBehavior.label },
            set: { newValue in
                guard let behavior = UpscalingFloorBehavior.allCases.first(where: { $0.label == newValue }) else {
                    return
                }
                var next = settingsStore.diagnostics
                next.upscalingFloorBehavior = behavior
                settingsStore.diagnostics = next
            }
        )
    }

    func controllerBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.ControllerSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.controller[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.controller
                next[keyPath: keyPath] = newValue
                settingsStore.controller = next
            }
        )
    }

    func accessibilityBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.AccessibilitySettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.accessibility[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.accessibility
                next[keyPath: keyPath] = newValue
                settingsStore.accessibility = next
            }
        )
    }

    func diagnosticsBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.DiagnosticsSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.diagnostics[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.diagnostics
                next[keyPath: keyPath] = newValue
                settingsStore.diagnostics = next
            }
        )
    }
}
