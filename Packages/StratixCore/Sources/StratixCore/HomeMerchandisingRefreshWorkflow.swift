// HomeMerchandisingRefreshWorkflow.swift
// Defines home merchandising refresh workflow.
//

import Foundation
import StratixModels
import XCloudAPI

struct HomeMerchandisingRefreshResult: Sendable {
    let snapshot: HomeMerchandisingSnapshot
    let discovery: HomeMerchandisingDiscoveryCachePayload
}

@MainActor
enum HomeMerchandisingRefreshWorkflow {
    struct Context: Sendable {
        let latestSections: [CloudLibrarySection]
        let existingSnapshot: HomeMerchandisingSnapshot?
        let cachedDiscovery: HomeMerchandisingDiscoveryCachePayload?
        let market: String
        let language: String
        let forceDiscoveryRefresh: Bool
        let config: LibraryHydrationConfig
    }

    struct Dependencies {
        let isDiscoveryStale: @Sendable (Date) -> Bool
        let discoverAliases: @Sendable () async throws -> GamePassSiglDiscoveryResult
        let fetchProductIDs: @Sendable (_ siglID: String, _ market: String, _ language: String) async throws -> [String]
        let formatError: (Error) -> String
        let logInfo: (String) -> Void
        let logWarning: (String) -> Void
        let logDebug: (String) -> Void
    }

    static func refresh(
        context: Context,
        dependencies: Dependencies
    ) async -> HomeMerchandisingRefreshResult {
        let discovery = await resolveDiscovery(
            context: context,
            dependencies: dependencies
        )
        let buildResult = await HomeMerchandisingSnapshotBuilder.build(
            context: .init(
                latestSections: context.latestSections,
                discovery: discovery,
                existingSnapshot: context.existingSnapshot,
                market: context.market,
                language: context.language,
                config: context.config
            ),
            fetchProductIDs: dependencies.fetchProductIDs,
            logDebug: dependencies.logDebug
        )
        return HomeMerchandisingRefreshResult(
            snapshot: buildResult.snapshot,
            discovery: buildResult.discovery
        )
    }

    private static func resolveDiscovery(
        context: Context,
        dependencies: Dependencies
    ) async -> HomeMerchandisingDiscoveryCachePayload {
        if !context.forceDiscoveryRefresh,
           let cachedDiscovery = context.cachedDiscovery,
           !dependencies.isDiscoveryStale(cachedDiscovery.savedAt) {
            dependencies.logInfo("Home merchandising SIGL discovery reused from cache: \(cachedDiscovery.entries.count)")
            return cachedDiscovery
        }

        do {
            let discoveryResult = try await dependencies.discoverAliases()
            dependencies.logInfo("Home merchandising SIGL discovery count: \(discoveryResult.entries.count)")
            return HomeMerchandisingDiscoveryCachePayload(
                entries: discoveryResult.entries,
                savedAt: Date()
            )
        } catch {
            dependencies.logWarning("Home merchandising SIGL discovery failed, using fallback map: \(dependencies.formatError(error))")
            return fallbackDiscovery(
                savedAt: Date(),
                config: context.config
            )
        }
    }

    private static func fallbackDiscovery(
        savedAt: Date,
        config: LibraryHydrationConfig
    ) -> HomeMerchandisingDiscoveryCachePayload {
        HomeMerchandisingDiscoveryCachePayload(
            entries: config.fixedHomeCategoryAliases.compactMap { alias in
                guard let siglID = GamePassSiglClient.fallbackAliasToSiglID[alias] else { return nil }
                return GamePassSiglDiscoveryEntry(
                    alias: alias,
                    label: LibraryController.displayLabel(for: alias),
                    siglID: siglID,
                    source: .fallback
                )
            },
            savedAt: savedAt
        )
    }
}
