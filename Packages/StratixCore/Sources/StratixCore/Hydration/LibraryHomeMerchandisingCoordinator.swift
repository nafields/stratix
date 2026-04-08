// LibraryHomeMerchandisingCoordinator.swift
// Defines the library home merchandising coordinator for the Hydration surface.
//

import Foundation
import StratixModels
import XCloudAPI

@MainActor
struct LibraryHomeMerchandisingCoordinator {
    struct Dependencies {
        let hydrationPlanner: LibraryHydrationPlanner
        let homeMerchandisingSIGLProvider: LibraryController.HomeMerchandisingSIGLProvider
        let config: LibraryHydrationConfig
        let existingSnapshot: () -> HomeMerchandisingSnapshot?
        let cachedDiscovery: () -> HomeMerchandisingDiscoveryCachePayload?
        let setCachedDiscovery: (HomeMerchandisingDiscoveryCachePayload?) -> Void
        let isSuspendedForStreaming: () -> Bool
        let applyActions: ([LibraryAction]) -> Void
        let formatError: (Error) -> String
        let logInfo: (String) -> Void
        let logWarning: (String) -> Void
        let logDebug: (String) -> Void
    }

    func refreshForHydration(
        latestSections: [CloudLibrarySection],
        market: String,
        language: String,
        forceDiscoveryRefresh: Bool,
        dependencies: Dependencies
    ) async -> HomeMerchandisingRefreshResult {
        await HomeMerchandisingRefreshWorkflow.refresh(
            context: .init(
                latestSections: latestSections,
                existingSnapshot: dependencies.existingSnapshot(),
                cachedDiscovery: dependencies.cachedDiscovery(),
                market: market,
                language: language,
                forceDiscoveryRefresh: forceDiscoveryRefresh,
                config: dependencies.config
            ),
            dependencies: .init(
                isDiscoveryStale: { [hydrationPlanner = dependencies.hydrationPlanner] savedAt in
                    hydrationPlanner.isUnifiedHydrationStale(generatedAt: savedAt)
                },
                discoverAliases: dependencies.homeMerchandisingSIGLProvider.discoverAliases,
                fetchProductIDs: dependencies.homeMerchandisingSIGLProvider.fetchProductIDs,
                formatError: dependencies.formatError,
                logInfo: dependencies.logInfo,
                logWarning: dependencies.logWarning,
                logDebug: dependencies.logDebug
            )
        )
    }

    func refreshSnapshot(
        latestSections: [CloudLibrarySection],
        market: String,
        language: String,
        forceDiscoveryRefresh: Bool,
        dependencies: Dependencies
    ) async {
        guard !dependencies.isSuspendedForStreaming() else {
            dependencies.logInfo("Home merchandising refresh skipped: suspended for streaming")
            return
        }
        dependencies.applyActions([.homeMerchandisingLoadingSet(true)])
        defer {
            dependencies.applyActions([.homeMerchandisingLoadingSet(false), .homeMerchandisingCompletionSet(true)])
        }

        let result = await refreshForHydration(
            latestSections: latestSections,
            market: market,
            language: language,
            forceDiscoveryRefresh: forceDiscoveryRefresh,
            dependencies: dependencies
        )
        dependencies.setCachedDiscovery(result.discovery)
        dependencies.applyActions([
            .discoveryEntriesSet(result.discovery.entries),
            .homeMerchandisingSet(result.snapshot),
            .homeMerchandisingSessionSourceSet(.liveRecovery)
        ])
    }
}
