// StratixApp.swift
// Defines the app entry point and injects the shared controller graph into SwiftUI.
//

import SwiftUI
import StratixCore

@main
/// Boots the Stratix app and wires the shared `AppCoordinator` into the root scene.
struct StratixApp: App {
    @UIApplicationDelegateAdaptor(StratixAppDelegate.self) private var appDelegate

    @State private var coordinator = AppCoordinator()

    /// Creates the main window group and starts coordinator-driven boot only for normal app runs.
    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
                .environment(coordinator.sessionController)
                .environment(coordinator.libraryController)
                .environment(coordinator.profileController)
                .environment(coordinator.consoleController)
                .environment(coordinator.streamController)
                .environment(coordinator.shellBootstrapController)
                .environment(coordinator.achievementsController)
                .environment(coordinator.inputController)
                .environment(coordinator.previewExportController)
                .environment(coordinator.settingsStore)
                .task {
                    appDelegate.coordinator = coordinator
                    guard shouldRunCoordinatorOnAppear else { return }
                    await coordinator.onAppear()
                }
        }
    }

    /// Skips normal coordinator boot when a UI harness owns startup sequencing.
    private var shouldRunCoordinatorOnAppear: Bool {
        !StratixLaunchMode.isShellUITestModeEnabled
            && !StratixLaunchMode.isGamePassHomeUITestModeEnabled
    }
}
