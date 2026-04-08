// LibraryHydrationLiveCommitWorkflowStageTests.swift
// Exercises library hydration live commit workflow stage behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

@MainActor
@Suite(.serialized)
struct LibraryHydrationLiveCommitWorkflowStageTests {
    @Test
    func commit_buildsPublicationPlan_forLiveRecoveryWithDetails() async {
        let result = await LibraryHydrationLiveCommitWorkflow().commit(
            context: .init(
                trigger: .liveRefresh,
                market: "US",
                language: "en-US",
                shouldPersist: true,
                shouldPrefetchArtwork: false,
                shouldAdvanceHomeReadiness: true,
                shouldWarmProfileAndSocial: false
            ),
            fetchResult: makeFetchResult(includeDetails: true),
            controller: LibraryController()
        )

        #expect(result.publicationPlan.stages.contains(.authShell))
        #expect(result.publicationPlan.stages.contains(.routeRestore))
        #expect(result.publicationPlan.stages.contains(.mruAndHero))
        #expect(result.publicationPlan.stages.contains(.visibleRows))
        #expect(result.publicationPlan.stages.contains(.detailsAndSecondaryRows))
        #expect(result.publicationPlan.stages.contains(.backgroundArtwork))
    }

    @Test
    func commit_omitsDetailsStage_whenNoDetailSeedExists() async {
        let result = await LibraryHydrationLiveCommitWorkflow().commit(
            context: .init(
                trigger: .postStreamDelta,
                market: "US",
                language: "en-US",
                shouldPersist: true,
                shouldPrefetchArtwork: false,
                shouldAdvanceHomeReadiness: false,
                shouldWarmProfileAndSocial: false
            ),
            fetchResult: makeFetchResult(includeDetails: false),
            controller: LibraryController()
        )

        #expect(result.publicationPlan.stages.contains(.detailsAndSecondaryRows) == false)
    }

    @Test
    func commit_includesSocialAndProfileStage_whenWarmupRequested() async {
        let result = await LibraryHydrationLiveCommitWorkflow().commit(
            context: .init(
                trigger: .liveRefresh,
                market: "US",
                language: "en-US",
                shouldPersist: true,
                shouldPrefetchArtwork: false,
                shouldAdvanceHomeReadiness: true,
                shouldWarmProfileAndSocial: true
            ),
            fetchResult: makeFetchResult(includeDetails: false),
            controller: LibraryController()
        )

        #expect(result.publicationPlan.stages.contains(.socialAndProfile))
        #expect(result.actions.isEmpty == false)
    }

    private func makeFetchResult(includeDetails: Bool) -> LibraryHydrationLiveFetchResult {
        let savedAt = Date(timeIntervalSince1970: 1_705_050_505)
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: savedAt)
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")

        return LibraryHydrationLiveFetchResult(
            catalogState: LibraryHydrationCatalogState.liveFetch(
                primaryTitlesResponse: TestHydrationFixtures.titlesResponse([]),
                supplementaryResponses: [],
                mruResponse: TestHydrationFixtures.titlesResponse([]),
                existingSections: snapshot.sections
            ),
            committedSections: snapshot.sections,
            seededProductDetails: CatalogProductDetailsSeedState(
                details: includeDetails ? [ProductID("product-1"): detail] : [:],
                upsertedCount: includeDetails ? 1 : 0
            ),
            recoveryState: includeDetails
                ? .liveRecovery(
                    sections: snapshot.sections,
                    productDetails: [ProductID("product-1"): detail],
                    homeMerchandising: snapshot.homeMerchandising!,
                    discovery: snapshot.discovery!,
                    savedAt: savedAt
                )
                : .postStreamDelta(
                    sections: snapshot.sections,
                    homeMerchandising: snapshot.homeMerchandising!,
                    discovery: snapshot.discovery!,
                    savedAt: savedAt
                ),
            merchandisingSnapshot: snapshot.homeMerchandising,
            merchandisingDiscovery: snapshot.discovery,
            hydratedCatalogProducts: [],
            hydratedProductCount: includeDetails ? 1 : 0
        )
    }
}
