// AppControllerBuilder.swift
// Defines app controller builder for the App / Composition surface.
//

import Foundation
import XCloudAPI

@MainActor
enum AppControllerBuilder {
    static func make(settingsStore: SettingsStore) -> AppControllerGraph {
        let sessionController = SessionController()
        let libraryController = LibraryController()
        let profileController = ProfileController()
        let consoleController = ConsoleController()
        let streamController = StreamController()
        let shellBootstrapController = ShellBootstrapController()
        let inputController = InputController()
        let achievementsController = AchievementsController()
        let previewExportController = PreviewExportController()
        let previewExportSource = AppPreviewExportSource(
            settingsStore: settingsStore,
            sessionController: sessionController,
            libraryController: libraryController,
            profileController: profileController,
            consoleController: consoleController,
            streamController: streamController
        )
        let startupWorkflow = AppStartupWorkflow()
        let foregroundRefreshWorkflow = AppForegroundRefreshWorkflow()
        let backgroundRefreshWorkflow = AppBackgroundRefreshWorkflow()
        let cacheRestoreWorkflow = AppCacheRestoreWorkflow()
        let signOutWorkflow = AppSignOutWorkflow()
        let networkSessionProvider = AppNetworkSessionProvider(settingsStore: settingsStore)
        let videoCapabilitiesBootstrapProbe = VideoCapabilitiesBootstrapProbe()
        let streamPriorityShellController = makeStreamPriorityShellController(
            sessionController: sessionController,
            libraryController: libraryController,
            profileController: profileController,
            consoleController: consoleController,
            streamController: streamController,
            shellBootstrapController: shellBootstrapController,
            achievementsController: achievementsController
        )
        let lifecycleCoordinator = AppLifecycleCoordinator(
            settingsStore: settingsStore,
            sessionController: sessionController,
            libraryController: libraryController,
            profileController: profileController,
            consoleController: consoleController,
            streamController: streamController,
            shellBootstrapController: shellBootstrapController,
            inputController: inputController,
            achievementsController: achievementsController,
            startupWorkflow: startupWorkflow,
            foregroundRefreshWorkflow: foregroundRefreshWorkflow,
            backgroundRefreshWorkflow: backgroundRefreshWorkflow,
            signOutWorkflow: signOutWorkflow
        )
        let shellBootCoordinator = AppShellBootCoordinator(
            sessionController: sessionController,
            libraryController: libraryController,
            profileController: profileController,
            shellBootstrapController: shellBootstrapController,
            achievementsController: achievementsController,
            cacheRestoreWorkflow: cacheRestoreWorkflow,
            startupWorkflow: startupWorkflow,
            streamPriorityShellController: streamPriorityShellController
        )

        let profileControllerServices = AppProfileControllerServices(
            sessionController: sessionController,
            settingsStore: settingsStore,
            networkSessionProvider: networkSessionProvider
        )
        let achievementsControllerServices = AppAchievementsControllerServices(
            sessionController: sessionController,
            profileController: profileController,
            libraryController: libraryController,
            networkSessionProvider: networkSessionProvider
        )
        let libraryControllerServices = AppLibraryControllerServices(
            sessionController: sessionController,
            profileController: profileController,
            achievementsController: achievementsController
        )
        let streamControllerServices = AppStreamControllerServices(
            settingsStore: settingsStore,
            sessionController: sessionController,
            libraryController: libraryController,
            consoleController: consoleController,
            achievementsController: achievementsController,
            inputController: inputController,
            networkSessionProvider: networkSessionProvider,
            videoCapabilitiesBootstrapProbe: videoCapabilitiesBootstrapProbe,
            streamPriorityShellController: streamPriorityShellController
        )
        previewExportController.attach(previewExportSource)

        return AppControllerGraph(
            settingsStore: settingsStore,
            sessionController: sessionController,
            libraryController: libraryController,
            profileController: profileController,
            consoleController: consoleController,
            streamController: streamController,
            shellBootstrapController: shellBootstrapController,
            inputController: inputController,
            achievementsController: achievementsController,
            previewExportController: previewExportController,
            streamPriorityShellController: streamPriorityShellController,
            lifecycleCoordinator: lifecycleCoordinator,
            shellBootCoordinator: shellBootCoordinator,
            profileControllerServices: profileControllerServices,
            achievementsControllerServices: achievementsControllerServices,
            libraryControllerServices: libraryControllerServices,
            streamControllerServices: streamControllerServices
        )
    }

    private static func makeStreamPriorityShellController(
        sessionController: SessionController,
        libraryController: LibraryController,
        profileController: ProfileController,
        consoleController: ConsoleController,
        streamController: StreamController,
        shellBootstrapController: ShellBootstrapController,
        achievementsController: AchievementsController
    ) -> AppStreamPriorityShellController {
        AppStreamPriorityShellController(
            dependencies: AppStreamPriorityShellDependencies(
                suspendShellBootstrap: {
                    await shellBootstrapController.suspendForStreaming()
                },
                resumeShellBootstrap: {
                    shellBootstrapController.resumeAfterStreaming()
                },
                suspendLibrary: {
                    await libraryController.suspendForStreaming()
                },
                resumeLibrary: {
                    libraryController.resumeAfterStreaming()
                },
                suspendProfile: {
                    await profileController.suspendForStreaming()
                },
                resumeProfile: {
                    profileController.resumeAfterStreaming()
                },
                suspendConsole: {
                    await consoleController.suspendForStreaming()
                },
                resumeConsole: {
                    consoleController.resumeAfterStreaming()
                },
                suspendAchievements: {
                    await achievementsController.suspendForStreaming()
                },
                resumeAchievements: {
                    achievementsController.resumeAfterStreaming()
                },
                authState: {
                    sessionController.authState
                },
                hasStreamingSession: {
                    streamController.state.streamingSession != nil
                },
                makePostStreamHydrationPlan: {
                    libraryController.makePostStreamHydrationPlan()
                },
                runPostStreamDeltaRefresh: { plan in
                    await libraryController.refreshPostStreamResumeDelta(plan: plan)
                },
                runPostStreamFullRefresh: {
                    await libraryController.refresh(forceRefresh: true, reason: .postStreamResume)
                },
                prefetchArtwork: {
                    let sections = libraryController.state.sections
                    guard !sections.isEmpty else { return }
                    await libraryController.prefetchLibraryArtwork(sections)
                },
                setShellStatusText: { text in
                    shellBootstrapController.setStatusText(text)
                },
                setShellIsLoading: { isLoading in
                    shellBootstrapController.setIsLoading(isLoading)
                },
                markShellRestored: {
                    streamController.apply(.shellRestoredAfterExitSet(true))
                }
            )
        )
    }
}
