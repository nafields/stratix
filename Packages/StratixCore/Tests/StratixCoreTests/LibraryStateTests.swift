// LibraryStateTests.swift
// Exercises library state behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

@Suite(.serialized)
struct LibraryStateTests {
    @Test
    func empty_providesExpectedInitialValues() {
        let state = LibraryState.empty

        #expect(state.sections.isEmpty)
        #expect(state.itemsByTitleID.isEmpty)
        #expect(state.itemsByProductID.isEmpty)
        #expect(state.productDetails.isEmpty)
        #expect(state.isLoading == false)
        #expect(state.lastError == nil)
        #expect(state.needsReauth == false)
        #expect(state.lastHydratedAt == nil)
        #expect(state.cacheSavedAt == nil)
        #expect(state.isArtworkPrefetchThrottled == false)
        #expect(state.homeMerchandising == nil)
        #expect(state.discoveryEntries.isEmpty)
        #expect(state.isHomeMerchandisingLoading == false)
        #expect(state.hasCompletedInitialHomeMerchandising == false)
        #expect(state.homeMerchandisingSessionSource == .none)
        #expect(state.hasRecoveredLiveHomeMerchandisingThisSession == false)
        #expect(state.catalogRevision == 0)
        #expect(state.detailRevision == 0)
        #expect(state.homeRevision == 0)
        #expect(state.sceneContentRevision == 0)
    }

    @Test
    func equatable_changesWhenRelevantFieldsChange() {
        let item = TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")
        let section = TestHydrationFixtures.section(items: [item])
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")

        var a = LibraryState.empty
        var b = LibraryState.empty
        #expect(a == b)

        a.sections = [section]
        #expect(a != b)

        b.sections = [section]
        #expect(a == b)

        a.productDetails = [ProductID("product-1"): detail]
        #expect(a != b)

        b.productDetails = [ProductID("product-1"): detail]
        #expect(a == b)

        a.homeRevision = 1
        #expect(a != b)
    }
}
