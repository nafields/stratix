// CloudLibrarySettingsVideoAudioPane.swift
// Defines cloud library settings video audio pane for the CloudLibrary / Settings surface.
//

import SwiftUI

extension CloudLibrarySettingsView {
    var videoAudioPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            CloudLibraryPageSectionCard(title: "Video", subtitle: "Display and output controls") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibraryPickerRow(title: "Color Range", selection: streamBinding(\.colorRange), options: ["Auto", "Limited", "Full"])
                    CloudLibrarySliderRow(title: "Safe Area", value: streamBinding(\.safeAreaPercent), range: 80...100, formatter: wholePercentText)
                }
            }

            CloudLibraryPageSectionCard(title: "Audio", subtitle: "Output and chat behavior") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibrarySliderRow(title: "Audio Boost", value: streamBinding(\.audioBoost), range: 0...12.0, formatter: audioBoostText, step: 1)
                    CloudLibraryToggleRow(title: "Stereo Audio", subtitle: "Prefer stereo output on the client", isOn: streamBinding(\.stereoAudio))
                    CloudLibraryToggleRow(title: "Chat Channel", subtitle: "Persist the chat-channel preference", isOn: streamBinding(\.chatChannelEnabled))
                }
            }
        }
    }

    private func wholePercentText(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private func audioBoostText(_ value: Double) -> String {
        String(format: "+%.0f dB", value)
    }
}
