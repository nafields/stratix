// CloudLibrarySettingsDiagnosticsPane.swift
// Defines cloud library settings diagnostics pane for the CloudLibrary / Settings surface.
//

import SwiftUI
import StratixCore
import StratixModels

extension CloudLibrarySettingsView {
    var diagnosticsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            CloudLibraryPageSectionCard(title: "Region Override", subtitle: "Preferred xCloud region selection") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibraryPickerRow(title: "Region Override", selection: streamBinding(\.regionOverride), options: ["Auto", "US East", "US West", "Europe", "UK"])
                    if let regionOverrideDiagnostics, !regionOverrideDiagnostics.isEmpty {
                        CloudLibraryStatLine(icon: "globe", text: regionOverrideDiagnostics)
                    }
                    CloudLibraryToggleRow(title: "Log Network Events", subtitle: "Include per-request network breadcrumbs in diagnostics", isOn: diagnosticsBinding(\.logNetworkEvents))
                    CloudLibraryToggleRow(title: "Block Tracking", subtitle: "Disable analytics tracking for this device", isOn: diagnosticsBinding(\.blockTracking))
                    CloudLibraryToggleRow(title: "Verbose Logs", subtitle: "Enable deeper runtime logging", isOn: diagnosticsBinding(\.verboseLogs))
                    CloudLibraryPickerRow(
                        title: "Upscaling Floor",
                        selection: diagnosticsFloorBehaviorBinding,
                        options: UpscalingFloorBehavior.allCases.map(\.label)
                    )
                    CloudLibraryToggleRow(title: "Frame Probe", subtitle: "Collect frame timing probes", isOn: diagnosticsBinding(\.frameProbe))
                    CloudLibraryToggleRow(title: "Audio Resync Watchdog", subtitle: "Monitor remote audio drift", isOn: diagnosticsBinding(\.audioResyncWatchdogEnabled))
                    CloudLibraryToggleRow(title: "Startup Haptics Probe", subtitle: "Validate controller haptics on launch", isOn: diagnosticsBinding(\.startupHapticsProbeEnabled))
                }
            }

            CloudLibraryPageSectionCard(title: "Preview Data", subtitle: "Export the live shell model for design and regression work") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibrarySettingsActionButton(
                        title: previewExportTitle,
                        systemImage: "square.and.arrow.up"
                    ) {
                        startPreviewExport()
                    }

                    if let exportFeedback, !exportFeedback.isEmpty {
                        CloudLibraryStatLine(icon: "doc.fill", text: exportFeedback)
                    }
                }
            }
        }
    }

    private var previewExportTitle: String {
        isExportingPreviewDump ? "Exporting Preview Dump" : "Export Preview Dump"
    }
}
