// CloudLibrarySettingsControllerPane.swift
// Defines cloud library settings controller pane for the CloudLibrary / Settings surface.
//

import SwiftUI

extension CloudLibrarySettingsView {
    var controllerPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            CloudLibraryPageSectionCard(title: "Controller", subtitle: "Input feel, mapping, and responsiveness") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibraryToggleRow(title: "Vibration / Rumble", subtitle: "Enable controller haptics", isOn: controllerBinding(\.vibrationEnabled))
                    CloudLibraryToggleRow(title: "Swap A / B Buttons", subtitle: "Alternative confirm and cancel layout", isOn: controllerBinding(\.swapABButtons))
                    CloudLibraryToggleRow(title: "Invert Y Axis", subtitle: "Invert vertical look input", isOn: controllerBinding(\.invertYAxis))
                    CloudLibrarySliderRow(title: "Stick Deadzone", value: controllerBinding(\.deadzone), range: 0...0.35, formatter: decimalText)
                    CloudLibrarySliderRow(title: "Trigger Sensitivity", value: controllerBinding(\.triggerSensitivity), range: 0...1.0, formatter: decimalText)
                    CloudLibraryPickerRow(title: "Trigger Interpretation", selection: triggerModeBinding, options: ["Auto", "Compatibility", "Analog"])
                    CloudLibrarySliderRow(title: "Sensitivity Boost", value: controllerBinding(\.sensitivityBoost), range: 0...1.0, formatter: decimalText)
                    CloudLibrarySliderRow(title: "Vibration Intensity", value: controllerBinding(\.vibrationIntensity), range: 0...1.0, formatter: decimalText)
                }
            }
        }
    }

    private func decimalText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
