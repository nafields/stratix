// CloudLibraryBrowseRouteActions.swift
// Defines cloud library browse route actions for the Features / CloudLibrary surface.
//

import StratixModels

struct CloudLibraryBrowseRouteActions {
    let refreshCloudLibrary: @MainActor () -> Void
    let signOut: @MainActor () -> Void
    let requestSideRailEntry: @MainActor () -> Void
    let homeSelectRailItem: @MainActor (CloudLibraryHomeRailItemViewState) -> Void
    let homeSelectCarouselPlay: @MainActor (CloudLibraryHomeCarouselItemViewState) -> Void
    let homeSelectCarouselDetails: @MainActor (CloudLibraryHomeCarouselItemViewState) -> Void
    let homeFocusTileID: @MainActor (TitleID?) -> Void
    let homeSettledTileID: @MainActor (TitleID?) -> Void
    let librarySelectTile: @MainActor (MediaTileViewState) -> Void
    let libraryFocusTileID: @MainActor (TitleID?) -> Void
    let librarySettledTileID: @MainActor (TitleID?) -> Void
    let librarySelectTab: @MainActor (String) -> Void
    let librarySelectFilter: @MainActor (ChipViewState) -> Void
    let librarySelectSort: @MainActor () -> Void
    let libraryClearFilters: @MainActor () -> Void
    let searchClearQuery: @MainActor () -> Void
    let searchSelectTile: @MainActor (MediaTileViewState) -> Void
    let searchFocusTileID: @MainActor (TitleID?) -> Void
}
