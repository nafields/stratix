// AppLifecycleCoordinatorTests.swift
// Exercises app lifecycle coordinator behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@MainActor
@Suite(.serialized)
struct AppLifecycleCoordinatorTests {
    @Test
    func signOutWorkflowOwnershipLivesInLifecycleCoordinator() async {
        let coordinator = makeLifecycleCoordinator()

        coordinator.consoleController.setConsoles([makeRemoteConsole()])
        coordinator.profileController.setCurrentUserPresence(
            XboxCurrentUserPresence(xuid: "123", state: "Online", devices: [], lastSeen: nil)
        )
        coordinator.libraryController.apply([
            .sectionsReplaced([CloudLibrarySection(id: "library", name: "Library", items: [])]),
            .lastHydratedAtSet(Date())
        ])
        coordinator.streamController.apply(.shellRestoredAfterExitSet(true))

        await coordinator.lifecycle.handleSessionDidSignOut()

        #expect(coordinator.consoleController.consoles.isEmpty)
        #expect(coordinator.profileController.currentUserPresence == nil)
        #expect(coordinator.libraryController.sections.isEmpty)
        #expect(coordinator.shellBootstrapController.phase == .idle)
        #expect(coordinator.streamController.shellRestoredAfterStreamExit == false)
    }

    private func makeLifecycleCoordinator() -> (
        lifecycle: AppLifecycleCoordinator,
        libraryController: LibraryController,
        profileController: ProfileController,
        consoleController: ConsoleController,
        streamController: StreamController,
        shellBootstrapController: ShellBootstrapController
    ) {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let sessionController = SessionController()
        let libraryController = LibraryController()
        let profileController = ProfileController()
        let consoleController = ConsoleController()
        let streamController = StreamController()
        let shellBootstrapController = ShellBootstrapController()
        let inputController = InputController()
        let achievementsController = AchievementsController()

        return (
            lifecycle: AppLifecycleCoordinator(
                settingsStore: settingsStore,
                sessionController: sessionController,
                libraryController: libraryController,
                profileController: profileController,
                consoleController: consoleController,
                streamController: streamController,
                shellBootstrapController: shellBootstrapController,
                inputController: inputController,
                achievementsController: achievementsController,
                startupWorkflow: AppStartupWorkflow(),
                foregroundRefreshWorkflow: AppForegroundRefreshWorkflow(),
                backgroundRefreshWorkflow: AppBackgroundRefreshWorkflow(),
                signOutWorkflow: AppSignOutWorkflow()
            ),
            libraryController: libraryController,
            profileController: profileController,
            consoleController: consoleController,
            streamController: streamController,
            shellBootstrapController: shellBootstrapController
        )
    }
}
