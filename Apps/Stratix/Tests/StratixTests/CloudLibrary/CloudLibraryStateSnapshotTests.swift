// CloudLibraryStateSnapshotTests.swift
// Exercises cloud library state snapshot behavior.
//

import XCTest
import StratixModels
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryStateSnapshotTests: XCTestCase {
    @MainActor
    func testAdapterExposesLibraryStateFieldsWithoutMutation() {
        let item = CloudLibraryTestSupport.makeItem()
        let detail = CloudLibraryTestSupport.makeDetail(productId: item.productId)
        let titleID = TitleID(rawValue: item.titleId)
        let productID = ProductID(rawValue: item.productId)
        let state = CloudLibraryTestSupport.makeLibraryState(
            sections: [CloudLibrarySection(id: "library", name: "Library", items: [item])],
            productDetails: [productID: detail],
            isLoading: true,
            lastError: "offline_error",
            needsReauth: true,
            lastHydratedAt: Date(timeIntervalSince1970: 10),
            cacheSavedAt: Date(timeIntervalSince1970: 5),
            catalogRevision: 3,
            detailRevision: 2,
            homeRevision: 4,
            sceneContentRevision: 7
        )

        let snapshot = CloudLibraryStateSnapshot(state: state)

        XCTAssertEqual(snapshot.sections, state.sections)
        XCTAssertEqual(snapshot.homeMerchandising, state.homeMerchandising)
        XCTAssertEqual(snapshot.discoveryEntries, state.discoveryEntries)
        XCTAssertEqual(snapshot.isLoading, state.isLoading)
        XCTAssertEqual(snapshot.lastError, state.lastError)
        XCTAssertEqual(snapshot.needsReauth, state.needsReauth)
        XCTAssertEqual(snapshot.catalogRevision, state.catalogRevision)
        XCTAssertEqual(snapshot.detailRevision, state.detailRevision)
        XCTAssertEqual(snapshot.homeRevision, state.homeRevision)
        XCTAssertEqual(snapshot.sceneContentRevision, state.sceneContentRevision)
        XCTAssertEqual(snapshot.itemsByTitleID[titleID]?.name, item.name)
        XCTAssertEqual(snapshot.itemsByProductID[productID]?.name, item.name)
        XCTAssertEqual(snapshot.productDetails[productID]?.productId, detail.productId)
        XCTAssertEqual(snapshot.item(titleID: titleID)?.titleId, item.titleId)
        XCTAssertEqual(snapshot.item(productID: productID)?.productId, item.productId)
        XCTAssertEqual(snapshot.productDetail(productID: productID)?.productId, detail.productId)
    }

    @MainActor
    func testAdapterReportsEmptyStateCorrectly() {
        let snapshot = CloudLibraryStateSnapshot(state: .empty)

        XCTAssertTrue(snapshot.sectionsAreEmpty)
        XCTAssertFalse(snapshot.hasHomeMerchandisingSnapshot)
        XCTAssertFalse(snapshot.hasCachedContent)
    }

    @MainActor
    func testDetailStateHotCacheUsesTypedTitleIDKeys() {
        var cache = DetailStateHotCache(capacity: 2)
        let titleID = TitleID(rawValue: "typed-title")

        cache.insert(
            state: CloudLibraryTitleDetailViewState(
                id: "detail-1",
                title: "Halo Infinite",
                subtitle: nil,
                heroImageURL: nil,
                posterImageURL: nil,
                ratingText: nil,
                legalText: nil,
                descriptionText: nil,
                primaryAction: .init(id: "play", title: "Play", style: .primary),
                secondaryActions: [],
                capabilityChips: [],
                gallery: [],
                achievementSummary: nil,
                achievementItems: [],
                achievementErrorText: nil,
                detailPanels: [],
                contextLabel: nil,
                isHydrating: false
            ),
            for: titleID,
            inputSignature: "sig"
        )

        XCTAssertNotNil(cache.peek(titleID))
        XCTAssertEqual(cache.keys, [titleID])
        XCTAssertEqual(cache.invalidateChangedEntries(currentSignatures: [titleID: "sig"]), [])
    }
}
