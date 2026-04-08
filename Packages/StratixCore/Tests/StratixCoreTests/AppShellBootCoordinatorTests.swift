// AppShellBootCoordinatorTests.swift
// Exercises app shell boot coordinator behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@MainActor
@Suite(.serialized)
struct AppShellBootCoordinatorTests {
    @Test
    func shellBootHydrationSkipsWhileShellSuspendedForStreaming() async {
        let coordinator = makeShellBootCoordinator()
        await coordinator.sessionController.applyTokensFromCoordinator(makeTokens(), mode: .full)
        await coordinator.streamPriorityShellController.enter(policy: .tearDownShell)

        await coordinator.shellBoot.beginShellBootHydrationIfNeeded(restoreCachesBeforeBoot: true)

        #expect(coordinator.shellBootstrapController.phase == .idle)
    }

    private func makeShellBootCoordinator() -> (
        shellBoot: AppShellBootCoordinator,
        sessionController: SessionController,
        streamPriorityShellController: AppStreamPriorityShellController,
        shellBootstrapController: ShellBootstrapController
    ) {
        let sessionController = SessionController()
        let libraryController = LibraryController()
        let profileController = ProfileController()
        let streamController = StreamController()
        let shellBootstrapController = ShellBootstrapController()
        let achievementsController = AchievementsController()
        let streamPriorityShellController = AppStreamPriorityShellController(
            dependencies: AppStreamPriorityShellDependencies(
                suspendShellBootstrap: { await shellBootstrapController.suspendForStreaming() },
                resumeShellBootstrap: { shellBootstrapController.resumeAfterStreaming() },
                suspendLibrary: { await libraryController.suspendForStreaming() },
                resumeLibrary: { libraryController.resumeAfterStreaming() },
                suspendProfile: { await profileController.suspendForStreaming() },
                resumeProfile: { profileController.resumeAfterStreaming() },
                suspendConsole: {},
                resumeConsole: {},
                suspendAchievements: { await achievementsController.suspendForStreaming() },
                resumeAchievements: { achievementsController.resumeAfterStreaming() },
                authState: { sessionController.authState },
                hasStreamingSession: { streamController.state.streamingSession != nil },
                makePostStreamHydrationPlan: { libraryController.makePostStreamHydrationPlan() },
                runPostStreamDeltaRefresh: { plan in await libraryController.refreshPostStreamResumeDelta(plan: plan) },
                runPostStreamFullRefresh: { await libraryController.refresh(forceRefresh: true, reason: .postStreamResume) },
                prefetchArtwork: {
                    let sections = libraryController.state.sections
                    guard !sections.isEmpty else { return }
                    await libraryController.prefetchLibraryArtwork(sections)
                },
                setShellStatusText: { _ in },
                setShellIsLoading: { _ in },
                markShellRestored: {}
            )
        )

        return (
            shellBoot: AppShellBootCoordinator(
                sessionController: sessionController,
                libraryController: libraryController,
                profileController: profileController,
                shellBootstrapController: shellBootstrapController,
                achievementsController: achievementsController,
                cacheRestoreWorkflow: AppCacheRestoreWorkflow(),
                startupWorkflow: AppStartupWorkflow(),
                streamPriorityShellController: streamPriorityShellController
            ),
            sessionController: sessionController,
            streamPriorityShellController: streamPriorityShellController,
            shellBootstrapController: shellBootstrapController
        )
    }

    private func makeTokens() -> StreamTokens {
        StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: "https://xcloud.example.com",
            webToken: nil,
            webTokenUHS: nil,
            xcloudRegions: []
        )
    }
}
