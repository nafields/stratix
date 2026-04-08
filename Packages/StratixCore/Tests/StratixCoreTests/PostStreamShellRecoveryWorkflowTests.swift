// PostStreamShellRecoveryWorkflowTests.swift
// Exercises post stream shell recovery workflow behavior.
//

import Foundation
import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct PostStreamShellRecoveryWorkflowTests {
    @Test
    func run_usesFullRefreshWhenPlanModeIsNotDelta() async {
        let workflow = PostStreamShellRecoveryWorkflow()
        var fullRefreshCount = 0
        var deltaRefreshCount = 0
        var prefetchCount = 0

        await workflow.run(
            environment: makeEnvironment(
                makePlan: { .init(mode: .refreshNetwork, decisionDescription: "network") },
                runDeltaRefresh: { _ in
                    deltaRefreshCount += 1
                    return .appliedDelta
                },
                runFullRefresh: {
                    fullRefreshCount += 1
                },
                prefetchArtwork: {
                    prefetchCount += 1
                }
            )
        )

        #expect(fullRefreshCount == 1)
        #expect(deltaRefreshCount == 0)
        #expect(prefetchCount == 1)
    }

    @Test
    func run_usesDeltaRefreshWhenPlanRequestsDelta() async {
        let workflow = PostStreamShellRecoveryWorkflow()
        var deltaRefreshCount = 0

        await workflow.run(
            environment: makeEnvironment(
                runDeltaRefresh: { _ in
                    deltaRefreshCount += 1
                    return .noChange
                }
            )
        )

        #expect(deltaRefreshCount == 1)
    }

    @Test
    func run_fallsBackToFullRefreshWhenDeltaRequiresFallback() async {
        let workflow = PostStreamShellRecoveryWorkflow()
        var deltaRefreshCount = 0
        var fullRefreshCount = 0
        var prefetchCount = 0

        await workflow.run(
            environment: makeEnvironment(
                runDeltaRefresh: { _ in
                    deltaRefreshCount += 1
                    return .requiresFullRefresh("fallback")
                },
                runFullRefresh: {
                    fullRefreshCount += 1
                },
                prefetchArtwork: {
                    prefetchCount += 1
                }
            )
        )

        #expect(deltaRefreshCount == 1)
        #expect(fullRefreshCount == 1)
        #expect(prefetchCount == 1)
    }

    @Test
    func run_prefetchesArtworkWhenDeltaApplied() async {
        let workflow = PostStreamShellRecoveryWorkflow()
        var fullRefreshCount = 0
        var prefetchCount = 0

        await workflow.run(
            environment: makeEnvironment(
                runDeltaRefresh: { _ in .appliedDelta },
                runFullRefresh: {
                    fullRefreshCount += 1
                },
                prefetchArtwork: {
                    prefetchCount += 1
                }
            )
        )

        #expect(fullRefreshCount == 0)
        #expect(prefetchCount == 1)
    }

    @Test
    func run_prefetchesArtworkAfterFallbackFullRefresh() async {
        let workflow = PostStreamShellRecoveryWorkflow()
        var fullRefreshCount = 0
        var prefetchCount = 0

        await workflow.run(
            environment: makeEnvironment(
                runDeltaRefresh: { _ in .requiresFullRefresh("fallback") },
                runFullRefresh: {
                    fullRefreshCount += 1
                },
                prefetchArtwork: {
                    prefetchCount += 1
                }
            )
        )

        #expect(fullRefreshCount == 1)
        #expect(prefetchCount == 1)
    }

    @Test
    func run_prefetchesArtworkAfterDirectFullRefreshPlan() async {
        let workflow = PostStreamShellRecoveryWorkflow()
        var fullRefreshCount = 0
        var prefetchCount = 0

        await workflow.run(
            environment: makeEnvironment(
                makePlan: { .init(mode: .refreshNetwork, decisionDescription: "network") },
                runFullRefresh: {
                    fullRefreshCount += 1
                },
                prefetchArtwork: {
                    prefetchCount += 1
                }
            )
        )

        #expect(fullRefreshCount == 1)
        #expect(prefetchCount == 1)
    }

    @Test
    func run_clearsShellLoadingStatusOnExit() async {
        let workflow = PostStreamShellRecoveryWorkflow()
        var statusTransitions: [String?] = []
        var loadingTransitions: [Bool] = []
        var restoredMarks = 0

        await workflow.run(
            environment: makeEnvironment(
                setStatusText: { statusTransitions.append($0) },
                setIsLoading: { loadingTransitions.append($0) },
                markShellRestored: { restoredMarks += 1 }
            )
        )

        #expect(statusTransitions == ["Refreshing your cloud library...", nil])
        #expect(loadingTransitions == [true, false])
        #expect(restoredMarks == 1)
    }

    private func makeEnvironment(
        makePlan: @escaping @MainActor () -> PostStreamHydrationPlan = {
            .init(mode: .refreshMRUDelta, decisionDescription: "delta")
        },
        runDeltaRefresh: @escaping @MainActor (PostStreamHydrationPlan) async -> PostStreamRefreshResult = { _ in .noChange },
        runFullRefresh: @escaping @MainActor () async -> Void = {},
        prefetchArtwork: @escaping @MainActor () async -> Void = {},
        setStatusText: @escaping @MainActor (String?) -> Void = { _ in },
        setIsLoading: @escaping @MainActor (Bool) -> Void = { _ in },
        markShellRestored: @escaping @MainActor () -> Void = {}
    ) -> PostStreamShellRecoveryEnvironment {
        PostStreamShellRecoveryEnvironment(
            makePlan: makePlan,
            runDeltaRefresh: runDeltaRefresh,
            runFullRefresh: runFullRefresh,
            prefetchArtwork: prefetchArtwork,
            setStatusText: setStatusText,
            setIsLoading: setIsLoading,
            markShellRestored: markShellRestored
        )
    }
}
