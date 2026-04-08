// CloudLibraryShellHostActionTests.swift
// Exercises cloud library shell host action behavior.
//

import SwiftUI
import Testing
import StratixModels

#if canImport(Stratix)
@testable import Stratix
#endif

struct CloudLibraryShellHostActionTests {
    @Test
    @MainActor
    func browseActions_routeTypedIDsThroughClosures() {
        let focusState = CloudLibraryFocusState()
        var queryState = LibraryQueryState()
        var openedTitleID: TitleID?
        var launchedStream: (TitleID, String)?
        var enteredLibraryRoute = false

        let actions = CloudLibraryBrowseRouteActions(
            refreshCloudLibrary: {},
            signOut: {},
            requestSideRailEntry: { focusState.requestSideRailEntry() },
            homeSelectRailItem: { item in
                switch item {
                case .title(let titleItem):
                    switch titleItem.action {
                    case .openDetail:
                        openedTitleID = titleItem.tile.titleID
                    case .launchStream(let source):
                        launchedStream = (titleItem.tile.titleID, source)
                    }
                case .showAll(let card):
                    queryState.selectedTabID = "full-library"
                    queryState.scopedCategory = LibraryScopedCategoryContext(
                        alias: card.alias,
                        label: card.label,
                        allowedTitleIDs: Set<TitleID>()
                    )
                    queryState.activeFilterIDs.removeAll()
                    enteredLibraryRoute = true
                }
            },
            homeSelectCarouselPlay: { item in
                launchedStream = (item.titleID, "home_carousel_play")
            },
            homeSelectCarouselDetails: { item in
                openedTitleID = item.titleID
            },
            homeFocusTileID: { focusState.setFocusedTileID($0, for: .home) },
            homeSettledTileID: { focusState.setSettledHeroTileID($0, for: .home) },
            librarySelectTile: { tile in
                openedTitleID = tile.titleID
            },
            libraryFocusTileID: { focusState.setFocusedTileID($0, for: .library) },
            librarySettledTileID: { focusState.setSettledHeroTileID($0, for: .library) },
            librarySelectTab: {
                queryState.selectedTabID = $0
            },
            librarySelectFilter: { _ in },
            librarySelectSort: {},
            libraryClearFilters: {},
            searchClearQuery: {},
            searchSelectTile: { tile in
                openedTitleID = tile.titleID
            },
            searchFocusTileID: { focusState.setFocusedTileID($0, for: .search) }
        )

        let homeID = TitleID(rawValue: "home-title")
        let libraryID = TitleID(rawValue: "library-title")
        let searchID = TitleID(rawValue: "search-title")
        actions.homeFocusTileID(homeID)
        actions.libraryFocusTileID(libraryID)
        actions.searchFocusTileID(searchID)
        actions.homeSettledTileID(homeID)
        actions.librarySettledTileID(libraryID)
        #expect(focusState.focusedTileID(for: .home) == homeID)
        #expect(focusState.focusedTileID(for: .library) == libraryID)
        #expect(focusState.focusedTileID(for: .search) == searchID)
        #expect(focusState.settledHeroTileID(for: .home) == homeID)
        #expect(focusState.settledHeroTileID(for: .library) == libraryID)

        let libraryTile = MediaTileViewState(
            id: "library-tile",
            titleID: libraryID,
            title: "Halo Infinite"
        )
        actions.librarySelectTile(libraryTile)
        #expect(openedTitleID == libraryID)

        let carouselItem = CloudLibraryHomeCarouselItemViewState(
            id: "carousel",
            titleID: TitleID("forza-title"),
            title: "Forza Horizon 5",
            subtitle: nil,
            categoryLabel: nil,
            ratingBadgeText: nil,
            description: nil,
            heroBackgroundURL: nil,
            artworkURL: nil
        )
        actions.homeSelectCarouselPlay(carouselItem)
        #expect(launchedStream?.0 == TitleID("forza-title"))
        #expect(launchedStream?.1 == "home_carousel_play")

        let showAllItem = CloudLibraryHomeRailItemViewState.showAll(
            .init(id: "show-all", alias: "action", label: "Action", totalCount: 12)
        )
        actions.homeSelectRailItem(showAllItem)
        #expect(enteredLibraryRoute == true)
        #expect(queryState.selectedTabID == "full-library")
        #expect(queryState.scopedCategory?.alias == "action")
    }

    @Test
    @MainActor
    func detailActions_launchStreamKeepsTypedTitleIDs() {
        var launchedStream: (TitleID, String)?
        let actions = CloudLibraryDetailRouteActions(
            launchStream: { launchedStream = ($0, $1) },
            secondaryAction: { _ in }
        )

        actions.launchStream(TitleID(rawValue: "avowed-title"), "detail_primary")

        #expect(launchedStream?.0 == TitleID(rawValue: "avowed-title"))
        #expect(launchedStream?.1 == "detail_primary")
    }

    @Test
    @MainActor
    func utilityActions_routeThroughThinHostClosures() async {
        let focusState = CloudLibraryFocusState()
        var openedConsoles = false
        var openedSettings = false

        let actions = CloudLibraryUtilityRouteActions(
            openConsoles: { openedConsoles = true },
            openSettings: { openedSettings = true },
            refreshProfileData: {},
            refreshFriends: {},
            refreshCloudLibrary: {},
            refreshConsoles: {},
            signOut: {},
            requestSideRailEntry: { focusState.requestSideRailEntry() },
            exportPreviewDump: { "ok" }
        )

        actions.openSettings()
        #expect(openedSettings == true)

        actions.openConsoles()
        #expect(openedConsoles == true)

        actions.requestSideRailEntry()
        #expect(focusState.isSideRailExpanded == true)

        let exportResult = await actions.exportPreviewDump()
        #expect(exportResult == "ok")
    }
}
