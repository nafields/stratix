// LibraryHydrationLiveCommitWorkflowTests.swift
// Exercises library hydration live commit workflow behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing

@MainActor
@Suite(.serialized)
struct LibraryHydrationLiveCommitWorkflowTests {
    @Test
    func commit_buildsPublishedState_andPersistenceIntent() async {
        let savedAt = Date(timeIntervalSince1970: 5_050_505_050)
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: savedAt)
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
        let fetchResult = LibraryHydrationLiveFetchResult(
            catalogState: LibraryHydrationCatalogState.liveFetch(
                primaryTitlesResponse: TestHydrationFixtures.titlesResponse([]),
                supplementaryResponses: [],
                mruResponse: TestHydrationFixtures.titlesResponse([]),
                existingSections: snapshot.sections
            ),
            committedSections: snapshot.sections,
            seededProductDetails: CatalogProductDetailsSeedState(
                details: [ProductID("product-1"): detail],
                upsertedCount: 1
            ),
            recoveryState: .liveRecovery(
                sections: snapshot.sections,
                productDetails: [ProductID("product-1"): detail],
                homeMerchandising: snapshot.homeMerchandising!,
                discovery: snapshot.discovery!,
                savedAt: savedAt
            ),
            merchandisingSnapshot: snapshot.homeMerchandising,
            merchandisingDiscovery: snapshot.discovery,
            hydratedCatalogProducts: [],
            hydratedProductCount: 1
        )

        let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let controller = LibraryController(
            cacheLocations: .init(
                details: cacheRoot.appendingPathComponent("details.json"),
                sections: cacheRoot.appendingPathComponent("sections.json"),
                homeMerchandising: cacheRoot.appendingPathComponent("home.json")
            )
        )

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
            fetchResult: fetchResult,
            controller: controller
        )

        #expect(result.actions.contains(where: {
            if case .hydrationPublishedStateApplied(let state) = $0 {
                return state.sections.first?.id == "library"
            }
            return false
        }))
        #expect(result.actions.contains(where: {
            if case .hydrationProductDetailsStateApplied(let state) = $0 {
                return state.details[ProductID("product-1")]?.title == "Halo Infinite"
            }
            return false
        }))
        switch result.persistenceIntent {
        case .unifiedSectionsAndProductDetails(let sections, let details):
            #expect(sections.isUnifiedHomeReady == true)
            #expect(details.details[ProductID("product-1")]?.title == "Halo Infinite")
        default:
            Issue.record("Expected combined persistence intent for live recovery commit.")
        }
    }

    @Test
    func commit_noopsPersistence_whenRecoveryStateIsMissing() async {
        let controller = LibraryController()
        let fetchResult = LibraryHydrationLiveFetchResult(
            catalogState: LibraryHydrationCatalogState.liveFetch(
                primaryTitlesResponse: TestHydrationFixtures.titlesResponse([]),
                supplementaryResponses: [],
                mruResponse: TestHydrationFixtures.titlesResponse([]),
                existingSections: []
            ),
            committedSections: [],
            seededProductDetails: CatalogProductDetailsSeedState(details: [:], upsertedCount: 0),
            recoveryState: nil,
            merchandisingSnapshot: nil,
            merchandisingDiscovery: HomeMerchandisingDiscoveryCachePayload(
                entries: [TestHydrationFixtures.discoveryEntry(alias: "recently-added", siglID: "sigl-recent")],
                savedAt: Date()
            ),
            hydratedCatalogProducts: [],
            hydratedProductCount: 0
        )

        let result = await LibraryHydrationLiveCommitWorkflow().commit(
            context: .init(
                trigger: .liveRefresh,
                market: "US",
                language: "en-US",
                shouldPersist: true,
                shouldPrefetchArtwork: false,
                shouldAdvanceHomeReadiness: false,
                shouldWarmProfileAndSocial: false
            ),
            fetchResult: fetchResult,
            controller: controller
        )

        #expect(result.actions.isEmpty)
        #expect(result.cachedDiscovery?.entries.map(\.alias) == ["recently-added"])
        if case .none = result.persistenceIntent {
        } else {
            Issue.record("Expected persistence to noop when recovery state is missing.")
        }
    }

    @Test
    func commit_omitsProductDetailsPersistence_whenNoProductDetailChangesExist() async {
        let savedAt = Date(timeIntervalSince1970: 2_020_202_020)
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: savedAt)
        let fetchResult = LibraryHydrationLiveFetchResult(
            catalogState: LibraryHydrationCatalogState.liveFetch(
                primaryTitlesResponse: TestHydrationFixtures.titlesResponse([]),
                supplementaryResponses: [],
                mruResponse: TestHydrationFixtures.titlesResponse([]),
                existingSections: snapshot.sections
            ),
            committedSections: snapshot.sections,
            seededProductDetails: CatalogProductDetailsSeedState(details: [:], upsertedCount: 0),
            recoveryState: .postStreamDelta(
                sections: snapshot.sections,
                homeMerchandising: snapshot.homeMerchandising!,
                discovery: snapshot.discovery!,
                savedAt: savedAt
            ),
            merchandisingSnapshot: snapshot.homeMerchandising,
            merchandisingDiscovery: snapshot.discovery,
            hydratedCatalogProducts: [],
            hydratedProductCount: 0
        )

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
            fetchResult: fetchResult,
            controller: LibraryController()
        )

        switch result.persistenceIntent {
        case .unifiedSections(let sections):
            #expect(sections.isUnifiedHomeReady == true)
        default:
            Issue.record("Expected unified sections persistence without product details.")
        }
    }

    @Test
    func commit_noopsPersistence_whenShouldPersistIsFalse() async {
        let savedAt = Date(timeIntervalSince1970: 7_070_707_070)
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: savedAt)
        let fetchResult = LibraryHydrationLiveFetchResult(
            catalogState: LibraryHydrationCatalogState.liveFetch(
                primaryTitlesResponse: TestHydrationFixtures.titlesResponse([]),
                supplementaryResponses: [],
                mruResponse: TestHydrationFixtures.titlesResponse([]),
                existingSections: snapshot.sections
            ),
            committedSections: snapshot.sections,
            seededProductDetails: CatalogProductDetailsSeedState(details: [:], upsertedCount: 0),
            recoveryState: .postStreamDelta(
                sections: snapshot.sections,
                homeMerchandising: snapshot.homeMerchandising!,
                discovery: snapshot.discovery!,
                savedAt: savedAt
            ),
            merchandisingSnapshot: snapshot.homeMerchandising,
            merchandisingDiscovery: snapshot.discovery,
            hydratedCatalogProducts: [],
            hydratedProductCount: 0
        )

        let result = await LibraryHydrationLiveCommitWorkflow().commit(
            context: .init(
                trigger: .postStreamDelta,
                market: "US",
                language: "en-US",
                shouldPersist: false,
                shouldPrefetchArtwork: false,
                shouldAdvanceHomeReadiness: false,
                shouldWarmProfileAndSocial: false
            ),
            fetchResult: fetchResult,
            controller: LibraryController()
        )

        if case .none = result.persistenceIntent {
        } else {
            Issue.record("Expected persistence intent to be .none when persistence is disabled.")
        }
    }
}
