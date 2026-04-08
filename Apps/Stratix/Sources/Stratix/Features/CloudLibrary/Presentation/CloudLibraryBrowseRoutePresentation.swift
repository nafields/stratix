// CloudLibraryBrowseRoutePresentation.swift
// Defines cloud library browse route presentation for the Features / CloudLibrary surface.
//

import Foundation
import StratixModels

struct CloudLibraryBrowseRoutePresentation: Hashable {
    let browseRoute: CloudLibraryBrowseRoute
    let loadState: CloudLibraryLoadState
    let homeState: CloudLibraryHomeViewState
    let homeTileLookup: [TitleID: CloudLibraryHomeScreen.TileLookupEntry]
    let libraryState: CloudLibraryLibraryViewState
    let libraryTileLookup: [TitleID: MediaTileViewState]
    let totalLibraryCount: Int
    let searchBrowseItems: [MediaTileViewState]
    let searchResultItems: [MediaTileViewState]
    let searchTileLookup: [TitleID: MediaTileViewState]
    let preferredHomeTileID: TitleID?
    let preferredLibraryTileID: TitleID?
    let preferredSearchTileID: TitleID?

    init(
        browseRoute: CloudLibraryBrowseRoute,
        loadState: CloudLibraryLoadState,
        homeState: CloudLibraryHomeViewState,
        homeTileLookup: [TitleID: CloudLibraryHomeScreen.TileLookupEntry],
        libraryState: CloudLibraryLibraryViewState,
        libraryTileLookup: [TitleID: MediaTileViewState],
        totalLibraryCount: Int,
        searchBrowseItems: [MediaTileViewState],
        searchResultItems: [MediaTileViewState],
        searchTileLookup: [TitleID: MediaTileViewState],
        preferredHomeTileID: TitleID?,
        preferredLibraryTileID: TitleID?,
        preferredSearchTileID: TitleID?
    ) {
        self.browseRoute = browseRoute
        self.loadState = loadState
        self.homeState = homeState
        self.homeTileLookup = homeTileLookup
        self.libraryState = libraryState
        self.libraryTileLookup = libraryTileLookup
        self.totalLibraryCount = totalLibraryCount
        self.searchBrowseItems = searchBrowseItems
        self.searchResultItems = searchResultItems
        self.searchTileLookup = searchTileLookup
        self.preferredHomeTileID = preferredHomeTileID
        self.preferredLibraryTileID = preferredLibraryTileID
        self.preferredSearchTileID = preferredSearchTileID
    }

    static let empty = CloudLibraryBrowseRoutePresentation(
        browseRoute: .home,
        loadState: .notLoaded,
        homeState: CloudLibraryHomeViewState(
            heroBackgroundURL: nil,
            carouselItems: [],
            sections: []
        ),
        homeTileLookup: [:],
        libraryState: CloudLibraryLibraryViewState(
            heroBackdropURL: nil,
            tabs: [],
            selectedTabID: "",
            filters: [],
            sortLabel: "",
            displayMode: .grid,
            gridItems: []
        ),
        libraryTileLookup: [:],
        totalLibraryCount: 0,
        searchBrowseItems: [],
        searchResultItems: [],
        searchTileLookup: [:],
        preferredHomeTileID: nil,
        preferredLibraryTileID: nil,
        preferredSearchTileID: nil
    )
}

@MainActor
struct CloudLibraryBrowseRoutePresentationBuilder {
    func makeBrowseRoutePresentation(
        loadState: CloudLibraryLoadState,
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        homeState: CloudLibraryHomeViewState,
        libraryState: CloudLibraryLibraryViewState,
        totalLibraryCount: Int,
        searchBrowseItems: [MediaTileViewState],
        searchResultItems: [MediaTileViewState]
    ) -> CloudLibraryBrowseRoutePresentation {
        CloudLibraryBrowseRoutePresentation(
            browseRoute: routeState.browseRoute,
            loadState: loadState,
            homeState: homeState,
            homeTileLookup: Dictionary(
                homeState.sections.flatMap { section in
                    section.items.compactMap { item -> (TitleID, CloudLibraryHomeScreen.TileLookupEntry)? in
                        guard case .title(let titleItem) = item else { return nil }
                        return (
                            titleItem.tile.titleID,
                            CloudLibraryHomeScreen.TileLookupEntry(
                                sectionID: section.id,
                                tile: titleItem.tile,
                                titleID: titleItem.tile.titleID
                            )
                        )
                    }
                },
                uniquingKeysWith: { current, _ in current }
            ),
            libraryState: libraryState,
            libraryTileLookup: Dictionary(
                libraryState.gridItems.map { ($0.titleID, $0) },
                uniquingKeysWith: { current, _ in current }
            ),
            totalLibraryCount: totalLibraryCount,
            searchBrowseItems: searchBrowseItems,
            searchResultItems: searchResultItems,
            searchTileLookup: Dictionary(
                (searchBrowseItems + searchResultItems).map { ($0.titleID, $0) },
                uniquingKeysWith: { current, _ in current }
            ),
            preferredHomeTileID: focusState.focusedTileID(for: .home),
            preferredLibraryTileID: focusState.focusedTileID(for: .library),
            preferredSearchTileID: focusState.focusedTileID(for: .search)
        )
    }
}
