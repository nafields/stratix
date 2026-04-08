// AppStreamPriorityShellControllerTests.swift
// Exercises app stream priority shell controller behavior.
//

import Foundation
import Testing
@testable import StratixCore
import XCloudAPI

@MainActor
@Suite(.serialized)
struct AppStreamPriorityShellControllerTests {
    @Test
    func exit_runsPostStreamDeltaRecoveryThroughExtractedController() async {
        var events: [String] = []
        var statusTexts: [String?] = []
        var loadingStates: [Bool] = []
        var restoredMarks = 0

        let controller = AppStreamPriorityShellController(
            dependencies: AppStreamPriorityShellDependencies(
                suspendShellBootstrap: { events.append("suspend:shell") },
                resumeShellBootstrap: { events.append("resume:shell") },
                suspendLibrary: { events.append("suspend:library") },
                resumeLibrary: { events.append("resume:library") },
                suspendProfile: { events.append("suspend:profile") },
                resumeProfile: { events.append("resume:profile") },
                suspendConsole: { events.append("suspend:console") },
                resumeConsole: { events.append("resume:console") },
                suspendAchievements: { events.append("suspend:achievements") },
                resumeAchievements: { events.append("resume:achievements") },
                authState: { .authenticated(makeTokens()) },
                hasStreamingSession: { false },
                makePostStreamHydrationPlan: {
                    PostStreamHydrationPlan(mode: .refreshMRUDelta, decisionDescription: "fresh_cache")
                },
                runPostStreamDeltaRefresh: { plan in
                    #expect(plan.mode == .refreshMRUDelta)
                    events.append("delta")
                    return .appliedDelta
                },
                runPostStreamFullRefresh: {
                    events.append("full")
                },
                prefetchArtwork: {
                    events.append("prefetch")
                },
                setShellStatusText: { text in
                    statusTexts.append(text)
                },
                setShellIsLoading: { isLoading in
                    loadingStates.append(isLoading)
                },
                markShellRestored: {
                    restoredMarks += 1
                }
            )
        )

        await controller.enter(policy: .tearDownShell)
        #expect(controller.isShellSuspendedForStreaming == true)

        await controller.exit()

        #expect(controller.isShellSuspendedForStreaming == false)
        #expect(events == [
            "suspend:shell",
            "suspend:library",
            "suspend:profile",
            "suspend:console",
            "suspend:achievements",
            "resume:shell",
            "resume:library",
            "resume:profile",
            "resume:console",
            "resume:achievements",
            "delta",
            "prefetch",
        ])
        #expect(statusTexts == ["Refreshing your cloud library...", nil])
        #expect(loadingStates == [true, false])
        #expect(restoredMarks == 1)
        #expect(controller.invocationCount == 1)
        #expect(controller.deltaAttemptCount == 1)
        #expect(controller.fullRefreshFallbackCount == 0)
    }

    @Test
    func exit_skipsRecoveryWhenUnauthenticatedButStillRestoresShell() async {
        var deltaCalls = 0
        var fullRefreshCalls = 0
        var restoredMarks = 0
        var loadingStates: [Bool] = []

        let controller = AppStreamPriorityShellController(
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
                    PostStreamHydrationPlan(mode: .refreshMRUDelta, decisionDescription: "unused")
                },
                runPostStreamDeltaRefresh: { _ in
                    deltaCalls += 1
                    return .appliedDelta
                },
                runPostStreamFullRefresh: {
                    fullRefreshCalls += 1
                },
                prefetchArtwork: {},
                setShellStatusText: { _ in },
                setShellIsLoading: { isLoading in loadingStates.append(isLoading) },
                markShellRestored: { restoredMarks += 1 }
            )
        )

        await controller.enter(policy: .tearDownShell)
        await controller.exit()

        #expect(deltaCalls == 0)
        #expect(fullRefreshCalls == 0)
        #expect(restoredMarks == 1)
        #expect(loadingStates == [false])
        #expect(controller.invocationCount == 0)
    }

    @Test
    func exit_doesNotMarkShellRestoredWhileStreamingSessionStillExists() async {
        var deltaCalls = 0
        var fullRefreshCalls = 0
        var restoredMarks = 0
        var statusTexts: [String?] = []
        var loadingStates: [Bool] = []

        let controller = AppStreamPriorityShellController(
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
                authState: { .authenticated(makeTokens()) },
                hasStreamingSession: { true },
                makePostStreamHydrationPlan: {
                    PostStreamHydrationPlan(mode: .refreshMRUDelta, decisionDescription: "unused")
                },
                runPostStreamDeltaRefresh: { _ in
                    deltaCalls += 1
                    return .appliedDelta
                },
                runPostStreamFullRefresh: {
                    fullRefreshCalls += 1
                },
                prefetchArtwork: {},
                setShellStatusText: { text in statusTexts.append(text) },
                setShellIsLoading: { isLoading in loadingStates.append(isLoading) },
                markShellRestored: { restoredMarks += 1 }
            )
        )

        await controller.enter(policy: .tearDownShell)
        await controller.exit()

        #expect(deltaCalls == 0)
        #expect(fullRefreshCalls == 0)
        #expect(restoredMarks == 0)
        #expect(statusTexts == [nil])
        #expect(loadingStates == [false])
        #expect(controller.invocationCount == 0)
    }

    @Test
    func exit_noChangeDelta_still_marksShellRestored_afterRecoveryCompletes() async {
        var events: [String] = []
        var restoredMarks = 0

        let controller = AppStreamPriorityShellController(
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
                authState: { .authenticated(makeTokens()) },
                hasStreamingSession: { false },
                makePostStreamHydrationPlan: {
                    PostStreamHydrationPlan(mode: .refreshMRUDelta, decisionDescription: "delta")
                },
                runPostStreamDeltaRefresh: { _ in
                    events.append("delta")
                    return .noChange
                },
                runPostStreamFullRefresh: {
                    events.append("full")
                },
                prefetchArtwork: {
                    events.append("prefetch")
                },
                setShellStatusText: { _ in },
                setShellIsLoading: { _ in },
                markShellRestored: {
                    events.append("restored")
                    restoredMarks += 1
                }
            )
        )

        await controller.enter(policy: .tearDownShell)
        await controller.exit()

        #expect(events == ["delta", "restored"])
        #expect(restoredMarks == 1)
    }

    @Test
    func exit_fullRefreshFallback_defersRestored_untilFullRefreshCompletes() async {
        var events: [String] = []
        var restoredMarks = 0

        let controller = AppStreamPriorityShellController(
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
                authState: { .authenticated(makeTokens()) },
                hasStreamingSession: { false },
                makePostStreamHydrationPlan: {
                    PostStreamHydrationPlan(mode: .refreshMRUDelta, decisionDescription: "fallback")
                },
                runPostStreamDeltaRefresh: { _ in
                    events.append("delta")
                    return .requiresFullRefresh("fallback")
                },
                runPostStreamFullRefresh: {
                    events.append("full")
                },
                prefetchArtwork: {
                    events.append("prefetch")
                },
                setShellStatusText: { _ in },
                setShellIsLoading: { _ in },
                markShellRestored: {
                    events.append("restored")
                    restoredMarks += 1
                }
            )
        )

        await controller.enter(policy: .tearDownShell)
        await controller.exit()

        #expect(events == ["delta", "full", "prefetch", "restored"])
        #expect(restoredMarks == 1)
    }

    private func makeTokens() -> StreamTokens {
        StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: "https://xcloud.example.com",
            xcloudF2PToken: nil,
            xcloudF2PHost: nil
        )
    }
}
