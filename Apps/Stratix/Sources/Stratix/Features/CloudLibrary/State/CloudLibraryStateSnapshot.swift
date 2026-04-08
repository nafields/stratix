// CloudLibraryStateSnapshot.swift
// Defines cloud library state snapshot for the Features / CloudLibrary surface.
//

import Foundation
import StratixCore
import StratixModels
import XCloudAPI

struct CloudLibraryStateSnapshot: Equatable, Sendable {
    let state: LibraryState

    var sections: [CloudLibrarySection] { state.sections }
    var itemsByTitleID: [TitleID: CloudLibraryItem] { state.itemsByTitleID }
    var itemsByProductID: [ProductID: CloudLibraryItem] { state.itemsByProductID }
    var productDetails: [ProductID: CloudLibraryProductDetail] { state.productDetails }

    var homeMerchandising: HomeMerchandisingSnapshot? { state.homeMerchandising }
    var discoveryEntries: [GamePassSiglDiscoveryEntry] { state.discoveryEntries }

    var isLoading: Bool { state.isLoading }
    var lastError: String? { state.lastError }
    var needsReauth: Bool { state.needsReauth }
    var lastHydratedAt: Date? { state.lastHydratedAt }
    var cacheSavedAt: Date? { state.cacheSavedAt }

    var hasCompletedInitialHomeMerchandising: Bool { state.hasCompletedInitialHomeMerchandising }
    var homeMerchandisingSessionSource: HomeMerchandisingSessionSource { state.homeMerchandisingSessionSource }
    var hasRecoveredLiveHomeMerchandisingThisSession: Bool { state.hasRecoveredLiveHomeMerchandisingThisSession }

    var catalogRevision: UInt64 { state.catalogRevision }
    var detailRevision: UInt64 { state.detailRevision }
    var homeRevision: UInt64 { state.homeRevision }
    var sceneContentRevision: UInt64 { state.sceneContentRevision }

    var sectionsAreEmpty: Bool {
        sections.allSatisfy(\.items.isEmpty)
    }

    var hasHomeMerchandisingSnapshot: Bool {
        homeMerchandising != nil
    }

    var hasCachedContent: Bool {
        !sections.isEmpty && !sectionsAreEmpty || hasHomeMerchandisingSnapshot
    }

    func item(titleID: TitleID) -> CloudLibraryItem? {
        itemsByTitleID[titleID]
    }

    func item(productID: ProductID) -> CloudLibraryItem? {
        itemsByProductID[productID]
    }

    func productDetail(productID: ProductID) -> CloudLibraryProductDetail? {
        productDetails[productID]
    }
}
