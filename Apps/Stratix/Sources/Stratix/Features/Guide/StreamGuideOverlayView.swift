// StreamGuideOverlayView.swift
// Defines the stream guide overlay view used in the Features / Guide surface.
//

import SwiftUI
import StratixCore
import StratixModels

/// Renders the in-stream guide overlay and keeps guide state synchronized with settings changes.
struct StreamGuideOverlayView: View {
    @Binding var isPresented: Bool
    @Binding var selectedSection: AppShellSection
    var requestedPaneRawValue: String? = nil

    let profileName: String
    let profileInitials: String
    var profileImageURL: URL? = nil
    var profileStatusText: String = "Online"
    var profileStatusDetail: String? = nil
    let cloudLibraryCount: Int
    let consoleCount: Int
    let isLoadingCloudLibrary: Bool
    var regionOverrideDiagnostics: String? = nil
    let onRefreshCloudLibrary: () -> Void
    let onRefreshConsoles: () -> Void
    let onSignOut: () -> Void
    let onExportPreviewDump: () async -> String

    @Environment(SettingsStore.self) var settingsStore
    @SceneStorage("guide.last_pane") var lastPaneRawValue = GuideOverlayPane.overview.rawValue
    @SceneStorage("guide.settings_mode") var settingsModeRawValue = GuideSettingsMode.basic.rawValue

    @State var selectedPane: GuideOverlayPane = .overview
    @State var previewDumpStatusMessage: String? = nil
    @State var isExportingPreviewDump = false
    @State var lastSettingChangeMessage: String? = nil
    @State var pendingFocusTask: Task<Void, Never>?
    @State var hasRecordedInitialFocusSettlement = false
    @FocusState var sidebarFocus: GuideSidebarFocusTarget?

    /// Resolves the active guide settings mode from persisted scene storage.
    var settingsMode: GuideSettingsMode {
        get { GuideSettingsMode(rawValue: settingsModeRawValue) ?? .basic }
        nonmutating set { settingsModeRawValue = newValue.rawValue }
    }

    /// Renders the full-screen guide overlay and keeps the scene-storage state in sync.
    var body: some View {
        ZStack(alignment: .leading) {
            Button(action: close) {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close guide")

            HStack(spacing: 0) {
                panel
                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: handleAppear)
        .onChange(of: sidebarFocus) { _, value in
            recordFocusChange(target: value)
        }
        .onExitCommand(perform: handleGuideBack)
        .onPlayPauseCommand(perform: close)
        .accessibilityIdentifier("guide_overlay_root")
        .onChange(of: settingsStore.stream.qualityPreset) { _, newValue in
            noteSettingChanged("Quality Preset", value: newValue)
        }
        .onChange(of: settingsStore.stream.codecPreference) { _, newValue in
            noteSettingChanged("Codec Preference", value: newValue)
        }
        .onChange(of: settingsStore.stream.clientProfileOSName) { _, newValue in
            noteSettingChanged("Client Profile", value: newValue)
        }
        .onChange(of: settingsStore.stream.lowLatencyMode) { _, newValue in
            noteSettingChanged("Low Latency Mode", value: newValue ? "On" : "Off")
        }
        .onChange(of: settingsStore.accessibility.reduceMotion) { _, newValue in
            noteSettingChanged("Reduce Motion", value: newValue ? "On" : "Off")
        }
        .onChange(of: settingsStore.accessibility.largeText) { _, newValue in
            noteSettingChanged("Large Text", value: newValue ? "On" : "Off")
        }
        .onChange(of: settingsStore.shell.guideTranslucency) { _, newValue in
            noteSettingChanged("Guide Panel Opacity", value: String(format: "%.0f%%", newValue * 100))
        }
    }

}

#if DEBUG
private struct StreamGuideOverlayPreviewHost: View {
    @State private var shown = true
    @State private var section: AppShellSection = .gamePass

    var body: some View {
        ZStack {
            CloudLibraryAmbientBackground(imageURL: CloudLibraryPreviewData.home.heroBackgroundURL)
            StreamGuideOverlayView(
                isPresented: $shown,
                selectedSection: $section,
                profileName: "Stratix Preview",
                profileInitials: "S",
                cloudLibraryCount: 248,
                consoleCount: 2,
                isLoadingCloudLibrary: false,
                onRefreshCloudLibrary: {},
                onRefreshConsoles: {},
                onSignOut: {},
                onExportPreviewDump: { "Preview dump not available in previews." }
            )
        }
    }
}

#Preview("StreamGuideOverlayView", traits: .fixedLayout(width: 1920, height: 1080)) {
    StreamGuideOverlayPreviewHost()
        .environment(SettingsStore())
}
#endif
