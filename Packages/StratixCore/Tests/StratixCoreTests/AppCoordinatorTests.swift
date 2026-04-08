// AppCoordinatorTests.swift
// Exercises app coordinator behavior.
//

import Foundation
import Testing
import Observation
@testable import StratixCore
import StratixModels
import StreamingCore
import XCloudAPI

@MainActor
@Suite(.serialized)
struct AppCoordinatorTests {
    private let defaults = UserDefaults.standard
    private let migrationKey = "stratix.migrations.guide_show_stream_stats.v1"

    @Test
    func statsHUDMigration_copiesLegacyValueWhenGuideKeyUnset() {
        resetDefaults()
        defaults.set(true, forKey: "stratix.stream.showStatsHUD")
        defaults.removeObject(forKey: "guide.show_stream_stats")
        defaults.removeObject(forKey: migrationKey)

        _ = AppCoordinator()

        #expect(defaults.object(forKey: "guide.show_stream_stats") as? Bool == true)
    }

    @Test
    func statsHUDMigration_doesNotOverwriteExistingGuideValue() {
        resetDefaults()
        defaults.set(true, forKey: "stratix.stream.showStatsHUD")
        defaults.set(false, forKey: "guide.show_stream_stats")
        defaults.removeObject(forKey: migrationKey)

        _ = AppCoordinator()

        #expect(defaults.object(forKey: "guide.show_stream_stats") as? Bool == false)
    }

    @Test
    func explicitRegionOverride_doesNotFallbackToLegacyRegionKey() {
        resetDefaults()
        defaults.set("US East", forKey: "guide.region_override")
        defaults.set("weu", forKey: "stratix.stream.preferredRegionId")

        let coordinator = AppCoordinator()
        coordinator.testingSetXCloudRegions([
            LoginRegion(name: "weu", baseUri: "https://weu.example.com", isDefault: true)
        ])

        #expect(coordinator.testingEffectivePreferredRegionId() == nil)
    }

    @Test
    func autoRegionOverride_keepsLegacyFallbackBehavior() {
        resetDefaults()
        defaults.set("Auto", forKey: "guide.region_override")
        defaults.set("weu", forKey: "stratix.stream.preferredRegionId")

        let coordinator = AppCoordinator()
        coordinator.testingSetXCloudRegions([
            LoginRegion(name: "weu", baseUri: "https://weu.example.com", isDefault: true)
        ])

        #expect(coordinator.testingEffectivePreferredRegionId() == "weu")
    }

    @Test
    func streamRefreshTokenApply_skipsCacheRestoreAndPrewarmSideEffects() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        coordinator.libraryController.hasLoadedProductDetailsCache = false
        coordinator.libraryController.hasLoadedSectionsCache = false
        coordinator.libraryController.hasPerformedNetworkHydrationThisSession = false

        await coordinator.testingApplyTokensStreamRefresh(makeTokens())

