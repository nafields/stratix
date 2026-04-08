// CloudLibrarySettingsOverviewPane.swift
// Defines cloud library settings overview pane for the CloudLibrary / Settings surface.
//

import SwiftUI

extension CloudLibrarySettingsView {
    var overviewPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            CloudLibraryPageSectionCard(title: "Quick Actions", subtitle: "Refresh the live shell state and export preview data") {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12, alignment: .leading),
                        GridItem(.flexible(), spacing: 12, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    CloudLibrarySettingsActionButton(title: "Refresh Game Pass", systemImage: "cloud.fill", action: onRefreshCloudLibrary)
                    CloudLibrarySettingsActionButton(title: "Refresh Consoles", systemImage: "tv.badge.wifi", action: onRefreshConsoles)
                    CloudLibrarySettingsActionButton(title: previewExportTitle, systemImage: "square.and.arrow.up") {
                        startPreviewExport()
                    }
                    CloudLibrarySettingsActionButton(
                        title: "Sign Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        destructive: true,
                        action: onSignOut
                    )
                }
            }

            CloudLibraryPageSectionCard(title: "Shell Status", subtitle: "Live state from the current session") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibraryStatLine(icon: "person.crop.circle.fill", text: "Profile: \(profileName)")
                    CloudLibraryStatLine(icon: "bolt.horizontal.fill", text: profileStatusDetail.isEmpty ? profileStatusText : profileStatusDetail)
                    CloudLibraryStatLine(icon: "cloud.fill", text: cloudLibraryStatusText)
                    CloudLibraryStatLine(icon: "tv.fill", text: "\(consoleCount) consoles detected")
                    CloudLibraryStatLine(icon: "dial.high.fill", text: authenticatedShellSettingsSummary(settingsStore: settingsStore))
                }
            }

            if let exportFeedback, !exportFeedback.isEmpty {
                CloudLibraryPageSectionCard(title: "Preview Export", subtitle: "Latest export result") {
                    CloudLibraryStatLine(icon: "doc.fill", text: exportFeedback)
                }
            }
        }
    }

    private var previewExportTitle: String {
        isExportingPreviewDump ? "Exporting Preview Dump" : "Export Preview Dump"
    }

    private var cloudLibraryStatusText: String {
        isLoadingCloudLibrary ? "Cloud library is syncing now" : "\(cloudLibraryCount) titles available"
    }
}
