// AuthenticatedShellView.swift
// Defines the authenticated shell container and its lightweight runtime markers.
//

import SwiftUI
import StratixCore
import StratixModels

/// Hosts the authenticated shell and publishes lightweight readiness markers used by shell UI tests.
struct AuthenticatedShellView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(StreamController.self) private var streamController
    @Environment(ShellBootstrapController.self) private var shellBootstrapController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders the authenticated shell, root content, and hidden state markers used by tests.
    var body: some View {
        ZStack {
            CloudLibraryView()
            shellReadyMarker
            streamExitCompletionMarker
        }
        .dynamicTypeSize(
            authenticatedShellEffectiveDynamicTypeSize(
                base: dynamicTypeSize,
                largeTextEnabled: settingsStore.accessibility.largeText
            )
        )
        .transaction {
            if settingsStore.accessibility.reduceMotion {
                $0.animation = nil
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    /// Exposes shell readiness to UI tests without affecting visible layout.
    private var shellReadyMarker: some View {
        if shellBootstrapController.phase == .ready {
            Text("shell_ready")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("shell_ready")
                .accessibilityValue("ready")
        }
    }

    @ViewBuilder
    /// Exposes stream-exit completion to UI tests after the shell has been restored.
    private var streamExitCompletionMarker: some View {
        if streamController.shellRestoredAfterStreamExit {
            Text("shell_restored_after_stream_exit")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("stream_exit_complete")
                .accessibilityValue("shell_restored")
        }
    }
}

@MainActor
/// Produces the compact settings summary displayed in profile and shell surfaces.
func authenticatedShellSettingsSummary(settingsStore: SettingsStore) -> String {
    let latency = settingsStore.stream.lowLatencyMode ? "Low latency" : "Balanced latency"
    let stats = settingsStore.stream.showStreamStats ? "Stats on" : "Stats off"
    return "\(settingsStore.stream.qualityPreset) • \(settingsStore.stream.codecPreference) • \(latency) • \(stats)"
}

@MainActor
/// Clamps Dynamic Type up to the large-text floor when that accessibility option is enabled.
func authenticatedShellEffectiveDynamicTypeSize(
    base: DynamicTypeSize,
    largeTextEnabled: Bool
) -> DynamicTypeSize {
    guard largeTextEnabled else { return base }
    return max(base, .xLarge)
}

@MainActor
/// Derives a short initials string for profile fallback rendering.
func authenticatedShellInitials(from name: String) -> String {
    let initials = name
        .split(separator: " ")
        .prefix(2)
        .compactMap { $0.first.map(String.init) }
        .joined()
        .uppercased()
    return initials.isEmpty ? "P" : initials
}

@MainActor
/// Chooses the best display name for the signed-in profile and falls back to the settings store.
func authenticatedShellEffectiveProfileName(
    profileSnapshot: ProfileShellSnapshot,
    settingsStore: SettingsStore
) -> String {
    if let preferred = profileSnapshot.preferredScreenName?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !preferred.isEmpty {
        return preferred
    }
    return settingsStore.shell.profileName
}

@MainActor
/// Chooses the best profile image URL between live profile data and the shell fallback.
func authenticatedShellEffectiveProfileImageURL(
    profileSnapshot: ProfileShellSnapshot,
    settingsStore: SettingsStore
) -> URL? {
    profileSnapshot.profileImageURL ?? settingsStore.profileImageURL
}

@MainActor
/// Normalizes profile presence into the shell-facing Online or Offline status text.
func authenticatedShellProfilePresenceStatus(
    profileSnapshot: ProfileShellSnapshot,
    libraryStatus: LibraryShellStatusSnapshot,
    settingsStore: SettingsStore
) -> String {
    let override = settingsStore.shell.profilePresenceOverride
    if override == "Online" || override == "Offline" {
        return override
    }
    if let liveState = profileSnapshot.presenceState,
       !liveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return liveState.capitalized
    }
    if libraryStatus.needsReauth {
        return "Offline"
    }
    if libraryStatus.lastErrorText != nil,
       libraryStatus.hasSections == false,
       libraryStatus.isLoading == false {
        return "Offline"
    }
    return "Online"
}

@MainActor
/// Produces the longer profile presence detail string used in the authenticated shell.
func authenticatedShellProfilePresenceDetailText(profileSnapshot: ProfileShellSnapshot) -> String {
    if profileSnapshot.isLoadingCurrentUserPresence, profileSnapshot.presenceState == nil {
        return "Syncing Xbox presence…"
    }

    if let activeTitle = profileSnapshot.activeTitleName, profileSnapshot.isOnline {
        return "Playing \(activeTitle)"
    }
    if let lastSeen = profileSnapshot.lastSeenTitleName, !lastSeen.isEmpty {
        return "Last seen in \(lastSeen)"
    }
    if let device = profileSnapshot.onlineDeviceType, !device.isEmpty, profileSnapshot.isOnline {
        return "Online on \(device)"
    }

    if let error = profileSnapshot.lastCurrentUserPresenceError, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if error.localizedCaseInsensitiveContains("decode") || error.localizedCaseInsensitiveContains("format") {
            return "Xbox status sync unavailable"
        }
        return "Xbox presence unavailable"
    }

    return "Xbox presence synced"
}

#if DEBUG
private struct AuthenticatedShellPreviewHost: View {
    @State private var coordinator = AppCoordinator()

    var body: some View {
        AuthenticatedShellView()
            .environment(coordinator.sessionController)
            .environment(coordinator.libraryController)
            .environment(coordinator.profileController)
            .environment(coordinator.consoleController)
            .environment(coordinator.streamController)
            .environment(coordinator.shellBootstrapController)
            .environment(coordinator.achievementsController)
            .environment(coordinator.inputController)
            .environment(coordinator.settingsStore)
            .environment(coordinator.previewExportController)
    }
}

#Preview("AuthenticatedShellView", traits: .fixedLayout(width: 1920, height: 1080)) {
    AuthenticatedShellPreviewHost()
}
#endif
