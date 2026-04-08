// AppShellBootCoordinator.swift
// Defines the app shell boot coordinator for the App / Shell surface.
//

import DiagnosticsKit
import Foundation

@MainActor
protocol AppShellBootHandling: AnyObject {
    func beginShellBootHydrationIfNeeded(restoreCachesBeforeBoot: Bool) async
}

@MainActor
final class AppShellBootCoordinator: AppShellBootHandling {
    private let sessionController: SessionController
    private let libraryController: LibraryController
    private let profileController: ProfileController
    private let shellBootstrapController: ShellBootstrapController
    private let achievementsController: AchievementsController
    private let cacheRestoreWorkflow: AppCacheRestoreWorkflow
    private let startupWorkflow: AppStartupWorkflow
    private let streamPriorityShellController: AppStreamPriorityShellController
    private let logger = GLogger(category: .auth)

    init(
        sessionController: SessionController,
        libraryController: LibraryController,
        profileController: ProfileController,
        shellBootstrapController: ShellBootstrapController,
        achievementsController: AchievementsController,
        cacheRestoreWorkflow: AppCacheRestoreWorkflow,
        startupWorkflow: AppStartupWorkflow,
        streamPriorityShellController: AppStreamPriorityShellController
    ) {
        self.sessionController = sessionController
        self.libraryController = libraryController
        self.profileController = profileController
        self.shellBootstrapController = shellBootstrapController
        self.achievementsController = achievementsController
        self.cacheRestoreWorkflow = cacheRestoreWorkflow
        self.startupWorkflow = startupWorkflow
        self.streamPriorityShellController = streamPriorityShellController
    }

    func beginShellBootHydrationIfNeeded(restoreCachesBeforeBoot: Bool) async {
        await startupWorkflow.beginShellBootHydrationIfNeeded(
            environment: AppStartupHydrationEnvironment(
                isShellSuspendedForStreaming: streamPriorityShellController.isShellSuspendedForStreaming,
                isAuthenticated: isAuthenticated,
                shouldRestoreCachesBeforeBoot: restoreCachesBeforeBoot,
                restoreCachesFromDisk: { [cacheRestoreWorkflow, libraryController, achievementsController, profileController] in
                    await cacheRestoreWorkflow.run(
                        environment: AppCacheRestoreEnvironment(
                            isAuthenticated: true,
                            restoreLibraryCaches: { isAuthenticated in
                                await libraryController.restoreDiskCachesIfNeeded(isAuthenticated: isAuthenticated)
                            },
                            restoreAchievementCaches: { isAuthenticated in
                                await achievementsController.restoreDiskCachesIfNeeded(isAuthenticated: isAuthenticated)
                            },
                            restoreProfileCaches: {
                                await profileController.restoreSocialCacheFromDisk()
                            }
                        )
                    )
                },
                makeShellBootHydrationPlan: { [libraryController] in
                    libraryController.makeShellBootHydrationPlan(isAuthenticated: true)
                },
                beginShellBootHydration: { [shellBootstrapController] plan, refreshAction, prefetchAction in
                    await shellBootstrapController.beginHydrationIfNeeded(
                        plan: plan,
                        refreshAction: refreshAction,
                        prefetchAction: prefetchAction
                    )
                },
                refreshCloudLibrary: { [libraryController] deferInitialRoutePublication in
                    await libraryController.refresh(
                        forceRefresh: true,
                        reason: .startupAuto,
                        deferInitialRoutePublication: deferInitialRoutePublication
                    )
                },
                prefetchArtwork: { [libraryController] in
                    let sections = libraryController.state.sections
                    guard !sections.isEmpty else { return }
                    await libraryController.prefetchLibraryArtwork(sections)
                },
                logInfo: { [logger] in logger.info($0) }
            )
        )
    }

    private var isAuthenticated: Bool {
        if case .authenticated = sessionController.authState { return true }
        return false
    }
}