        #expect(coordinator.libraryController.hasLoadedProductDetailsCache == false)
        #expect(coordinator.libraryController.hasLoadedSectionsCache == false)
        #expect(await coordinator.testingIsCloudLibraryLoadTaskActive() == false)
    }

    @Test
    func fullTokenApply_startsShellBootHydrationWithoutExplicitViewTrigger() async {
        resetDefaults()
        let coordinator = AppCoordinator()

        #expect(coordinator.shellBootstrapController.phase == .idle)

        await coordinator.testingApplyTokensFull(makeTokens())

        #expect(coordinator.shellBootstrapController.phase != .idle)
    }

    @Test
    func fullTokenApply_doesNotPiggybackOnForegroundRefreshWorkflow() async {
        resetDefaults()
        let coordinator = AppCoordinator()

        #expect(coordinator.sessionController.testingLastTokenRefreshAttemptAt == nil)

        await coordinator.testingApplyTokensFull(makeTokens())

        #expect(coordinator.sessionController.testingLastTokenRefreshAttemptAt == nil)
    }

    @Test
    func authCompletion_and_authenticatedShellEntry_doNotDoubleStartStartupPipeline() async {
        resetDefaults()
        let coordinator = AppCoordinator()

        await coordinator.testingApplyTokensFull(makeTokens())

        let firstTask = await coordinator.shellBootstrapController.taskRegistry.task(
            id: "shell.hydration",
            as: Task<Void, Never>.self
        )
        #expect(firstTask != nil)

        await coordinator.beginShellBootHydrationIfNeeded()

        let secondTask = await coordinator.shellBootstrapController.taskRegistry.task(
            id: "shell.hydration",
            as: Task<Void, Never>.self
        )
        #expect(secondTask != nil)
    }

    @Test
    func shellBootHydration_restoresCachesBeforeMakingStartupDecision() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        coordinator.libraryController.hasLoadedProductDetailsCache = false
        coordinator.libraryController.hasLoadedSectionsCache = false
        coordinator.libraryController.hasPerformedNetworkHydrationThisSession = false

        await coordinator.testingApplyTokensStreamRefresh(makeTokens())
        #expect(coordinator.libraryController.hasLoadedProductDetailsCache == false)
        #expect(coordinator.libraryController.hasLoadedSectionsCache == false)

        await coordinator.beginShellBootHydrationIfNeeded()

        #expect(coordinator.libraryController.hasLoadedProductDetailsCache == true)
        #expect(coordinator.libraryController.hasLoadedSectionsCache == true)
    }

    @Test
    func shellBootHydration_skipsWhileShellSuspendedForStreaming() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())

        await coordinator.streamController.enterStreamPriorityMode(context: .cloud(titleId: TitleID("1234")))
        await coordinator.beginShellBootHydrationIfNeeded()

        #expect(coordinator.shellBootstrapController.phase == .idle)
    }

    @Test
    func streamExit_invokesDedicatedPostStreamRefresh() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())

        await coordinator.streamController.enterStreamPriorityMode(context: .cloud(titleId: TitleID("1234")))
        #expect(coordinator.testingPostStreamRefreshInvocationCount == 0)
        #expect(coordinator.streamController.shellRestoredAfterStreamExit == false)

        await coordinator.streamController.exitStreamPriorityMode()

        #expect(coordinator.testingPostStreamRefreshInvocationCount == 1)
        #expect(coordinator.streamController.shellRestoredAfterStreamExit == true)
    }

    @Test
    func streamExit_marksShellRestored_only_afterPostStreamRecoveryCompletes() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())
        primeFreshPostStreamDeltaState(coordinator)

        var fullRefreshObservedShellRestored = true
        coordinator.testingSetPostStreamDeltaRefreshOverride { .requiresFullRefresh("fallback") }
        coordinator.testingSetPostStreamFullRefreshOverride {
            fullRefreshObservedShellRestored = coordinator.streamController.shellRestoredAfterStreamExit
        }

        await coordinator.streamController.enterStreamPriorityMode(context: .cloud(titleId: TitleID("1234")))
        #expect(coordinator.streamController.shellRestoredAfterStreamExit == false)

        await coordinator.streamController.exitStreamPriorityMode()

        #expect(fullRefreshObservedShellRestored == false)
        #expect(coordinator.streamController.shellRestoredAfterStreamExit == true)
    }

    @Test
    func streamExit_prefersPostStreamDeltaRefreshWithoutFullFallback() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())
        primeFreshPostStreamDeltaState(coordinator)
        coordinator.testingSetPostStreamDeltaRefreshOverride { .appliedDelta }
        coordinator.testingSetPostStreamFullRefreshOverride {
            Issue.record("Full refresh fallback should not run when post-stream delta succeeds.")
        }

        await coordinator.streamController.enterStreamPriorityMode(context: .cloud(titleId: TitleID("1234")))
        await coordinator.streamController.exitStreamPriorityMode()

        #expect(coordinator.testingPostStreamRefreshInvocationCount == 1)
        #expect(coordinator.testingPostStreamDeltaAttemptCount == 1)
        #expect(coordinator.testingPostStreamFullRefreshFallbackCount == 0)
    }

    @Test
    func streamExit_noChangePostStreamDeltaDoesNotTriggerFullFallback() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())
        primeFreshPostStreamDeltaState(coordinator)
        coordinator.testingSetPostStreamDeltaRefreshOverride { .noChange }
        coordinator.testingSetPostStreamFullRefreshOverride {
            Issue.record("Full refresh fallback should not run when post-stream delta has no changes.")
        }

        await coordinator.streamController.enterStreamPriorityMode(context: .cloud(titleId: TitleID("1234")))
        await coordinator.streamController.exitStreamPriorityMode()

        #expect(coordinator.testingPostStreamRefreshInvocationCount == 1)
        #expect(coordinator.testingPostStreamDeltaAttemptCount == 1)
        #expect(coordinator.testingPostStreamFullRefreshFallbackCount == 0)
    }

    @Test
    func streamExit_fallsBackToFullRefreshWhenPostStreamDeltaFails() async {
        final class FallbackCounter {
            var value = 0
        }

        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())
        primeFreshPostStreamDeltaState(coordinator)

        let fallbackCounter = FallbackCounter()
        coordinator.testingSetPostStreamDeltaRefreshOverride { .requiresFullRefresh("mru_fetch_failed") }
        coordinator.testingSetPostStreamFullRefreshOverride {
            fallbackCounter.value += 1
        }

        await coordinator.streamController.enterStreamPriorityMode(context: .cloud(titleId: TitleID("1234")))
        await coordinator.streamController.exitStreamPriorityMode()

        #expect(coordinator.testingPostStreamRefreshInvocationCount == 1)
        #expect(coordinator.testingPostStreamDeltaAttemptCount == 1)
        #expect(coordinator.testingPostStreamFullRefreshFallbackCount == 1)
        #expect(fallbackCounter.value == 1)
    }

    @Test
    func streamExit_plannerNetworkModeSkipsDeltaAttemptAndRunsFullFallback() async {
        final class FallbackCounter {
            var value = 0
        }

        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())
        coordinator.libraryController.apply([
            .sectionsReplaced([
                CloudLibrarySection(id: "library", name: "Library", items: [])
            ]),
            .homeMerchandisingSet(nil),
            .homeMerchandisingCompletionSet(false),
            .lastHydratedAtSet(nil)
        ])

        let fallbackCounter = FallbackCounter()
        coordinator.testingSetPostStreamDeltaRefreshOverride {
            Issue.record("Delta refresh should not be attempted when the planner requires a full refresh.")
            return .appliedDelta
        }
        coordinator.testingSetPostStreamFullRefreshOverride {
            fallbackCounter.value += 1
        }

        await coordinator.streamController.enterStreamPriorityMode(context: .cloud(titleId: TitleID("1234")))
        await coordinator.streamController.exitStreamPriorityMode()

        #expect(coordinator.testingPostStreamRefreshInvocationCount == 1)
        #expect(coordinator.testingPostStreamDeltaAttemptCount == 0)
        #expect(coordinator.testingPostStreamFullRefreshFallbackCount == 1)
        #expect(fallbackCounter.value == 1)
    }

    @Test
    func backgroundRefresh_skipsWhileStreamPriorityModeActive() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())
        coordinator.streamController.apply(.runtimePhaseSet(.streaming))

        let refreshed = await coordinator.performBackgroundAppRefresh()

        #expect(refreshed == false)
    }

    @Test
    func signOut_resetsControllerGraphThroughWorkflow() async {
        resetDefaults()
        let coordinator = AppCoordinator()
        await coordinator.testingApplyTokensFull(makeTokens())

        coordinator.consoleController.setConsoles([makeRemoteConsole()])
        coordinator.profileController.setCurrentUserPresence(
            XboxCurrentUserPresence(xuid: "123", state: "Online", devices: [], lastSeen: nil)
        )
        coordinator.libraryController.apply([
            .sectionsReplaced([
                CloudLibrarySection(id: "library", name: "Library", items: [])
            ]),
            .lastHydratedAtSet(Date())
        ])
        coordinator.streamController.apply(.shellRestoredAfterExitSet(true))

        await coordinator.handleSessionDidSignOutFromController()

        #expect(coordinator.consoleController.consoles.isEmpty)
        #expect(coordinator.profileController.currentUserPresence == nil)
        #expect(coordinator.libraryController.sections.isEmpty)
        #expect(coordinator.shellBootstrapController.phase == .idle)
        #expect(coordinator.streamController.shellRestoredAfterStreamExit == false)
    }

    // MARK: - Streaming session observation

    @Test
    func streamingSessionObservation_invalidatesOnlyOnReferenceChange() {
        final class InvalidationCounter: @unchecked Sendable {
            var value = 0
        }

        let coordinator = AppCoordinator()
        let invalidationCount = InvalidationCounter()

        withObservationTracking {
            _ = coordinator.streamController.streamingSession
        } onChange: {
            invalidationCount.value += 1
        }

        _ = coordinator.streamController.streamingSession
        _ = coordinator.streamController.streamingSession

        #expect(invalidationCount.value == 0)

        coordinator.streamController.apply(.streamingSessionSet(makeStreamingSession()))

        #expect(invalidationCount.value == 1)
    }

    @Test
    func streamingSessionObservation_doesNotInvalidateWhenReferenceStaysStable() {
        final class InvalidationCounter: @unchecked Sendable {
            var value = 0
        }

        let coordinator = AppCoordinator()
        let session = makeStreamingSession()
        let invalidationCount = InvalidationCounter()
        coordinator.streamController.apply(.streamingSessionSet(session))

        withObservationTracking {
            _ = coordinator.streamController.streamingSession
        } onChange: {
            invalidationCount.value += 1
        }

        session.reportRendererDecodeFailure("decode failure")

        #expect(invalidationCount.value == 0)
    }

    @Test
    func observationTracking_doesNotInvalidateWhenChildControllerMutates() {
        final class InvalidationCounter: @unchecked Sendable {
            var value = 0
        }

        let coordinator = AppCoordinator()
        let invalidationCount = InvalidationCounter()

        withObservationTracking {
            _ = coordinator.libraryController
        } onChange: {
            invalidationCount.value += 1
        }

        coordinator.libraryController.apply(
            coordinator.libraryController.isLoading ? .loadingFinished : .loadingStarted
        )

        #expect(invalidationCount.value == 0)
    }

    @Test
    func shellBootPlan_prefetchesWhenFreshUnifiedSnapshotExists() {
        resetDefaults()
        let coordinator = AppCoordinator()
        coordinator.libraryController.apply([
            .sectionsReplaced([
                CloudLibrarySection(id: "library", name: "Library", items: [])
            ]),
            .homeMerchandisingSet(
                HomeMerchandisingSnapshot(recentlyAddedItems: [], rows: [], generatedAt: Date())
            ),
            .homeMerchandisingCompletionSet(true),
            .lastHydratedAtSet(Date())
        ])

        let plan = coordinator.libraryController.makeShellBootHydrationPlan(isAuthenticated: true)

        #expect(plan?.mode == .prefetchCached)
        #expect(plan?.deferInitialRoutePublication == false)
    }

    private func resetDefaults() {
        let keys = [
            "guide.show_stream_stats",
            "stratix.stream.showStatsHUD",
            migrationKey,
            "guide.region_override",
            "stratix.stream.preferredRegionId"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
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

    private func primeFreshPostStreamDeltaState(_ coordinator: AppCoordinator) {
        let sections = [
            CloudLibrarySection(
                id: "library",
                name: "Library",
                items: [
                    CloudLibraryItem(
                        titleId: "title-1",
                        productId: "product-1",
                        name: "Halo Infinite",
                        shortDescription: nil,
                        artURL: URL(string: "https://example.com/title-1.jpg"),
                        supportedInputTypes: ["controller"],
                        isInMRU: false
                    )
                ]
            )
        ]
        coordinator.libraryController.apply([
            .sectionsReplaced(sections),
            .homeMerchandisingSet(
                HomeMerchandisingSnapshot(
                    recentlyAddedItems: sections[0].items,
                    rows: [],
                    generatedAt: Date()
                )
            ),
            .homeMerchandisingCompletionSet(true),
            .lastHydratedAtSet(Date())
        ])
    }
}
