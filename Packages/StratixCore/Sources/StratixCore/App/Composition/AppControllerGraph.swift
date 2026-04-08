// AppControllerGraph.swift
// Defines app controller graph for the App / Composition surface.
//

import Foundation

@MainActor
struct AppControllerGraph {
    let settingsStore: SettingsStore
    let sessionController: SessionController
    let libraryController: LibraryController
    let profileController: ProfileController
    let consoleController: ConsoleController
    let streamController: StreamController
    let shellBootstrapController: ShellBootstrapController
    let inputController: InputController
    let achievementsController: AchievementsController
    let previewExportController: PreviewExportController
    let streamPriorityShellController: AppStreamPriorityShellController
    let lifecycleCoordinator: any AppLifecycleHandling
    let shellBootCoordinator: any AppShellBootHandling
    let profileControllerServices: AppProfileControllerServices
    let achievementsControllerServices: AppAchievementsControllerServices
    let libraryControllerServices: AppLibraryControllerServices
    let streamControllerServices: AppStreamControllerServices
}
