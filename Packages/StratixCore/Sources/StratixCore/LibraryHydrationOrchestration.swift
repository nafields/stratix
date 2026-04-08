// LibraryHydrationOrchestration.swift
// Defines library hydration orchestration.
//

import Foundation
import StratixModels
import XCloudAPI

@MainActor
extension LibraryController {
    func makeShellBootHydrationPlan(isAuthenticated: Bool) -> ShellBootHydrationPlan? {
        hydrationPlanner.makeShellBootPlan(
            isAuthenticated: isAuthenticated,
            hasFreshCompleteStartupSnapshot: hasFreshCompleteStartupSnapshot
        )
    }

    func makePostStreamHydrationPlan() -> PostStreamHydrationPlan {
        hydrationPlanner.makePostStreamPlan(
            sections: sections,
            homeMerchandising: homeMerchandising,
            hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
            lastHydratedAt: lastHydratedAt,
            cacheSavedAt: cacheSavedAt
        )
    }

    func applyHydrationOrchestrationResult(
        _ result: LibraryHydrationOrchestrationResult
    ) async {
        if let discovery = result.cachedDiscovery {
            cachedHomeMerchandisingDiscovery = discovery
        }
        let publicationResult = await publicationCoordinator.publish(
            actions: result.actions,
            plan: result.publicationPlan,
            controller: self
        )
        trimProductDetailsCacheToLimit()

        await hydrationPersistenceStore.schedule(
            result.persistenceIntent,
            publicationPlan: result.publicationPlan,
            publicationResult: publicationResult
        )
    }

    func refreshPostStreamResumeDelta(
        plan: PostStreamHydrationPlan
    ) async -> PostStreamRefreshResult {
        guard !isSuspendedForStreaming else {
            logger.info("Post-stream delta refresh skipped: suspended for streaming")
            return .requiresFullRefresh("suspended_for_streaming")
        }
        guard plan.mode == .refreshMRUDelta else {
            logger.info("Post-stream delta refresh escalated to full refresh: \(plan.decisionDescription)")
            return .requiresFullRefresh(plan.decisionDescription)
        }

        do {
            let result = try await hydrationOrchestrator.performPostStreamDelta(
                controller: self,
                request: makeHydrationRequest(trigger: .postStreamDelta)
            )
            await applyHydrationOrchestrationResult(result)
            return result.postStreamResult ?? .requiresFullRefresh("post_stream_result_missing")
        } catch {
            logger.warning("Post-stream delta orchestration failed: \(logString(for: error))")
            return .requiresFullRefresh("orchestration_failed")
        }
    }

    func fetchLiveMRUEntries(
        tokens: StreamTokens
    ) async throws -> [LibraryMRUEntry] {
        try await LibraryMRUDeltaFetcher.fetchLiveMRUEntries(
            tokens: tokens,
            mruLimit: Self.hydrationConfig.mruLimit,
            resolveHost: { [weak self] gsToken, preferredHost in
                guard let self else { throw CancellationError() }
                return try await self.resolveLibraryHost(
                    tokens: tokens,
                    gsToken: gsToken,
                    preferredHost: preferredHost
                )
            },
            logInfo: { [logger] message in
                logger.info("\(message)")
            },
            logWarning: { [logger] message in
                logger.warning("\(message)")
            },
            formatError: { [weak self] error in
                self?.logString(for: error) ?? String(describing: error)
            }
        )
    }

    func resolveLibraryHost(
        tokens: StreamTokens,
        gsToken: String,
        preferredHost: String? = nil
    ) async throws -> String {
        try await LibraryHostResolver.resolve(
            tokens: tokens,
            gsToken: gsToken,
            preferredHost: preferredHost,
            logInfo: { [logger] message in
                logger.info("\(message)")
            },
            logWarning: { [logger] message in
                logger.warning("\(message)")
            },
            formatError: { [weak self] error in
                self?.logString(for: error) ?? String(describing: error)
            },
            isHTTPResponseError: { [weak self] error in
                self?.isHTTPResponseError(error) ?? false
            }
        )
    }

    func refreshHomeMerchandisingSnapshot(
        latestSections: [CloudLibrarySection],
        market: String,
        language: String,
        forceDiscoveryRefresh: Bool = false
    ) async {
        await homeMerchandisingCoordinator.refreshSnapshot(
            latestSections: latestSections,
            market: market,
            language: language,
            forceDiscoveryRefresh: forceDiscoveryRefresh,
            dependencies: homeMerchandisingDependencies()
        )
    }
}
