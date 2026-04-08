// LibraryHydrationPublishedState.swift
// Defines the library hydration published state.
//

import Foundation
import StratixModels
import XCloudAPI

struct LibraryHydrationPublishedState: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        case cacheRestore
        case liveRecovery
    }

    let sections: [CloudLibrarySection]
    let homeMerchandising: HomeMerchandisingSnapshot?
    let discovery: HomeMerchandisingDiscoveryCachePayload?
    let isUnifiedHomeReady: Bool
    let sessionSource: HomeMerchandisingSessionSource
    let savedAt: Date
    let source: Source

    static func cacheRestore(
        snapshot: DecodedLibrarySectionsCacheSnapshot
    ) -> LibraryHydrationPublishedState {
        LibraryHydrationPublishedState(
            sections: snapshot.sections,
            homeMerchandising: snapshot.homeMerchandising,
            discovery: snapshot.discovery,
            isUnifiedHomeReady: snapshot.isUnifiedHomeReady,
            sessionSource: .cacheRestore,
            savedAt: snapshot.savedAt,
            source: .cacheRestore
        )
    }

    static func liveRecovery(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot,
        discovery: HomeMerchandisingDiscoveryCachePayload,
        savedAt: Date
    ) -> LibraryHydrationPublishedState {
        LibraryHydrationPublishedState(
            sections: sections,
            homeMerchandising: homeMerchandising,
            discovery: discovery,
            isUnifiedHomeReady: true,
            sessionSource: .liveRecovery,
            savedAt: savedAt,
            source: .liveRecovery
        )
    }
}

struct LibraryHydrationProductDetailsState: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        case cacheRestore
        case liveRecovery
    }

    let details: [ProductID: CloudLibraryProductDetail]
    let source: Source
    let shouldPersist: Bool
    let restoredCount: Int

    static func cacheRestore(
        details: [ProductID: CloudLibraryProductDetail],
        existing: [ProductID: CloudLibraryProductDetail]
    ) -> LibraryHydrationProductDetailsState {
        var merged = normalized(existing)
        merged.reserveCapacity(max(existing.count, details.count))
        for (key, detail) in normalized(details) {
            if let current = merged[key],
               LibraryController.detailMediaRichness(current) >= LibraryController.detailMediaRichness(detail) {
                continue
            }
            merged[key] = detail
        }
        return LibraryHydrationProductDetailsState(
            details: merged,
            source: .cacheRestore,
            shouldPersist: false,
            restoredCount: details.count
        )
    }

    static func liveRecovery(
        details: [ProductID: CloudLibraryProductDetail]
    ) -> LibraryHydrationProductDetailsState {
        let normalizedDetails = normalized(details)
        return LibraryHydrationProductDetailsState(
            details: normalizedDetails,
            source: .liveRecovery,
            shouldPersist: true,
            restoredCount: normalizedDetails.count
        )
    }

    private static func normalized(
        _ details: [ProductID: CloudLibraryProductDetail]
    ) -> [ProductID: CloudLibraryProductDetail] {
        var normalized: [ProductID: CloudLibraryProductDetail] = [:]
        normalized.reserveCapacity(details.count)
        for (key, detail) in details {
            guard !key.rawValue.isEmpty else { continue }
            if let existing = normalized[key],
               LibraryController.detailMediaRichness(existing) >= LibraryController.detailMediaRichness(detail) {
                continue
            }
            normalized[key] = detail
        }
        return normalized
    }
}

struct LibraryHydrationRecoveryState: Sendable, Equatable {
    let publishedState: LibraryHydrationPublishedState
    let productDetailsState: LibraryHydrationProductDetailsState?
    let shouldPersistUnifiedSnapshot: Bool

    static func liveRecovery(
        sections: [CloudLibrarySection],
        productDetails: [ProductID: CloudLibraryProductDetail],
        homeMerchandising: HomeMerchandisingSnapshot,
        discovery: HomeMerchandisingDiscoveryCachePayload,
        savedAt: Date
    ) -> LibraryHydrationRecoveryState {
        LibraryHydrationRecoveryState(
            publishedState: .liveRecovery(
                sections: sections,
                homeMerchandising: homeMerchandising,
                discovery: discovery,
                savedAt: savedAt
            ),
            productDetailsState: .liveRecovery(details: productDetails),
            shouldPersistUnifiedSnapshot: true
        )
    }

    static func postStreamDelta(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot,
        discovery: HomeMerchandisingDiscoveryCachePayload,
        savedAt: Date
    ) -> LibraryHydrationRecoveryState {
        LibraryHydrationRecoveryState(
            publishedState: .liveRecovery(
                sections: sections,
                homeMerchandising: homeMerchandising,
                discovery: discovery,
                savedAt: savedAt
            ),
            productDetailsState: nil,
            shouldPersistUnifiedSnapshot: true
        )
    }
}

struct LibraryHydrationLiveFetchApplyState: Sendable, Equatable {
    let recoveryState: LibraryHydrationRecoveryState
    let seededProductDetailCount: Int

    static func liveFetch(
        sections: [CloudLibrarySection],
        hydratedCatalogProducts: [GamePassCatalogClient.CatalogProduct],
        titleByProductId: [ProductID: TitleEntry],
        existingProductDetails: [ProductID: CloudLibraryProductDetail],
        homeMerchandising: HomeMerchandisingSnapshot,
        discovery: HomeMerchandisingDiscoveryCachePayload,
        savedAt: Date,
        productDetailsCacheSizeLimit: Int
    ) -> LibraryHydrationLiveFetchApplyState {
        let productDetailsState = CatalogProductDetailHydrator.seededProductDetails(
            products: hydratedCatalogProducts,
            titleByProductId: titleByProductId,
            existingProductDetails: existingProductDetails,
            cacheSizeLimit: productDetailsCacheSizeLimit
        )

        return LibraryHydrationLiveFetchApplyState(
            recoveryState: .liveRecovery(
                sections: sections,
                productDetails: productDetailsState.details,
                homeMerchandising: homeMerchandising,
                discovery: discovery,
                savedAt: savedAt
            ),
            seededProductDetailCount: productDetailsState.upsertedCount
        )
    }
}

struct CatalogProductDetailsSeedState: Sendable, Equatable {
    let details: [ProductID: CloudLibraryProductDetail]
    let upsertedCount: Int
}
