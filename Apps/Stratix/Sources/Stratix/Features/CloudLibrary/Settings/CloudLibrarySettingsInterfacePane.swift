// CloudLibrarySettingsInterfacePane.swift
// Defines cloud library settings interface pane for the CloudLibrary / Settings surface.
//

import SwiftUI

extension CloudLibrarySettingsView {
    var interfacePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            CloudLibraryPageSectionCard(title: "Interface", subtitle: "TV comfort and shell accessibility") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibraryToggleRow(title: "Reduce Motion", subtitle: "Minimize motion-heavy transitions", isOn: accessibilityBinding(\.reduceMotion))
                    CloudLibraryToggleRow(title: "Large Text", subtitle: "Increase shell text sizing", isOn: accessibilityBinding(\.largeText))
                    CloudLibraryToggleRow(title: "Closed Captions", subtitle: "Persist the caption preference", isOn: accessibilityBinding(\.closedCaptions))
                    CloudLibraryToggleRow(title: "High Visibility Focus", subtitle: "Use a thicker focus ring and stronger glow", isOn: accessibilityBinding(\.highVisibilityFocus))
                    CloudLibrarySliderRow(title: "Focus Glow Intensity", value: shellBinding(\.focusGlowIntensity), range: 0.25...1.0, formatter: percentText)
                    CloudLibrarySliderRow(title: "Guide Transparency", value: shellBinding(\.guideTranslucency), range: 0.30...1.0, formatter: percentText)
                    CloudLibraryPickerRow(title: "Presence Override", selection: shellBinding(\.profilePresenceOverride), options: ["Auto", "Online", "Offline"])
                    CloudLibraryToggleRow(title: "Quick Resume Badges", subtitle: "Show continue markers on home and library", isOn: shellBinding(\.quickResumeTile))
                    CloudLibraryToggleRow(title: "Remember Last Section", subtitle: "Restore the last primary shell destination", isOn: shellBinding(\.rememberLastSection))
                }
            }
        }
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
