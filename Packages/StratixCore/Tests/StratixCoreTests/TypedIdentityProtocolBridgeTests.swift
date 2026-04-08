// TypedIdentityProtocolBridgeTests.swift
// Exercises typed identity protocol bridge behavior.
//

import Testing
@testable import StratixCore
import StratixModels

@MainActor
@Suite(.serialized)
struct TypedIdentityProtocolBridgeTests {
    @Test
    func libraryProtocolsBridgeTypedTitleAndProductIDs() {
        let item = CloudLibraryItem(
            titleId: "title-1",
            productId: "product-1",
            name: "Halo Infinite",
            shortDescription: nil,
            artURL: nil,
            posterImageURL: nil,
            heroImageURL: nil,
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
        let controller = LibraryController(
            initialState: LibraryState(
                sections: [CloudLibrarySection(id: "library", name: "Library", items: [item])],
                itemsByTitleID: [TitleID("title-1"): item],
                itemsByProductID: [ProductID("product-1"): item],
                productDetails: [ProductID("product-1"): detail],
                isLoading: false,
                lastError: nil,
                needsReauth: false,
                lastHydratedAt: nil,
                cacheSavedAt: nil,
                isArtworkPrefetchThrottled: false,
                homeMerchandising: nil,
                discoveryEntries: [],
                isHomeMerchandisingLoading: false,
                hasCompletedInitialHomeMerchandising: false,
                homeMerchandisingSessionSource: .none,
                hasRecoveredLiveHomeMerchandisingThisSession: false,
                catalogRevision: 1,
                detailRevision: 1,
                homeRevision: 0,
                sceneContentRevision: 1
            )
        )

        let itemReader: any LibraryItemReading = controller
        let detailReader: any LibraryDetailReading = controller

        #expect(itemReader.item(titleID: TitleID("title-1"))?.productId == "product-1")
        #expect(itemReader.item(productID: ProductID("product-1"))?.titleId == "title-1")
        #expect(detailReader.productDetail(productID: ProductID("product-1"))?.title == "Halo Infinite")
    }
}
