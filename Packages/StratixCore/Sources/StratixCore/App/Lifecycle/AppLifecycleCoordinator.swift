// AppLifecycleCoordinator.swift
// Defines the app lifecycle coordinator for the App / Lifecycle surface.
//

import DiagnosticsKit
import Foundation

@MainActor
protocol AppLifecycleHandling: AnyObject {
    func onAppear() async
    func handleAppDidBecomeActive() async
    func performBackgroundAppRefresh() async -> Bool
    func handleSessionDidSignOut() async
}

@MainActor
final class AppLifecycleCoordinator: AppLifecycleHandling {
    private let settingsStore: SettingsStore
    private let sessionController: SessionController
    private let libraryController: LibraryController
    private let profileController: ProfileController
    private let consoleController: ConsoleController
    private let streamController: StreamController
    private let shellBootstrapController: ShellBootstrapController
    private let inputController: InputController
    private let achievementsController: AchievementsController
    private let startupWorkflow: AppStartupWorkflow
    private let foregroundRefreshWorkflow: AppForegroundRefreshWorkflow
    private let backgroundRefreshWorkflow: AppBackgroundRefreshWorkflow
    private let signOutWorkflow: AppSignOutWorkflow
    private let logger = GLogger(category: .auth)

    init(
        settingsStore: SettingsStore,
        sessionController: SessionController,
        libraryController: LibraryController,
        profileController: ProfileController,
        consoleController: ConsoleController,
        streamController: StreamController,
        shellBootstrapController: ShellBootstrapController,
        inputController: InputController,
        achievementsController: AchievementsController,
        startupWorkflow: AppStartupWorkflow,
        foregroundRefreshWorkflow: AppForegroundRefreshWorkflow,
        backgroundRefreshWorkflow: AppBackgroundRefreshWorkflow,
        signOutWorkflow: AppSignOutWorkflow
    ) {
        self.settingsStore = settingsStore
        self.sessionController = sessionController
        self.libraryController = libraryController
        self.profileController = profileController
        self.consoleController = consoleController
        self.streamController = streamController
        self.shellBootstrapController = shellBootstrapController
        self.inputController = inputController
        self.achievementsController = achievementsController
        self.startupWorkflow = startupWorkflow
        self.foregroundRefreshWorkflow = foregroundRefreshWorkflow
        self.backgroundRefreshWorkflow = backgroundRefreshWorkflow
        self.signOutWorkflow = signOutWorkflow
    }

    func onAppear() async {
        await startupWorkflow.handleOnAppear(
            environment: AppStartupAppearEnvironment(
                updateControllerSettings: { [settingsStore, inputController] in
                    inputController.updateControllerSettings(from: settingsStore)
                },
                runAppLaunchHapticsProbe: { [settingsStore, inputController] in
                    inputController.runAppLaunchHapticsProbeIfNeeded(settingsStore: settingsStore)
                },
                sessionOnAppear: { [sessionController] in
                    await sessionController.onAppear()
                }
            )
        )
    }

    func handleAppDidBecomeActive() async {
        await foregroundRefreshWorkflow.run(
            environment: AppForegroundRefreshEnvironment(
                isAuthenticated: isAuthenticated,
                isStreamPriorityModeActive: streamController.isStreamPriorityModeActive,
                hasStreamingSession: streamController.state.streamingSession != nil,
                shellBootstrapPhase: shellBootstrapController.phase,
                refreshStreamTokens: { [sessionController] in
                    await sessionController.refreshStreamTokensInBackground(
                        reason: "foreground_resume",
                        minimumInterval: 25
                    )
                },
                loadCloudLibrary: { [libraryController] in
                    await libraryController.refresh(forceRefresh: false, reason: .foregroundResume)
                },
                hasLibrarySections: { [libraryController] in
                    !libraryController.state.sections.isEmpty
                },
                prefetchArtwork: { [libraryController] in
                    await libraryController.prefetchLibraryArtwork(libraryController.state.sections)
                },
                logInfo: { [logger] in logger.info($0) }
            )
        )
    }

    func performBackgroundAppRefresh() async -> Bool {
        await backgroundRefreshWorkflow.run(
            environment: AppBackgroundRefreshEnvironment(
                isAuthenticated: isAuthenticated,
                isStreamPriorityModeActive: streamController.isStreamPriorityModeActive,
                baselineHydratedAt: libraryController.state.lastHydratedAt,
                baselineItemCount: libraryController.state.sections.reduce(0) { $0 + $1.items.count },
                refreshStreamTokens: { [sessionController] in
                    await sessionController.refreshStreamTokensInBackground(
                        reason: "background_app_refresh",
                        minimumInterval: 0
                    )
                },
                loadCloudLibrary: { [libraryController] in
                    await libraryController.refresh(forceRefresh: false, reason: .backgroundRefresh)
                },
                refreshedHydratedAt: { [libraryController] in
                    libraryController.state.lastHydratedAt
                },
                refreshedItemCount: { [libraryController] in
                    libraryController.state.sections.reduce(0) { $0 + $1.items.count }
                },
                logInfo: { [logger] in logger.info($0) }
            )
        )
    }

    func handleSessionDidSignOut() async {
        await signOutWorkflow.run(
            environment: AppSignOutEnvironment(
                resetConsole: { [consoleController] in
                    consoleController.resetForSignOut()
                },
                resetLibrary: { [libraryController] in
                    await libraryController.resetForSignOut()
                },
                clearLibraryCaches: { [libraryController] in
                    libraryController.clearPersistedLibraryCaches()
                },
                resetShellBootstrap: { [shellBootstrapController] in
                    await shellBootstrapController.resetForSignOut()
                },
                resetAchievements: { [achievementsController] in
                    await achievementsController.resetForSignOut()
                },
                clearAchievementCaches: { [achievementsController] in
                    achievementsController.clearPersistedAchievementCache()
                },
                clearProfileCaches: { [profileController] in
                    profileController.clearPersistedSocialCache()
                },
                resetStream: { [streamController] in
                    await streamController.resetForSignOut()
                },
                resetInput: { [inputController] in
                    inputController.resetForSignOut()
                },
                resetProfile: { [profileController] in
                    profileController.resetForSignOut()
                }
            )
        )
    }

    private var isAuthenticated: Bool {
        if case .authenticated = sessionController.authState { return true }
        return false
    }
}
