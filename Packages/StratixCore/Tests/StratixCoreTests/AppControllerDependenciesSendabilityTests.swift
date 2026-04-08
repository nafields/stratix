// AppControllerDependenciesSendabilityTests.swift
// Exercises app controller dependencies sendability behavior.
//

import Foundation
@testable import StratixCore
import Testing

@MainActor
@Suite(.serialized)
struct AppControllerDependenciesSendabilityTests {
    @Test
    func appControllerDependencyBundlesRemainSendable() {
        let coordinator = AppCoordinator()

        let networkSessionProvider = AppNetworkSessionProvider(
            settingsStore: coordinator.settingsStore
        )
        let streamPriorityShellController = AppStreamPriorityShellController(
            postStreamShellRecoveryWorkflow: PostStreamShellRecoveryWorkflow(),
            dependencies: AppStreamPriorityShellDependencies(
                suspendShellBootstrap: {},
                resumeShellBootstrap: {},
                suspendLibrary: {},
                resumeLibrary: {},
                suspendProfile: {},
                resumeProfile: {},
                suspendConsole: {},
                resumeConsole: {},
                suspendAchievements: {},
                resumeAchievements: {},
                authState: { .unauthenticated },
                hasStreamingSession: { false },
                makePostStreamHydrationPlan: {
                    PostStreamHydrationPlan(mode: .refreshNetwork, decisionDescription: "test")
                },
                runPostStreamDeltaRefresh: { _ in .noChange },
                runPostStreamFullRefresh: {},
                prefetchArtwork: {},
                setShellStatusText: { _ in },
                setShellIsLoading: { _ in },
                markShellRestored: {}
            )
        )

        let libraryServices = AppLibraryControllerServices(
            sessionController: coordinator.sessionController,
            profileController: coordinator.profileController,
            achievementsController: coordinator.achievementsController
        )
        let streamServices = AppStreamControllerServices(
            settingsStore: coordinator.settingsStore,
            sessionController: coordinator.sessionController,
            libraryController: coordinator.libraryController,
            consoleController: coordinator.consoleController,
            achievementsController: coordinator.achievementsController,
            inputController: coordinator.inputController,
            networkSessionProvider: networkSessionProvider,
            videoCapabilitiesBootstrapProbe: VideoCapabilitiesBootstrapProbe(),
            streamPriorityShellController: streamPriorityShellController
        )

        requireSendable(libraryServices)
        requireSendable(streamServices)
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
