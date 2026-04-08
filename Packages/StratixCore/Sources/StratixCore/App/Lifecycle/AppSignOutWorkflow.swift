// AppSignOutWorkflow.swift
// Defines app sign out workflow for the App / Lifecycle surface.
//

import Foundation

@MainActor
struct AppSignOutEnvironment {
    let resetConsole: @MainActor @Sendable () async -> Void
    let resetLibrary: @MainActor @Sendable () async -> Void
    let clearLibraryCaches: @MainActor @Sendable () async -> Void
    let resetShellBootstrap: @MainActor @Sendable () async -> Void
    let resetAchievements: @MainActor @Sendable () async -> Void
    let clearAchievementCaches: @MainActor @Sendable () async -> Void
    let clearProfileCaches: @MainActor @Sendable () async -> Void
    let resetStream: @MainActor @Sendable () async -> Void
    let resetInput: @MainActor @Sendable () async -> Void
    let resetProfile: @MainActor @Sendable () async -> Void
}

@MainActor
struct AppSignOutWorkflow {
    func run(environment: AppSignOutEnvironment) async {
        await environment.resetConsole()
        await environment.resetLibrary()
        await environment.clearLibraryCaches()
        await environment.resetShellBootstrap()
        await environment.resetAchievements()
        await environment.clearAchievementCaches()
        await environment.clearProfileCaches()
        await environment.resetStream()
        await environment.resetInput()
        await environment.resetProfile()
    }
}
