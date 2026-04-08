// PostStreamShellRecoveryWorkflow.swift
// Defines post stream shell recovery workflow.
//

import Foundation

@MainActor
final class PostStreamShellRecoveryWorkflow {
#if DEBUG
    private(set) var invocationCount = 0
    private(set) var deltaAttemptCount = 0
    private(set) var fullRefreshFallbackCount = 0

    var testingPostStreamDeltaRefreshOverride: (@MainActor () async -> PostStreamRefreshResult)?
    var testingPostStreamFullRefreshOverride: (@MainActor () async -> Void)?
#endif

    func run(
        environment: PostStreamShellRecoveryEnvironment
    ) async {
#if DEBUG
        invocationCount += 1
#endif

        environment.setStatusText("Refreshing your cloud library...")
        environment.setIsLoading(true)
        defer {
            environment.setStatusText(nil)
            environment.setIsLoading(false)
            environment.markShellRestored()
        }

        let plan = environment.makePlan()
        let refreshResult: PostStreamRefreshResult
        if plan.mode == .refreshMRUDelta {
            refreshResult = await runDeltaRefresh(plan: plan, in: environment)
        } else {
            refreshResult = .requiresFullRefresh(plan.decisionDescription)
        }

        if case .requiresFullRefresh = refreshResult {
            await runFullRefresh(in: environment)
            await environment.prefetchArtwork()
            return
        }

        guard case .appliedDelta = refreshResult else { return }
        await environment.prefetchArtwork()
    }

    private func runDeltaRefresh(
        plan: PostStreamHydrationPlan,
        in environment: PostStreamShellRecoveryEnvironment
    ) async -> PostStreamRefreshResult {
#if DEBUG
        deltaAttemptCount += 1
        if let testingPostStreamDeltaRefreshOverride {
            return await testingPostStreamDeltaRefreshOverride()
        }
#endif
        return await environment.runDeltaRefresh(plan)
    }

    private func runFullRefresh(in environment: PostStreamShellRecoveryEnvironment) async {
#if DEBUG
        fullRefreshFallbackCount += 1
        if let testingPostStreamFullRefreshOverride {
            await testingPostStreamFullRefreshOverride()
            return
        }
#endif
        await environment.runFullRefresh()
    }
}
