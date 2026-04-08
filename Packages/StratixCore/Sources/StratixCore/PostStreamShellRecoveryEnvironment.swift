// PostStreamShellRecoveryEnvironment.swift
// Defines post stream shell recovery environment.
//

import Foundation

struct PostStreamShellRecoveryEnvironment {
    let makePlan: @MainActor () -> PostStreamHydrationPlan
    let runDeltaRefresh: @MainActor (PostStreamHydrationPlan) async -> PostStreamRefreshResult
    let runFullRefresh: @MainActor () async -> Void
    let prefetchArtwork: @MainActor () async -> Void
    let setStatusText: @MainActor (String?) -> Void
    let setIsLoading: @MainActor (Bool) -> Void
    let markShellRestored: @MainActor () -> Void
}
