// LibraryStreamingRuntime.swift
// Defines library streaming runtime.
//

import Foundation
import StratixModels

@MainActor
extension LibraryController {
    func resetForSignOut() async {
        apply(.signedOutReset)
        hasPerformedNetworkHydrationThisSession = false
        hasLoadedProductDetailsCache = false
        hasLoadedSectionsCache = false
        isArtworkPrefetchDisabledForSession = false
        lastArtworkPrefetchStartedAt = nil
        artworkPrefetchLastCompletedAtByURL.removeAll()
        cachedHomeMerchandisingDiscovery = nil
        await taskRegistry.cancelAll()
    }

    func suspendForStreaming() async {
        guard !isSuspendedForStreaming else { return }
        isSuspendedForStreaming = true
        apply([.loadingFinished, .homeMerchandisingLoadingSet(false)])
        await taskRegistry.cancelAll()
    }

    func resumeAfterStreaming() {
        guard isSuspendedForStreaming else { return }
        isSuspendedForStreaming = false
    }

    func testingIsLoadTaskActive() async -> Bool {
        await taskRegistry.task(id: TaskID.cloudLibraryLoad, as: Task<Void, Never>.self) != nil
    }

    func refreshHomeMerchandisingForHydration(
        latestSections: [CloudLibrarySection],
        market: String,
        language: String,
        forceDiscoveryRefresh: Bool
    ) async -> HomeMerchandisingRefreshResult {
        await homeMerchandisingCoordinator.refreshForHydration(
            latestSections: latestSections,
            market: market,
            language: language,
            forceDiscoveryRefresh: forceDiscoveryRefresh,
            dependencies: homeMerchandisingDependencies()
        )
    }

    func homeMerchandisingDependencies() -> LibraryHomeMerchandisingCoordinator.Dependencies {
        .init(
            hydrationPlanner: hydrationPlanner,
            homeMerchandisingSIGLProvider: homeMerchandisingSIGLProvider,
            config: Self.hydrationConfig,
            existingSnapshot: { [weak self] in
                self?.homeMerchandising
            },
            cachedDiscovery: { [weak self] in
                self?.cachedHomeMerchandisingDiscovery
            },
            setCachedDiscovery: { [weak self] discovery in
                self?.cachedHomeMerchandisingDiscovery = discovery
            },
            isSuspendedForStreaming: { [weak self] in
                self?.isSuspendedForStreaming ?? true
            },
            applyActions: { [weak self] actions in
                self?.apply(actions)
            },
            formatError: { [weak self] error in
                self?.logString(for: error) ?? String(describing: error)
            },
            logInfo: { [weak self] message in
                self?.hydrationInfo(message)
            },
            logWarning: { [weak self] message in
                self?.hydrationWarning(message)
            },
            logDebug: { [weak self] message in
                self?.hydrationDebug(message)
            }
        )
    }
}
