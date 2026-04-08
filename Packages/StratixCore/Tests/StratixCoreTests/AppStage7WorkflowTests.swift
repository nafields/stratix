// AppStage7WorkflowTests.swift
// Exercises app stage7 workflow behavior.
//

import Foundation
import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct AppStage7WorkflowTests {
    @Test
    func cacheRestoreWorkflow_skipsWhenUnauthenticated() async {
        var calls: [String] = []

        await AppCacheRestoreWorkflow().run(
            environment: AppCacheRestoreEnvironment(
                isAuthenticated: false,
                restoreLibraryCaches: { _ in calls.append("library") },
                restoreAchievementCaches: { _ in calls.append("achievements") },
                restoreProfileCaches: { calls.append("profile") }
            )
        )

        #expect(calls.isEmpty)
    }

    @Test
    func cacheRestoreWorkflow_restoresAllCachesWhenAuthenticated() async {
        var calls: [String] = []

        await AppCacheRestoreWorkflow().run(
            environment: AppCacheRestoreEnvironment(
                isAuthenticated: true,
                restoreLibraryCaches: { isAuthenticated in
                    calls.append("library:\(isAuthenticated)")
                },
                restoreAchievementCaches: { isAuthenticated in
                    calls.append("achievements:\(isAuthenticated)")
                },
                restoreProfileCaches: {
                    calls.append("profile")
                }
            )
        )

        #expect(calls == ["library:true", "achievements:true", "profile"])
    }

    @Test
    func startupWorkflow_handleOnAppear_runsSettingsProbeBeforeSessionRestore() async {
        var calls: [String] = []

        await AppStartupWorkflow().handleOnAppear(
            environment: AppStartupAppearEnvironment(
                updateControllerSettings: { calls.append("settings") },
                runAppLaunchHapticsProbe: { calls.append("haptics") },
                sessionOnAppear: { calls.append("session") }
            )
        )

        #expect(calls == ["settings", "haptics", "session"])
    }

    @Test
    func startupWorkflow_beginShellBootHydration_restoresCachesBeforeBootActions() async {
        var calls: [String] = []
        let plan = ShellBootHydrationPlan(
            mode: .refreshNetwork,
            statusText: "Loading",
            deferInitialRoutePublication: true,
            minimumVisibleDuration: .zero,
            decisionDescription: "test"
        )

        await AppStartupWorkflow().beginShellBootHydrationIfNeeded(
            environment: AppStartupHydrationEnvironment(
                isShellSuspendedForStreaming: false,
                isAuthenticated: true,
                shouldRestoreCachesBeforeBoot: true,
                restoreCachesFromDisk: { calls.append("restore") },
                makeShellBootHydrationPlan: {
                    calls.append("plan")
                    return plan
                },
                beginShellBootHydration: { receivedPlan, refreshCloudLibrary, prefetchArtwork in
                    #expect(receivedPlan == plan)
                    calls.append("begin")
                    await refreshCloudLibrary(plan.deferInitialRoutePublication)
                    await prefetchArtwork()
                },
                refreshCloudLibrary: { deferInitialRoutePublication in
                    calls.append("refresh:\(deferInitialRoutePublication)")
                },
                prefetchArtwork: {
                    calls.append("prefetch")
                },
                logInfo: { message in
                    calls.append("log:\(message)")
                }
            )
        )

        #expect(calls == ["restore", "plan", "begin", "refresh:true", "prefetch"])
    }

    @Test
    func startupWorkflow_skipsCacheRestoreWhenBootRestoreIsSuppressed() async {
        var calls: [String] = []
        let plan = ShellBootHydrationPlan(
            mode: .prefetchCached,
            statusText: "Loading",
            deferInitialRoutePublication: false,
            minimumVisibleDuration: .zero,
            decisionDescription: "test"
        )

        await AppStartupWorkflow().beginShellBootHydrationIfNeeded(
            environment: AppStartupHydrationEnvironment(
                isShellSuspendedForStreaming: false,
                isAuthenticated: true,
                shouldRestoreCachesBeforeBoot: false,
                restoreCachesFromDisk: { calls.append("restore") },
                makeShellBootHydrationPlan: {
                    calls.append("plan")
                    return plan
                },
                beginShellBootHydration: { receivedPlan, _, prefetchArtwork in
                    #expect(receivedPlan == plan)
                    calls.append("begin")
                    await prefetchArtwork()
                },
                refreshCloudLibrary: { _ in
                    calls.append("refresh")
                },
                prefetchArtwork: {
                    calls.append("prefetch")
                },
                logInfo: { message in
                    calls.append("log:\(message)")
                }
            )
        )

        #expect(calls == ["plan", "begin", "prefetch"])
    }

    @Test
    func startupWorkflow_beginShellBootHydration_skipsCacheRestoreWhenAlreadyRestored() async {
        var calls: [String] = []
        let plan = ShellBootHydrationPlan(
            mode: .prefetchCached,
            statusText: "Loading",
            deferInitialRoutePublication: false,
            minimumVisibleDuration: .zero,
            decisionDescription: "test"
        )

        await AppStartupWorkflow().beginShellBootHydrationIfNeeded(
            environment: AppStartupHydrationEnvironment(
                isShellSuspendedForStreaming: false,
                isAuthenticated: true,
                shouldRestoreCachesBeforeBoot: false,
                restoreCachesFromDisk: { calls.append("restore") },
                makeShellBootHydrationPlan: {
                    calls.append("plan")
                    return plan
                },
                beginShellBootHydration: { receivedPlan, _, prefetchArtwork in
                    #expect(receivedPlan == plan)
                    calls.append("begin")
                    await prefetchArtwork()
                },
                refreshCloudLibrary: { deferInitialRoutePublication in
                    calls.append("refresh:\(deferInitialRoutePublication)")
                },
                prefetchArtwork: {
                    calls.append("prefetch")
                },
                logInfo: { message in
                    calls.append("log:\(message)")
                }
            )
        )

        #expect(calls == ["plan", "begin", "prefetch"])
    }

    @Test
    func foregroundRefreshWorkflow_refreshesTokensThenLibraryAndPrefetchWhenShellBootAlreadyStarted() async {
        var calls: [String] = []

        await AppForegroundRefreshWorkflow().run(
            environment: AppForegroundRefreshEnvironment(
                isAuthenticated: true,
                isStreamPriorityModeActive: false,
                hasStreamingSession: false,
                shellBootstrapPhase: .ready,
                refreshStreamTokens: { calls.append("tokens") },
                loadCloudLibrary: { calls.append("library") },
                hasLibrarySections: { true },
                prefetchArtwork: { calls.append("prefetch") },
                logInfo: { message in calls.append("log:\(message)") }
            )
        )

        #expect(calls == ["tokens", "library", "log:Foreground resume artwork prefetch restart", "prefetch"])
    }

    @Test
    func foregroundRefreshWorkflow_skipsWhenStreamPriorityModeActive() async {
        var calls: [String] = []

        await AppForegroundRefreshWorkflow().run(
            environment: AppForegroundRefreshEnvironment(
                isAuthenticated: true,
                isStreamPriorityModeActive: true,
                hasStreamingSession: false,
                shellBootstrapPhase: .ready,
                refreshStreamTokens: { calls.append("tokens") },
                loadCloudLibrary: { calls.append("library") },
                hasLibrarySections: { true },
                prefetchArtwork: { calls.append("prefetch") },
                logInfo: { message in calls.append(message) }
            )
        )

        #expect(calls == ["Foreground resume refresh skipped: stream priority mode active"])
    }

    @Test
    func backgroundRefreshWorkflow_reportsChangeAfterRefresh() async {
        var calls: [String] = []
        let baselineHydratedAt = Date(timeIntervalSince1970: 10)
        let refreshedHydratedAt = Date(timeIntervalSince1970: 20)

        let changed = await AppBackgroundRefreshWorkflow().run(
            environment: AppBackgroundRefreshEnvironment(
                isAuthenticated: true,
                isStreamPriorityModeActive: false,
                baselineHydratedAt: baselineHydratedAt,
                baselineItemCount: 4,
                refreshStreamTokens: { calls.append("tokens") },
                loadCloudLibrary: { calls.append("library") },
                refreshedHydratedAt: { refreshedHydratedAt },
                refreshedItemCount: { 4 },
                logInfo: { message in calls.append("log:\(message)") }
            )
        )

        #expect(changed == true)
        #expect(calls == ["tokens", "library"])
    }

    @Test
    func backgroundRefreshWorkflow_skipsWhenStreamPriorityModeActive() async {
        var calls: [String] = []

        let changed = await AppBackgroundRefreshWorkflow().run(
            environment: AppBackgroundRefreshEnvironment(
                isAuthenticated: true,
                isStreamPriorityModeActive: true,
                baselineHydratedAt: nil,
                baselineItemCount: 0,
                refreshStreamTokens: { calls.append("tokens") },
                loadCloudLibrary: { calls.append("library") },
                refreshedHydratedAt: { nil },
                refreshedItemCount: { 0 },
                logInfo: { message in calls.append(message) }
            )
        )

        #expect(changed == false)
        #expect(calls == ["Background refresh skipped: stream priority mode active"])
    }
}
