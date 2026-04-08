// CloudLibraryBrowseRouteHost.swift
// Defines cloud library browse route host for the Features / CloudLibrary surface.
//

import SwiftUI
import StratixCore
import StratixModels

/// Renders the active browse destination and handles load-state gating for each route.
struct CloudLibraryBrowseRouteHost: View {
    @Environment(ShellBootstrapController.self) private var shellBootstrapController

    let presentation: CloudLibraryBrowseRoutePresentation
    let searchText: Binding<String>
    let actions: CloudLibraryBrowseRouteActions

    var body: some View {
        switch presentation.browseRoute {
        case .consoles:
            CloudLibraryConsolesView(onRequestSideRailEntry: actions.requestSideRailEntry)
        case .home, .library, .search:
            libraryContent
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch presentation.browseRoute {
        case .home:
            homeRouteContent
        case .library:
            browseRouteContent { libraryScreen }
        case .search:
            browseRouteContent { searchScreen }
        case .consoles:
            EmptyView()
        }
    }

    @ViewBuilder
    private var homeRouteContent: some View {
        switch presentation.loadState {
        case .notLoaded:
            loadingPanel
        case .failedNoCache(let error):
            errorPanel(error)
        case .restoredCached, .refreshingFromCache, .liveFresh, .degradedCached:
            loadedHomeContent
        }
    }

    @ViewBuilder
    /// Applies the shared load-state gate used by library and search before rendering their live content.
    private func browseRouteContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        switch presentation.loadState {
        case .notLoaded:
            loadingPanel
        case .failedNoCache(let error):
            errorPanel(error)
        case .restoredCached, .refreshingFromCache, .liveFresh, .degradedCached:
            content()
        }
    }

    private var loadingPanel: some View {
        CloudLibraryStatusPanel(
            state: .init(
                kind: .loading,
                title: "Refreshing Game Pass",
                message: "Syncing your cloud catalog and recent titles.",
                primaryActionTitle: nil
            )
        )
    }

    private func errorPanel(_ error: String) -> some View {
        CloudLibraryStatusPanel(
            state: .init(
                kind: .error,
                title: "Couldn't load library",
                message: error,
                primaryActionTitle: "Try Again"
            ),
            onPrimaryAction: actions.refreshCloudLibrary
        )
    }

    private var loadedHomeContent: some View {
        CloudLibraryHomeScreen(
            state: presentation.homeState,
            preferredTitleID: presentation.preferredHomeTileID,
            onSelectRailItem: actions.homeSelectRailItem,
            onSelectCarouselPlay: actions.homeSelectCarouselPlay,
            onSelectCarouselDetails: actions.homeSelectCarouselDetails,
            onRequestSideRailEntry: actions.requestSideRailEntry,
            onFocusTileID: actions.homeFocusTileID,
            onSettledTileID: actions.homeSettledTileID,
            tileLookup: presentation.homeTileLookup
        )
        .equatable()
        .modifier(RouteHomeRootAccessibilityModifier(isEnabled: shellBootstrapController.phase == .ready))
    }

    private var libraryScreen: some View {
        CloudLibraryLibraryScreen(
            state: presentation.libraryState,
            tileLookup: presentation.libraryTileLookup,
            preferredTitleID: presentation.preferredLibraryTileID,
            onSelectTile: actions.librarySelectTile,
            onFocusTileID: actions.libraryFocusTileID,
            onSettledTileID: actions.librarySettledTileID,
            onSelectTab: actions.librarySelectTab,
            onSelectFilter: actions.librarySelectFilter,
            onSelectSort: actions.librarySelectSort,
            onClearFilters: actions.libraryClearFilters,
            onRequestSideRailEntry: actions.requestSideRailEntry
        )
        .equatable()
    }

    private var searchScreen: some View {
        CloudLibrarySearchScreen(
            queryTextValue: searchText.wrappedValue,
            totalLibraryCount: presentation.totalLibraryCount,
            browseItems: presentation.searchBrowseItems,
            resultItems: presentation.searchResultItems,
            tileLookup: presentation.searchTileLookup,
            preferredTitleID: presentation.preferredSearchTileID,
            onClearQuery: actions.searchClearQuery,
            onSelectTile: actions.searchSelectTile,
            onFocusTileID: actions.searchFocusTileID,
            onRequestSideRailEntry: actions.requestSideRailEntry
        )
        .equatable()
        .searchable(text: searchText, prompt: "Search cloud titles")
    }
}

private struct RouteHomeRootAccessibilityModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    /// Delays the home-root accessibility marker until shell bootstrap has published a ready phase.
    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityIdentifier("route_home_root")
        } else {
            content
        }
    }
}
