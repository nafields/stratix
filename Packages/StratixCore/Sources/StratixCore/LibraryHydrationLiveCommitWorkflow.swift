// LibraryHydrationLiveCommitWorkflow.swift
// Defines library hydration live commit workflow.
//

import Foundation

protocol LibraryHydrationLiveCommitting: Sendable {
    @MainActor
    func commit(
        context: LibraryHydrationCommitContext,
        fetchResult: LibraryHydrationLiveFetchResult,
        controller: LibraryController
    ) async -> LibraryHydrationCommitResult
}

@MainActor
struct LibraryHydrationLiveCommitWorkflow: LibraryHydrationLiveCommitting {
    func commit(
        context: LibraryHydrationCommitContext,
        fetchResult: LibraryHydrationLiveFetchResult,
        controller _: LibraryController
    ) async -> LibraryHydrationCommitResult {
        guard let recoveryState = fetchResult.recoveryState else {
            return LibraryHydrationCommitResult(
                persistenceIntent: .none,
                cachedDiscovery: fetchResult.merchandisingDiscovery,
                actions: [],
                shouldPrefetchArtwork: false,
                shouldWarmProfileAndSocial: false,
                publicationPlan: makePublicationPlan(
                    trigger: context.trigger,
                    hasProductDetails: false,
                    shouldWarmProfileAndSocial: false
                ),
                postStreamResult: nil
            )
        }

        let publishedState = recoveryState.publishedState
        let productDetailsState = recoveryState.productDetailsState
        let publicationPlan = makePublicationPlan(
            trigger: context.trigger,
            hasProductDetails: productDetailsState != nil && fetchResult.seededProductDetails.upsertedCount > 0,
            shouldWarmProfileAndSocial: context.shouldWarmProfileAndSocial
        )
        var actions: [LibraryAction] = []

        if let productDetailsState {
            actions.append(.hydrationProductDetailsStateApplied(productDetailsState))
        }
        actions.append(.hydrationPublishedStateApplied(publishedState))

        let persistenceIntent = makePersistenceIntent(
            context: context,
            publishedState: publishedState,
            productDetailsState: productDetailsState,
            publicationPlan: publicationPlan
        )

        return LibraryHydrationCommitResult(
            persistenceIntent: persistenceIntent,
            cachedDiscovery: fetchResult.merchandisingDiscovery,
            actions: actions,
            shouldPrefetchArtwork: context.shouldPrefetchArtwork,
            shouldWarmProfileAndSocial: context.shouldWarmProfileAndSocial,
            publicationPlan: publicationPlan,
            postStreamResult: nil
        )
    }

    private func makePersistenceIntent(
        context: LibraryHydrationCommitContext,
        publishedState: LibraryHydrationPublishedState,
        productDetailsState: LibraryHydrationProductDetailsState?,
        publicationPlan: LibraryHydrationPublicationPlan
    ) -> LibraryHydrationPersistenceIntent {
        guard context.shouldPersist else { return .none }

        let sectionsSnapshot = LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: publishedState.sections,
            homeMerchandising: publishedState.homeMerchandising,
            discovery: publishedState.discovery,
            savedAt: publishedState.savedAt,
            isUnifiedHomeReady: publishedState.isUnifiedHomeReady,
            refreshSource: String(describing: context.trigger),
            trigger: String(describing: context.trigger),
            publicationPlan: publicationPlan
        )

        guard let productDetailsState, productDetailsState.shouldPersist else {
            return .unifiedSections(sectionsSnapshot)
        }

        let detailsSnapshot = LibraryHydrationPersistenceStore.makeProductDetailsSnapshot(
            details: productDetailsState.details,
            savedAt: publishedState.savedAt,
            refreshSource: String(describing: context.trigger),
            trigger: "product_details_refresh"
        )
        return .unifiedSectionsAndProductDetails(
            sections: sectionsSnapshot,
            details: detailsSnapshot
        )
    }

    private func makePublicationPlan(
        trigger: LibraryHydrationTrigger,
        hasProductDetails: Bool,
        shouldWarmProfileAndSocial: Bool
    ) -> LibraryHydrationPublicationPlan {
        _ = trigger
        var stages: [LibraryHydrationStage] = [
            .authShell,
            .routeRestore,
            .mruAndHero,
            .visibleRows
        ]

        if hasProductDetails {
            stages.append(.detailsAndSecondaryRows)
        }

        if shouldWarmProfileAndSocial {
            stages.append(.socialAndProfile)
        }

        stages.append(.backgroundArtwork)
        return LibraryHydrationPublicationPlan(stages: stages)
    }
}
