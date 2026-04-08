// LibraryReducerTests.swift
// Exercises library reducer behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

@Suite(.serialized)
struct LibraryReducerTests {
    @Test
    func reduce_sectionsReplaced_updatesIndexesAndRevisions() {
        let item = TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")
        let section = TestHydrationFixtures.section(items: [item])

        let next = LibraryReducer.reduce(
            state: .empty,
            action: .sectionsReplaced([section])
        )

        #expect(next.sections == [section])
        #expect(next.itemsByTitleID[TitleID("title-1")]?.titleId == "title-1")
        #expect(next.itemsByProductID[ProductID("product-1")]?.productId == "product-1")
        #expect(next.catalogRevision == 1)
        #expect(next.sceneContentRevision == 1)
    }

    @Test
    func reduce_productDetailsReplaced_updatesDetailsAndRevisions() {
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")

        let next = LibraryReducer.reduce(
            state: .empty,
            action: .productDetailsReplaced([ProductID("product-1"): detail])
        )

        #expect(next.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(next.detailRevision == 1)
        #expect(next.sceneContentRevision == 1)
    }

    @Test
    func reduce_hydrationPublishedStateApplied_updatesUnifiedHomeState() {
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: savedAt)

        let next = LibraryReducer.reduce(
            state: .empty,
            action: .hydrationPublishedStateApplied(.cacheRestore(snapshot: snapshot))
        )

        #expect(next.sections.map(\.id) == ["library"])
        #expect(next.itemsByTitleID[TitleID("title-1")]?.titleId == "title-1")
        #expect(next.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(next.discoveryEntries.map(\.alias) == ["recently-added"])
        #expect(next.hasCompletedInitialHomeMerchandising == true)
        #expect(next.homeMerchandisingSessionSource == .cacheRestore)
        #expect(next.lastHydratedAt == savedAt)
        #expect(next.cacheSavedAt == savedAt)
        #expect(next.catalogRevision == 1)
        #expect(next.homeRevision == 1)
        #expect(next.sceneContentRevision == 1)
    }

    @Test
    func reduce_hydrationProductDetailsStateApplied_filtersEmptyTypedKeysAndBumpsRevisions() {
        let next = LibraryReducer.reduce(
            state: .empty,
            action: .hydrationProductDetailsStateApplied(
                .liveRecovery(
                    details: [
                        ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite"),
                        ProductID(""): CloudLibraryProductDetail(productId: "", title: "Invalid")
                    ]
                )
            )
        )

        #expect(next.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(next.productDetails[ProductID("")] == nil)
        #expect(next.productDetails.count == 1)
        #expect(next.detailRevision == 1)
        #expect(next.sceneContentRevision == 1)
    }

    @Test
    func reduce_signedOutReset_returnsEmptyState() {
        let item = TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
        let populated = LibraryState(
            sections: [TestHydrationFixtures.section(items: [item])],
            itemsByTitleID: [TitleID("title-1"): item],
            itemsByProductID: [ProductID("product-1"): item],
            productDetails: [ProductID("product-1"): detail],
            isLoading: true,
            lastError: "boom",
            needsReauth: true,
            lastHydratedAt: .now,
            cacheSavedAt: .now,
            isArtworkPrefetchThrottled: true,
            homeMerchandising: nil,
            discoveryEntries: [],
            isHomeMerchandisingLoading: true,
            hasCompletedInitialHomeMerchandising: true,
            homeMerchandisingSessionSource: .liveRecovery,
            hasRecoveredLiveHomeMerchandisingThisSession: true,
            catalogRevision: 4,
            detailRevision: 5,
            homeRevision: 6,
            sceneContentRevision: 7
        )

        #expect(LibraryReducer.reduce(state: populated, action: .signedOutReset) == .empty)
    }

    @Test
    func reduce_doesNotMutateInputSnapshot() {
        let original = LibraryState.empty

        let next = LibraryReducer.reduce(
            state: original,
            action: .loadingStarted
        )

        #expect(original.isLoading == false)
        #expect(next.isLoading == true)
        #expect(original != next)
    }
}
