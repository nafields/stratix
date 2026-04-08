// LibraryState.swift
// Defines the library state.
//

import Foundation
import StratixModels
import XCloudAPI

public struct LibraryState: Sendable, Equatable {
    public var sections: [CloudLibrarySection]
    public var itemsByTitleID: [TitleID: CloudLibraryItem]
    public var itemsByProductID: [ProductID: CloudLibraryItem]
    public var productDetails: [ProductID: CloudLibraryProductDetail]

    public var isLoading: Bool
    public var lastError: String?
    public var needsReauth: Bool
    public var lastHydratedAt: Date?
    public var cacheSavedAt: Date?
    public var isArtworkPrefetchThrottled: Bool

    public var homeMerchandising: HomeMerchandisingSnapshot?
    public var discoveryEntries: [GamePassSiglDiscoveryEntry]
    public var isHomeMerchandisingLoading: Bool
    public var hasCompletedInitialHomeMerchandising: Bool
    public var homeMerchandisingSessionSource: HomeMerchandisingSessionSource
    public var hasRecoveredLiveHomeMerchandisingThisSession: Bool

    public var catalogRevision: UInt64
    public var detailRevision: UInt64
    public var homeRevision: UInt64
    public var sceneContentRevision: UInt64

    public init(
        sections: [CloudLibrarySection],
        itemsByTitleID: [TitleID: CloudLibraryItem],
        itemsByProductID: [ProductID: CloudLibraryItem],
        productDetails: [ProductID: CloudLibraryProductDetail],
        isLoading: Bool,
        lastError: String?,
        needsReauth: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?,
        isArtworkPrefetchThrottled: Bool,
        homeMerchandising: HomeMerchandisingSnapshot?,
        discoveryEntries: [GamePassSiglDiscoveryEntry],
        isHomeMerchandisingLoading: Bool,
        hasCompletedInitialHomeMerchandising: Bool,
        homeMerchandisingSessionSource: HomeMerchandisingSessionSource,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool,
        catalogRevision: UInt64,
        detailRevision: UInt64,
        homeRevision: UInt64,
        sceneContentRevision: UInt64
    ) {
        self.sections = sections
        self.itemsByTitleID = itemsByTitleID
        self.itemsByProductID = itemsByProductID
        self.productDetails = productDetails
        self.isLoading = isLoading
        self.lastError = lastError
        self.needsReauth = needsReauth
        self.lastHydratedAt = lastHydratedAt
        self.cacheSavedAt = cacheSavedAt
        self.isArtworkPrefetchThrottled = isArtworkPrefetchThrottled
        self.homeMerchandising = homeMerchandising
        self.discoveryEntries = discoveryEntries
        self.isHomeMerchandisingLoading = isHomeMerchandisingLoading
        self.hasCompletedInitialHomeMerchandising = hasCompletedInitialHomeMerchandising
        self.homeMerchandisingSessionSource = homeMerchandisingSessionSource
        self.hasRecoveredLiveHomeMerchandisingThisSession = hasRecoveredLiveHomeMerchandisingThisSession
        self.catalogRevision = catalogRevision
        self.detailRevision = detailRevision
        self.homeRevision = homeRevision
        self.sceneContentRevision = sceneContentRevision
    }
}

extension LibraryState {
    public static let empty = LibraryState(
        sections: [],
        itemsByTitleID: [:],
        itemsByProductID: [:],
        productDetails: [:],
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
        catalogRevision: 0,
        detailRevision: 0,
        homeRevision: 0,
        sceneContentRevision: 0
    )
}
