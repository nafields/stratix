// CloudLibrarySettingsStreamPane.swift
// Defines cloud library settings stream pane for the CloudLibrary / Settings surface.
//

import SwiftUI

extension CloudLibrarySettingsView {
    var streamPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            CloudLibraryPageSectionCard(title: "Stream", subtitle: "Quality, codec, and session responsiveness") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibraryPickerRow(title: "Quality Preset", selection: streamBinding(\.qualityPreset), options: ["Low Data", "Balanced", "High Quality", "Competitive"])
                    CloudLibraryPickerRow(title: "Codec Preference", selection: streamBinding(\.codecPreference), options: ["Auto", "H.264", "VP9"])
                    CloudLibraryPickerRow(title: "Client Profile", selection: streamBinding(\.clientProfileOSName), options: ["Auto", "Android", "Windows", "Tizen"])
                    CloudLibraryPickerRow(title: "Resolution", selection: streamBinding(\.preferredResolution), options: ["720p", "1080p", "1440p"])
                    CloudLibraryPickerRow(title: "Frame Rate", selection: streamBinding(\.preferredFPS), options: ["30", "60"])
                    CloudLibraryPickerRow(title: "Stats HUD Position", selection: streamBinding(\.statsHUDPosition), options: ["topRight", "topLeft", "bottomRight", "bottomLeft"])
                    CloudLibrarySliderRow(title: "Bitrate Cap", value: streamBinding(\.bitrateCapMbps), range: 0...100, formatter: bitrateText, step: 4)
                    CloudLibraryToggleRow(title: "HDR Preferred", subtitle: "Enable HDR metadata when available", isOn: streamBinding(\.hdrEnabled))
                    CloudLibraryToggleRow(title: "Low Latency Mode", subtitle: "Prioritize responsiveness over smoothing", isOn: streamBinding(\.lowLatencyMode))
                    CloudLibraryToggleRow(title: "Upscaling", subtitle: "Start on sample buffer, then promote to the best validated renderer", isOn: streamBinding(\.upscalingEnabled))
                    CloudLibraryToggleRow(title: "Show Stream Stats", subtitle: "Display FPS, bitrate, and RTT in-session", isOn: streamBinding(\.showStreamStats))
                    CloudLibraryToggleRow(title: "Auto Reconnect", subtitle: "Try reconnecting after transport drops", isOn: streamBinding(\.autoReconnect))
                    CloudLibraryToggleRow(title: "Packet Loss Protection", subtitle: "Trade a little sharpness for stability on unstable links", isOn: streamBinding(\.packetLossProtection))
                    CloudLibraryToggleRow(title: "Prefer IPv6", subtitle: "Use IPv6 when the network supports it", isOn: streamBinding(\.preferIPv6))
                }
            }
        }
    }

    private func bitrateText(_ value: Double) -> String {
        value <= 0 ? "Auto" : String(format: "%.0f Mbps", value)
    }
}
