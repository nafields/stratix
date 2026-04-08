// CloudLibraryViewModelLibraryProjection.swift
// Defines cloud library view model library projection for the CloudLibrary / Root surface.
//

import StratixCore
import StratixModels

@MainActor
extension CloudLibraryViewModel {
    func libraryQueryStateToken(_ queryState: LibraryQueryState) -> Int {
        var hasher = Hasher()
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

    func rebuildLibraryProjection(
        using sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot?,
        queryState: LibraryQueryState,
        showsContinueBadge: Bool,
        force: Bool = false
    ) {
        var hasher = Hasher()
        hasher.combine(sections.count)
        hasher.combine(sections.reduce(0) { $0 + $1.items.count })
        hasher.combine(merchandising?.rows.count ?? 0)
        hasher.combine(merchandising?.recentlyAddedItems.count ?? 0)
        hasher.combine(libraryQueryStateToken(queryState))
        hasher.combine(showsContinueBadge)
        let projectionToken = hasher.finalize()
        guard force || projectionToken != lastLibraryProjectionToken else { return }
        lastLibraryProjectionToken = projectionToken

        let newLibraryState = CloudLibraryDataSource.libraryState(
            sections: sections,
            merchandising: merchandising,
            queryState: queryState,
            showsContinueBadge: showsContinueBadge
        )
        if newLibraryState != cachedLibraryState {
            cachedLibraryState = newLibraryState
        }

        let newLibraryTileLookup = Dictionary(
            newLibraryState.gridItems.map { ($0.titleID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        if newLibraryTileLookup != cachedLibraryTileLookup {
            cachedLibraryTileLookup = newLibraryTileLookup
        }
    }

    func rebuildLibraryProjection(
        using index: CloudLibraryDataSource.PreparedLibraryIndex,
        catalogRevision: UInt64,
        homeRevision: UInt64,
        sceneContentRevision: UInt64,
        queryState: LibraryQueryState,
        showsContinueBadge: Bool
    ) {
        var hasher = Hasher()
        hasher.combine(sceneContentRevision)
        hasher.combine(catalogRevision)
        hasher.combine(homeRevision)
        hasher.combine(libraryQueryStateToken(queryState))
        hasher.combine(showsContinueBadge)
        let projectionToken = hasher.finalize()
        guard projectionToken != lastLibraryProjectionToken else { return }
        lastLibraryProjectionToken = projectionToken

        let newLibraryState = CloudLibraryDataSource.libraryState(
            index: index,
            queryState: queryState,
            showsContinueBadge: showsContinueBadge
        )
        if newLibraryState != cachedLibraryState {
            cachedLibraryState = newLibraryState
        }

        let newLibraryTileLookup = Dictionary(
            newLibraryState.gridItems.map { ($0.titleID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        if newLibraryTileLookup != cachedLibraryTileLookup {
            cachedLibraryTileLookup = newLibraryTileLookup
        }
    }
}
