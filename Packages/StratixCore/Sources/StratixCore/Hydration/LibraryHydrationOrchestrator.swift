// LibraryHydrationOrchestrator.swift
// Defines library hydration orchestrator for the Hydration surface.
//

import Foundation

@MainActor
protocol LibraryHydrationOrchestrating {
    func performStartupRestore(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult

    func performLiveRefresh(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult

    func performPostStreamDelta(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult
}

@MainActor
struct LibraryHydrationOrchestrator: LibraryHydrationOrchestrating {
    let planner: any LibraryHydrationPlanning
    let worker: any LibraryHydrationWorking
    let persistenceStore: LibraryHydrationPersistenceStore
    let homeMerchandisingSIGLProvider: LibraryController.HomeMerchandisingSIGLProvider
    let startupRestoreWorkflow: any LibraryHydrationStartupRestoring
    let liveRefreshWorkflow: any LibraryHydrationLiveRefreshing
    let liveCommitWorkflow: any LibraryHydrationLiveCommitting
    let postStreamDeltaWorkflow: any LibraryHydrationPostStreamDeltaRunning

    init(
        planner: any LibraryHydrationPlanning,
        worker: any LibraryHydrationWorking,
        persistenceStore: LibraryHydrationPersistenceStore,
        homeMerchandisingSIGLProvider: LibraryController.HomeMerchandisingSIGLProvider,
        startupRestoreWorkflow: any LibraryHydrationStartupRestoring = LibraryHydrationStartupRestoreWorkflow(),
        liveRefreshWorkflow: any LibraryHydrationLiveRefreshing = LibraryHydrationLiveRefreshWorkflow(),
        liveCommitWorkflow: any LibraryHydrationLiveCommitting = LibraryHydrationLiveCommitWorkflow(),
        postStreamDeltaWorkflow: any LibraryHydrationPostStreamDeltaRunning = LibraryHydrationPostStreamDeltaWorkflow()
    ) {
        self.planner = planner
        self.worker = worker
        self.persistenceStore = persistenceStore
        self.homeMerchandisingSIGLProvider = homeMerchandisingSIGLProvider
        self.startupRestoreWorkflow = startupRestoreWorkflow
        self.liveRefreshWorkflow = liveRefreshWorkflow
        self.liveCommitWorkflow = liveCommitWorkflow
        self.postStreamDeltaWorkflow = postStreamDeltaWorkflow
    }

    func performStartupRestore(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult {
        let shouldLoadProductDetailsCache = !controller.hasLoadedProductDetailsCache
        let shouldLoadSectionsCache = !controller.hasLoadedSectionsCache && controller.sections.isEmpty
        guard shouldLoadProductDetailsCache || shouldLoadSectionsCache else {
            return LibraryHydrationOrchestrationResult(
                actions: [],
                persistenceIntent: .none,
                cachedDiscovery: nil,
                source: .startupRestore,
                publicationPlan: LibraryHydrationPublicationPlan(stages: [.routeRestore]),
                postStreamResult: nil
            )
        }

        let restoreResult = await startupRestoreWorkflow.run(
            request: request,
            planner: planner,
            worker: worker,
            shouldLoadProductDetails: shouldLoadProductDetailsCache,
            shouldLoadSections: shouldLoadSectionsCache,
            expectedCacheVersion: LibraryHydrationCacheSchema.currentCacheVersion
        )

        var actions: [LibraryAction] = []
        switch restoreResult.productDetails {
        case .apply(let details):
            actions.append(
                .hydrationProductDetailsStateApplied(
                    .cacheRestore(details: details, existing: controller.productDetails)
                )
            )
        default:
            break
        }

        var cachedDiscovery: HomeMerchandisingDiscoveryCachePayload?
        switch restoreResult.sections {
        case .apply(let snapshot):
            let publishedState = LibraryHydrationPublishedState.cacheRestore(snapshot: snapshot)
            actions.append(.hydrationPublishedStateApplied(publishedState))
            cachedDiscovery = publishedState.discovery
        default:
            break
        }

        return LibraryHydrationOrchestrationResult(
            actions: actions,
            persistenceIntent: .none,
            cachedDiscovery: cachedDiscovery,
            source: .startupRestore,
            publicationPlan: LibraryHydrationPublicationPlan(stages: [.routeRestore]),
            postStreamResult: nil
        )
    }

    func performLiveRefresh(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult {
        let fetchResult = try await liveRefreshWorkflow.run(
            request: request,
            controller: controller
        )
        let commitResult = await liveCommitWorkflow.commit(
            context: LibraryHydrationCommitContext(
                trigger: request.trigger,
                market: request.market,
                language: request.language,
                shouldPersist: request.allowPersistenceWrite,
                shouldPrefetchArtwork: true,
                shouldAdvanceHomeReadiness: true,
                shouldWarmProfileAndSocial: true
            ),
            fetchResult: fetchResult,
            controller: controller
        )
        return LibraryHydrationOrchestrationResult(
            actions: commitResult.actions,
            persistenceIntent: commitResult.persistenceIntent,
            cachedDiscovery: commitResult.cachedDiscovery,
            source: request.trigger,
            publicationPlan: commitResult.publicationPlan,
            postStreamResult: commitResult.postStreamResult
        )
    }

    func performPostStreamDelta(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult {
        try await postStreamDeltaWorkflow.run(
            request: request,
            dependencies: .init(
                fetchLiveMRUEntries: {
                    try await controller.fetchLiveMRUEntriesForHydration()
                },
                applySectionsDelta: { liveMRUEntries in
                    LibraryController.sectionsApplyingMRUDelta(
                        to: controller.sections,
                        liveMRUEntries: liveMRUEntries
                    )
                },
                refreshMerchandising: { sections, market, language in
                    await controller.refreshHomeMerchandisingForHydration(
                        latestSections: sections,
                        market: market,
                        language: language,
                        forceDiscoveryRefresh: false
                    )
                },
                now: Date.init,
                logInfo: { [weak controller] message in
                    controller?.hydrationInfo(message)
                },
                logWarning: { [weak controller] message in
                    controller?.hydrationWarning(message)
                },
                logDebug: { [weak controller] message in
                    controller?.hydrationDebug(message)
                },
                describeSections: { [weak controller] sections in
                    controller?.describeHydrationSections(sections) ?? ""
                },
                describeHomeMerchandising: { [weak controller] snapshot in
                    controller?.describeHydrationHomeMerchandising(snapshot) ?? ""
                },
                describeDiscovery: { [weak controller] discovery in
                    controller?.describeHydrationDiscovery(discovery) ?? ""
                },
                formattedAge: { [weak controller] savedAt in
                    controller?.hydrationFormattedAge(savedAt) ?? "unknown"
                }
            )
        )
    }
}
