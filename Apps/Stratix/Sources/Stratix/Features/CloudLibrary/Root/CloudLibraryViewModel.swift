// CloudLibraryViewModel.swift
// Defines the cloud library view model.
//

import SwiftUI
import Observation
import DiagnosticsKit
import StratixCore
import StratixModels

// MARK: - ViewModel

/// Owns the projection cache, detail-state hot cache, and prefetch-tracking
/// sets that previously lived as @State in CloudLibraryView. CloudLibraryView
/// reads from this object and calls its mutating methods; it retains
/// responsibility for @FocusState bindings and typed environment wiring.
@Observable
@MainActor
final class CloudLibraryViewModel {
    let logger = GLogger(category: .ui)

    // MARK: - Cached projections (views read these directly)

    var cachedHomeState = CloudLibraryHomeViewState(
        heroBackgroundURL: nil,
        carouselItems: [],
        sections: []
    )
    var cachedLibraryState = CloudLibraryLibraryViewState(
        heroBackdropURL: nil,
        tabs: [
            .init(id: "my-games", title: "My games"),
            .init(id: "full-library", title: "Full library")
        ],
        selectedTabID: "full-library",
        filters: [],
        sortLabel: "Sort A-Z",
        displayMode: .grid,
        gridItems: []
    )
    var cachedSearchBrowseItems: [MediaTileViewState] = []
    var cachedSearchResultItems: [MediaTileViewState] = []
    var cachedSearchHeroURL: URL?
    var cachedHeroBackgroundContext = CloudLibraryHeroBackgroundContext.empty

    // MARK: - Lookup tables (views read these directly)

    var cachedItemsByTitleID: [TitleID: CloudLibraryItem] = [:]
    var cachedItemsByProductID: [ProductID: CloudLibraryItem] = [:]
    var cachedHomeTileLookup: [TitleID: CloudLibraryHomeScreen.TileLookupEntry] = [:]
    var cachedLibraryTileLookup: [TitleID: MediaTileViewState] = [:]
    var cachedSearchTileLookup: [TitleID: MediaTileViewState] = [:]

    // MARK: - Detail-state hot cache (LRU)

    var detailStateCache = DetailStateHotCache(capacity: StratixConstants.Cache.detailHotCacheCapacity)

    // MARK: - Load tracking

    var cachedLibraryCount: Int = 0
    var detailHydrationInFlightTitleIDs: Set<TitleID> = []

    // MARK: - Projection change-detection tokens (no need to publish)

    var preparedIndex: CloudLibraryDataSource.PreparedLibraryIndex?
    var preparedIndexToken: (
        catalogRevision: UInt64,
        homeRevision: UInt64,
        sceneContentRevision: UInt64
    )?
    var lastHomeProjectionToken: Int?
    var lastLibraryProjectionToken: Int?
    var lastSearchProjectionToken: Int?

    // MARK: - Index Maintenance

    /// Reuses the prepared index until one of the library, home, or scene revisions changes.
    func preparedIndexIfNeeded(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot?,
        catalogRevision: UInt64,
        homeRevision: UInt64,
        sceneContentRevision: UInt64
    ) -> CloudLibraryDataSource.PreparedLibraryIndex {
        let token: (
            catalogRevision: UInt64,
            homeRevision: UInt64,
            sceneContentRevision: UInt64
        ) = (catalogRevision, homeRevision, sceneContentRevision)
        if let preparedIndex,
           let preparedIndexToken,
           preparedIndexToken.catalogRevision == token.catalogRevision,
           preparedIndexToken.homeRevision == token.homeRevision,
           preparedIndexToken.sceneContentRevision == token.sceneContentRevision {
            return preparedIndex
        }

        let nextIndex = CloudLibraryDataSource.prepareIndex(
            sections: sections,
            merchandising: merchandising
        )
        preparedIndex = nextIndex
        preparedIndexToken = token
        return nextIndex
    }

    // MARK: - Item Lookup

    /// Chooses the best available hero-style artwork URL for the currently focused title.
    func heroCandidateURL(for titleID: TitleID?) -> URL? {
        guard let titleID,
              let item = cachedItemsByTitleID[titleID] else {
            return nil
        }
        return item.heroImageURL ?? item.artURL ?? item.posterImageURL
    }

    /// Rebuilds item lookups directly from live sections when a prepared index is not available.
    func rebuildItemLookup(using sections: [CloudLibrarySection]) {
        let newItemsByTitleID = Dictionary(
            CloudLibraryDataSource.allLibraryItems(from: sections).map { ($0.typedTitleID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        if newItemsByTitleID != cachedItemsByTitleID {
            cachedItemsByTitleID = newItemsByTitleID
        }

        let newItemsByProductID = Dictionary(
            uniqueKeysWithValues: CloudLibraryDataSource.allLibraryItems(from: sections).map {
                ($0.typedProductID, $0)
            }
        )
        if newItemsByProductID != cachedItemsByProductID {
            cachedItemsByProductID = newItemsByProductID
        }
    }

    /// Rebuilds item lookups from the prepared index to keep title and product lookups aligned with projection inputs.
    func rebuildItemLookup(using index: CloudLibraryDataSource.PreparedLibraryIndex) {
        if index.itemsByTitleID != cachedItemsByTitleID {
            cachedItemsByTitleID = index.itemsByTitleID
        }

        let newItemsByProductID = Dictionary(
            uniqueKeysWithValues: index.allItems.map { ($0.typedProductID, $0) }
        )
        if newItemsByProductID != cachedItemsByProductID {
            cachedItemsByProductID = newItemsByProductID
        }
    }

    // MARK: - Reset

    /// Clears every cached projection and lookup when the signed-in shell session is torn down.
    func resetForSignOut() {
        cachedHomeState = CloudLibraryHomeViewState(heroBackgroundURL: nil, carouselItems: [], sections: [])
        cachedLibraryState = CloudLibraryLibraryViewState(
            heroBackdropURL: nil,
            tabs: [
                .init(id: "my-games", title: "My games"),
                .init(id: "full-library", title: "Full library")
            ],
            selectedTabID: "full-library",
            filters: [],
            sortLabel: "Sort: A-Z",
            displayMode: .grid,
            gridItems: []
        )
        cachedSearchBrowseItems = []
        cachedSearchResultItems = []
        cachedSearchHeroURL = nil
        cachedItemsByTitleID = [:]
        cachedItemsByProductID = [:]
        cachedHomeTileLookup = [:]
        cachedLibraryTileLookup = [:]
        cachedSearchTileLookup = [:]
        detailStateCache.removeAll()
        cachedLibraryCount = 0
        detailHydrationInFlightTitleIDs = []
        preparedIndex = nil
        preparedIndexToken = nil
        lastHomeProjectionToken = nil
        lastLibraryProjectionToken = nil
        lastSearchProjectionToken = nil
        cachedHeroBackgroundContext = .empty
    }
}
