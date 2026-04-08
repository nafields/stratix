// AppBackgroundRefreshWorkflow.swift
// Defines app background refresh workflow for the App / Lifecycle surface.
//

import Foundation
import DiagnosticsKit

struct AppBackgroundRefreshEnvironment {
    let isAuthenticated: Bool
    let isStreamPriorityModeActive: Bool
    let baselineHydratedAt: Date?
    let baselineItemCount: Int
    let refreshStreamTokens: @MainActor () async -> Void
    let loadCloudLibrary: @MainActor () async -> Void
    let refreshedHydratedAt: @MainActor () -> Date?
    let refreshedItemCount: @MainActor () -> Int
    let logInfo: @MainActor (String) -> Void
}

@MainActor
final class AppBackgroundRefreshWorkflow {
    func run(environment: AppBackgroundRefreshEnvironment) async -> Bool {
        guard environment.isAuthenticated else { return false }
        guard !environment.isStreamPriorityModeActive else {
            environment.logInfo("Background refresh skipped: stream priority mode active")
            return false
        }

        StreamPerformanceTracker.mark(
            .tokenRefreshStart,
            metadata: ["reason": "background_app_refresh"]
        )
        await environment.refreshStreamTokens()
        StreamPerformanceTracker.mark(
            .tokenRefreshFinish,
            metadata: ["reason": "background_app_refresh"]
        )
        await environment.loadCloudLibrary()

        return environment.refreshedHydratedAt() != environment.baselineHydratedAt
            || environment.refreshedItemCount() != environment.baselineItemCount
    }
}
