// CloudLibraryRoutePresentationBuilderTests.swift
// Exercises cloud library route presentation builder behavior.
//

import XCTest
import StratixModels
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryRoutePresentationBuilderTests: XCTestCase {
    @MainActor
    func testMakeBrowseRoutePresentationIncludesLoadStateInsteadOfLegacyFlags() {
        let builder = CloudLibraryBrowseRoutePresentationBuilder()
        let routeState = CloudLibraryRouteState()
        routeState.setBrowseRoute(.search)
        let focusState = CloudLibraryFocusState()
        focusState.requestTopContentFocus(for: .search)
        let browseTile = MediaTileViewState(id: "browse-tile", titleID: TitleID("browse-title"), title: "Halo Infinite")
        let resultTile = MediaTileViewState(id: "result-tile", titleID: TitleID("result-title"), title: "Forza Horizon 5")

        let presentation = builder.makeBrowseRoutePresentation(
            loadState: .degradedCached(error: "offline_error", ageSeconds: 15),
            routeState: routeState,
            focusState: focusState,
            homeState: CloudLibraryHomeViewState(heroBackgroundURL: nil, carouselItems: [], sections: []),
            libraryState: CloudLibraryLibraryViewState(
                heroBackdropURL: nil,
                tabs: [.init(id: "all", title: "All Games")],
                selectedTabID: "all",
                filters: [],
                sortLabel: "Alphabetical",
                displayMode: .grid,
                gridItems: []
            ),
            totalLibraryCount: 42,
            searchBrowseItems: [browseTile],
            searchResultItems: [resultTile]
        )

        XCTAssertEqual(presentation.browseRoute, .search)
        XCTAssertEqual(presentation.loadState, .degradedCached(error: "offline_error", ageSeconds: 15))
        XCTAssertEqual(presentation.totalLibraryCount, 42)
        XCTAssertEqual(presentation.searchBrowseItems, [browseTile])
        XCTAssertEqual(presentation.searchResultItems, [resultTile])
    }

    @MainActor
    func testMakeBrowseRoutePresentationUsesTypedPreferredTileIDs() {
        let builder = CloudLibraryBrowseRoutePresentationBuilder()
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()
        let homeTitleID = TitleID(rawValue: "home-title")
        let libraryTitleID = TitleID(rawValue: "library-title")
        let searchTitleID = TitleID(rawValue: "search-title")
        focusState.setFocusedTileID(homeTitleID, for: .home)
        focusState.setFocusedTileID(libraryTitleID, for: .library)
        focusState.setFocusedTileID(searchTitleID, for: .search)

        let homeTile = MediaTileViewState(id: "home-tile", titleID: homeTitleID, title: "Home Game")
        let libraryTile = MediaTileViewState(id: "library-tile", titleID: libraryTitleID, title: "Library Game")
        let searchTile = MediaTileViewState(id: "search-tile", titleID: searchTitleID, title: "Search Game")
        let homeState = CloudLibraryHomeViewState(
            heroBackgroundURL: nil,
            carouselItems: [],
            sections: [
                CloudLibraryRailSectionViewState(
                    id: "recent",
                    alias: "recent",
                    title: "Jump Back In",
                    subtitle: nil,
                    items: [
                        .title(.init(id: homeTile.id, tile: homeTile, action: .openDetail))
                    ]
                )
            ]
        )
        let libraryState = CloudLibraryLibraryViewState(
            heroBackdropURL: nil,
            tabs: [.init(id: "all", title: "All Games")],
            selectedTabID: "all",
            filters: [],
            sortLabel: "Alphabetical",
            displayMode: .grid,
            gridItems: [libraryTile]
        )

        let presentation = builder.makeBrowseRoutePresentation(
            loadState: .liveFresh,
            routeState: routeState,
            focusState: focusState,
            homeState: homeState,
            libraryState: libraryState,
            totalLibraryCount: 3,
            searchBrowseItems: [searchTile],
            searchResultItems: []
        )

        XCTAssertEqual(presentation.homeTileLookup[homeTitleID]?.tile, homeTile)
        XCTAssertEqual(presentation.libraryTileLookup[libraryTitleID], libraryTile)
        XCTAssertEqual(presentation.searchTileLookup[searchTitleID], searchTile)
        XCTAssertEqual(presentation.preferredHomeTileID, homeTitleID)
        XCTAssertEqual(presentation.preferredLibraryTileID, libraryTitleID)
        XCTAssertEqual(presentation.preferredSearchTileID, searchTitleID)
        XCTAssertEqual(Set(presentation.homeTileLookup.keys), [homeTitleID])
        XCTAssertEqual(Set(presentation.libraryTileLookup.keys), [libraryTitleID])
        XCTAssertEqual(Set(presentation.searchTileLookup.keys), [searchTitleID])
    }

    @MainActor
    func testMakeBrowseRoutePresentationDeduplicatesTileLookupEntries() {
        let builder = CloudLibraryBrowseRoutePresentationBuilder()
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()

        let duplicateTitleID = TitleID(rawValue: "duplicate-title")
        let homeFirstTile = MediaTileViewState(id: "home-first", titleID: duplicateTitleID, title: "Home First")
        let homeSecondTile = MediaTileViewState(id: "home-second", titleID: duplicateTitleID, title: "Home Second")
        let libraryFirstTile = MediaTileViewState(id: "library-first", titleID: duplicateTitleID, title: "Library First")
        let librarySecondTile = MediaTileViewState(id: "library-second", titleID: duplicateTitleID, title: "Library Second")
        let searchBrowseTile = MediaTileViewState(id: "search-browse", titleID: duplicateTitleID, title: "Search Browse")
        let searchResultTile = MediaTileViewState(id: "search-result", titleID: duplicateTitleID, title: "Search Result")

        let presentation = builder.makeBrowseRoutePresentation(
            loadState: .liveFresh,
            routeState: routeState,
            focusState: focusState,
            homeState: CloudLibraryHomeViewState(
                heroBackgroundURL: nil,
                carouselItems: [],
                sections: [
                    CloudLibraryRailSectionViewState(
                        id: "recent",
                        alias: "recent",
                        title: "Jump Back In",
                        subtitle: nil,
                        items: [
                            .title(.init(id: homeFirstTile.id, tile: homeFirstTile, action: .openDetail)),
                            .title(.init(id: homeSecondTile.id, tile: homeSecondTile, action: .openDetail))
                        ]
                    )
                ]
            ),
            libraryState: CloudLibraryLibraryViewState(
                heroBackdropURL: nil,
                tabs: [.init(id: "all", title: "All Games")],
                selectedTabID: "all",
                filters: [],
                sortLabel: "Alphabetical",
                displayMode: .grid,
                gridItems: [libraryFirstTile, librarySecondTile]
            ),
            totalLibraryCount: 2,
            searchBrowseItems: [searchBrowseTile],
            searchResultItems: [searchResultTile]
        )

        XCTAssertEqual(presentation.homeTileLookup[duplicateTitleID]?.tile.id, homeFirstTile.id)
        XCTAssertEqual(presentation.libraryTileLookup[duplicateTitleID]?.id, libraryFirstTile.id)
        XCTAssertEqual(presentation.searchTileLookup[duplicateTitleID]?.id, searchBrowseTile.id)
    }

    @MainActor
    func testMakeShellPresentationBuildsFromTypedShellSnapshots() {
        let settingsStore = CloudLibraryTestSupport.makeSettingsStore()
        let libraryController = LibraryController(
            initialState: CloudLibraryTestSupport.makeLibraryState(
                sections: [CloudLibrarySection(id: "library", name: "Library", items: [CloudLibraryTestSupport.makeItem()])]
            )
        )
        let profileController = CloudLibraryTestSupport.makeProfileController()
        let builder = CloudLibraryShellPresentationBuilder()

        let projection = builder.makeShellPresentation(
            profileSnapshot: profileController.profileShellSnapshot(),
            libraryStatus: libraryController.libraryShellStatusSnapshot(),
            settingsStore: settingsStore,
            libraryCount: 12,
            consoleCount: 3
        )

        XCTAssertEqual(projection.shellChrome.profileName, "Player One")
        XCTAssertEqual(projection.sideRail.libraryCount, 12)
        XCTAssertEqual(projection.sideRail.consoleCount, 3)
    }

    @MainActor
    func testMakeUtilityRoutePresentationBuildsFromTypedUtilityInputs() {
        let settingsStore = CloudLibraryTestSupport.makeSettingsStore()
        let libraryState = CloudLibraryTestSupport.makeLibraryState(
            sections: [CloudLibrarySection(id: "library", name: "Library", items: [CloudLibraryTestSupport.makeItem()])],
            isLoading: true
        )
        let libraryController = LibraryController(initialState: libraryState)
        let profileController = CloudLibraryTestSupport.makeProfileController()
        let shellBuilder = CloudLibraryShellPresentationBuilder()
        let utilityBuilder = CloudLibraryUtilityRoutePresentationBuilder()
        let snapshot = CloudLibraryStateSnapshot(state: libraryState)
        let shellPresentation = shellBuilder.makeShellPresentation(
            profileSnapshot: profileController.profileShellSnapshot(),
            libraryStatus: libraryController.libraryShellStatusSnapshot(),
            settingsStore: settingsStore,
            libraryCount: 12,
            consoleCount: 3
        )

        let presentation = utilityBuilder.makeUtilityRoutePresentation(
            shellPresentation: shellPresentation,
            profileSnapshot: profileController.profileShellSnapshot(),
            isLoadingCloudLibrary: snapshot.isLoading,
            regionOverrideDiagnostics: nil
        )

        XCTAssertEqual(presentation.profile.gamertag, "playerone")
        XCTAssertEqual(presentation.settings.profileName, "Player One")
        XCTAssertTrue(presentation.settings.isLoadingCloudLibrary)
    }
}
