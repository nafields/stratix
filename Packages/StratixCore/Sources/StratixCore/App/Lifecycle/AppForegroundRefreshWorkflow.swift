// AppForegroundRefreshWorkflow.swift
// Defines app foreground refresh workflow for the App / Lifecycle surface.
//

import Foundation
import DiagnosticsKit

struct AppForegroundRefreshEnvironment {
    let isAuthenticated: Bool
    let isStreamPriorityModeActive: Bool
    let hasStreamingSession: Bool
    let shellBootstrapPhase: ShellBootstrapController.BootstrapPhase
    let refreshStreamTokens: @MainActor () async -> Void
    let loadCloudLibrary: @MainActor () async -> Void
    let hasLibrarySections: @MainActor () -> Bool
    let prefetchArtwork: @MainActor () async -> Void
    let logInfo: @MainActor (String) -> Void
}

@MainActor
final class AppForegroundRefreshWorkflow {
    func run(environment: AppForegroundRefreshEnvironment) async {
        guard environment.isAuthenticated else { return }
        guard !environment.isStreamPriorityModeActive else {
            environment.logInfo("Foreground resume refresh skipped: stream priority mode active")
            return
        }

        StreamPerformanceTracker.mark(
            .tokenRefreshStart,
            metadata: ["reason": "foreground_resume"]
        )
        await environment.refreshStreamTokens()
        StreamPerformanceTracker.mark(
            .tokenRefreshFinish,
            metadata: ["reason": "foreground_resume"]
        )

        guard !environment.hasStreamingSession else { return }
        guard case .idle = environment.shellBootstrapPhase else {
            await environment.loadCloudLibrary()
            guard environment.hasLibrarySections() else { return }
            environment.logInfo("Foreground resume artwork prefetch restart")
            await environment.prefetchArtwork()
            return
        }

        environment.logInfo("Foreground resume cloud library refresh skipped: shell boot hydration not started yet")
    }
}
