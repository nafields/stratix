// LibraryControllerStateReducerTests.swift
// Exercises library controller state reducer behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

@MainActor
@Suite(.serialized)
struct LibraryControllerStateReducerTests {
    @Test
    func apply_singleAction_updatesCanonicalState() {
        let controller = LibraryController()
        let section = TestHydrationFixtures.section(
            items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")]
        )

        controller.apply(.sectionsReplaced([section]))

        #expect(controller.state.sections.map(\.id) == ["library"])
        #expect(controller.sections.map(\.id) == ["library"])
        #expect(controller.state.itemsByTitleID[TitleID("title-1")]?.titleId == "title-1")
    }

    @Test
    func apply_multipleActions_appliesInOrder() {
        let controller = LibraryController()

        controller.apply([
            .loadingStarted,
            .errorSet("boom"),
            .loadingFinished
        ])

        #expect(controller.state.isLoading == false)
        #expect(controller.lastError == "boom")
    }

    @Test
    func compatibilityProperties_mirrorCanonicalStateAfterReducerApplication() {
        let controller = LibraryController()
        let item = TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")
        let section = TestHydrationFixtures.section(items: [item])
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
        let hydratedAt = Date(timeIntervalSince1970: 1_705_050_505)

        controller.apply([
            .sectionsReplaced([section]),
            .productDetailsReplaced([ProductID("product-1"): detail]),
            .lastHydratedAtSet(hydratedAt),
            .cacheSavedAtSet(hydratedAt)
        ])

        #expect(controller.state.sections.map(\.id) == ["library"])
        #expect(controller.state.itemsByTitleID[TitleID("title-1")]?.titleId == "title-1")
        #expect(controller.state.itemsByProductID[ProductID("product-1")]?.productId == "product-1")
        #expect(controller.state.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(controller.itemsByTitleID[TitleID("title-1")]?.titleId == "title-1")
        #expect(controller.itemsByProductID[ProductID("product-1")]?.productId == "product-1")
        #expect(controller.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(controller.lastHydratedAt == hydratedAt)
        #expect(controller.cacheSavedAt == hydratedAt)
    }

    @Test
    func applyHydrationOrchestrationResult_appliesActionsAndSchedulesPersistence() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("controller-state-reducer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let controller = LibraryController(
            cacheLocations: .init(
                details: cacheRoot.appendingPathComponent("details.json"),
                sections: cacheRoot.appendingPathComponent("sections.json"),
                homeMerchandising: cacheRoot.appendingPathComponent("home.json")
            )
        )
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date(timeIntervalSince1970: 1_701_010_101))
        let details = [ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")]
        let publishedState = LibraryHydrationPublishedState.cacheRestore(snapshot: snapshot)
        let productDetailsState = LibraryHydrationProductDetailsState.liveRecovery(details: details)

        await controller.applyHydrationOrchestrationResult(
            LibraryHydrationOrchestrationResult(
                actions: [
                    .hydrationProductDetailsStateApplied(productDetailsState),
                    .hydrationPublishedStateApplied(publishedState)
                ],
                persistenceIntent: .unifiedSectionsAndProductDetails(
                    sections: LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
                        sections: snapshot.sections,
                        homeMerchandising: snapshot.homeMerchandising,
                        discovery: snapshot.discovery,
                        savedAt: snapshot.savedAt,
                        isUnifiedHomeReady: snapshot.isUnifiedHomeReady
                    ),
                    details: LibraryHydrationPersistenceStore.makeProductDetailsSnapshot(
                        details: details,
                        savedAt: snapshot.savedAt
                    )
                ),
                cachedDiscovery: snapshot.discovery,
                source: .liveRefresh,
                publicationPlan: LibraryHydrationPublicationPlan(stages: [.routeRestore, .visibleRows]),
                postStreamResult: nil
            )
        )

        await Task.yield()
        await controller.flushSectionsCacheForTesting()
        await controller.flushProductDetailsCacheForTesting()

        #expect(controller.state.sections.map(\.id) == ["library"])
        #expect(controller.state.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(controller.state.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(controller.state.cacheSavedAt == snapshot.savedAt)
    }

    @Test
    func resetForSignOut_resetsRuntimeStateAndCanonicalState() async {
        let controller = LibraryController()
        controller.apply([
            .sectionsReplaced([TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")])]),
            .productDetailsReplaced([ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")]),
            .errorSet("boom"),
            .needsReauthSet(true)
        ])
        controller.hasPerformedNetworkHydrationThisSession = true
        controller.hasLoadedProductDetailsCache = true
        controller.hasLoadedSectionsCache = true
        controller.isArtworkPrefetchDisabledForSession = true
        controller.lastArtworkPrefetchStartedAt = Date()
        controller.artworkPrefetchLastCompletedAtByURL = ["https://example.com/art.jpg": Date()]
        controller.cachedHomeMerchandisingDiscovery = HomeMerchandisingDiscoveryCachePayload(entries: [], savedAt: Date())

        await controller.resetForSignOut()

        #expect(controller.state == .empty)
        #expect(controller.hasPerformedNetworkHydrationThisSession == false)
        #expect(controller.hasLoadedProductDetailsCache == false)
        #expect(controller.hasLoadedSectionsCache == false)
        #expect(controller.isArtworkPrefetchDisabledForSession == false)
        #expect(controller.lastArtworkPrefetchStartedAt == nil)
        #expect(controller.artworkPrefetchLastCompletedAtByURL.isEmpty)
        #expect(controller.cachedHomeMerchandisingDiscovery == nil)
    }
}
