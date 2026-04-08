// CloudLibraryViewModelSearchProjection.swift
// Defines cloud library view model search projection for the CloudLibrary / Root surface.
//

import StratixCore
import StratixModels

@MainActor
extension CloudLibraryViewModel {
    func searchQueryStateToken(_ queryState: LibraryQueryState) -> Int {
        var hasher = Hasher()
        hasher.combine(queryState.searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        hasher.combine(queryState.selectedTabID)
        hasher.combine(queryState.sortOption.rawValue)
        hasher.combine(queryState.displayMode.rawValue)
        for filterID in queryState.activeFilterIDs.sorted() {
            hasher.combine(filterID)
        }
        if let scopedCategory = queryState.scopedCategory {
            hasher.combine(scopedCategory.alias)
            hasher.combine(scopedCategory.label)
            for titleID in scopedCategory.allowedTitleIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
                hasher.combine(titleID.rawValue)
            }
        } else {
            hasher.combine("no_scoped_category")
        }
        return hasher.finalize()
    }

    func rebuildSearchProjection(
        using sections: [CloudLibrarySection],
        queryState: LibraryQueryState,
        showsContinueBadge: Bool,
        force: Bool = false
    ) {
        var hasher = Hasher()
        hasher.combine(sections.count)
        hasher.combine(sections.reduce(0) { $0 + $1.items.count })
        hasher.combine(searchQueryStateToken(queryState))
        hasher.combine(showsContinueBadge)
        let projectionToken = hasher.finalize()
        guard force || projectionToken != lastSearchProjectionToken else { return }
        lastSearchProjectionToken = projectionToken

        let allItems = CloudLibraryDataSource.allLibraryItems(from: sections)
        let browseItems = allItems
            .prefix(24)
            .map { CloudLibraryDataSource.tileState(for: $0, aspect: .portrait, showsContinueBadge: showsContinueBadge) }
        if browseItems != cachedSearchBrowseItems {
            cachedSearchBrowseItems = browseItems
        }

        let resultItems = CloudLibraryDataSource.searchResultItems(
            sections: sections,
            queryState: queryState
        )
        .map { CloudLibraryDataSource.tileState(for: $0, aspect: .portrait, showsContinueBadge: showsContinueBadge) }
        if resultItems != cachedSearchResultItems {
            cachedSearchResultItems = resultItems
        }

        let newSearchTileLookup = Dictionary(
            (browseItems + resultItems).map { ($0.titleID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        if newSearchTileLookup != cachedSearchTileLookup {
            cachedSearchTileLookup = newSearchTileLookup
        }

        let featured = CloudLibraryDataSource.featuredItem(from: sections)
        let searchHeroURL = featured?.heroImageURL ?? featured?.artURL
        if searchHeroURL != cachedSearchHeroURL {
            cachedSearchHeroURL = searchHeroURL
        }
    }

    func rebuildSearchProjection(
        using index: CloudLibraryDataSource.PreparedLibraryIndex,
        catalogRevision: UInt64,
        sceneContentRevision: UInt64,
        queryState: LibraryQueryState,
        showsContinueBadge: Bool
    ) {
        var hasher = Hasher()
        hasher.combine(sceneContentRevision)
        hasher.combine(catalogRevision)
        hasher.combine(searchQueryStateToken(queryState))
        hasher.combine(showsContinueBadge)
        let projectionToken = hasher.finalize()
        guard projectionToken != lastSearchProjectionToken else { return }
        lastSearchProjectionToken = projectionToken

        let browseItems = index.allItems
            .prefix(24)
            .map { CloudLibraryDataSource.tileState(for: $0, aspect: .portrait, showsContinueBadge: showsContinueBadge) }
        if browseItems != cachedSearchBrowseItems {
            cachedSearchBrowseItems = browseItems
        }

        let resultItems = CloudLibraryDataSource.searchResultItems(
            index: index,
            queryState: queryState
        )
        .map { CloudLibraryDataSource.tileState(for: $0, aspect: .portrait, showsContinueBadge: showsContinueBadge) }
        if resultItems != cachedSearchResultItems {
            cachedSearchResultItems = resultItems
        }

        let newSearchTileLookup = Dictionary(
            (browseItems + resultItems).map { ($0.titleID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        if newSearchTileLookup != cachedSearchTileLookup {
            cachedSearchTileLookup = newSearchTileLookup
        }

        let searchHeroURL = index.featuredItem?.heroImageURL ?? index.featuredItem?.artURL
        if searchHeroURL != cachedSearchHeroURL {
            cachedSearchHeroURL = searchHeroURL
        }
    }
}
