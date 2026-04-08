// CloudLibraryFocusState.swift
// Defines the cloud library focus state.
//

import Observation
import StratixModels

@Observable
@MainActor
/// Stores shell-owned focus facts that survive route rebuilds and feed hero/background restoration.
final class CloudLibraryFocusState {
    var focusedTileIDsByRoute: [CloudLibraryBrowseRoute: TitleID] = [:]
    var settledHomeHeroTileID: TitleID?
    var settledLibraryHeroTileID: TitleID?
    var isSideRailExpanded = false
    var hasRequestedInitialContentFocus = false

    /// Returns the last focused title for the given browse route when one exists.
    func focusedTileID(for route: CloudLibraryBrowseRoute) -> TitleID? {
        focusedTileIDsByRoute[route]
    }

    /// Records the currently focused title for a browse route without changing any route state.
    func setFocusedTileID(_ titleID: TitleID?, for route: CloudLibraryBrowseRoute) {
        focusedTileIDsByRoute[route] = titleID
    }

    /// Returns the route-specific hero tile that should drive shell hero/background restoration.
    func settledHeroTileID(for route: CloudLibraryBrowseRoute) -> TitleID? {
        switch route {
        case .home:
            settledHomeHeroTileID
        case .library:
            settledLibraryHeroTileID
        case .search, .consoles:
            nil
        }
    }

    /// Stores the settled hero tile for the routes that participate in shell hero restoration.
    func setSettledHeroTileID(_ titleID: TitleID?, for route: CloudLibraryBrowseRoute) {
        switch route {
        case .home:
            settledHomeHeroTileID = titleID
        case .library:
            settledLibraryHeroTileID = titleID
        case .search, .consoles:
            break
        }
    }

    /// Exists as the shell-facing content-focus hook even when the underlying focus path is framework-owned.
    func requestTopContentFocus(for route: CloudLibraryBrowseRoute) {
        _ = route
    }

    /// Exists as the shell-facing utility-focus hook even when the utility surface owns the concrete focus move.
    func requestUtilityFocus(for route: ShellUtilityRoute) {
        _ = route
    }

    /// Expands the side rail so the next remote move can re-enter shell navigation.
    func requestSideRailEntry() {
        isSideRailExpanded = true
    }

    /// Collapses the side rail after content has claimed focus ownership.
    func requestSideRailCollapse() {
        isSideRailExpanded = false
    }

    /// Marks that shell bootstrap still owes the initial content focus handoff.
    func requestInitialContentFocus() {
        hasRequestedInitialContentFocus = true
    }

    /// Clears the bootstrap-only content-focus request once the shell has consumed it.
    func clearInitialContentFocusRequest() {
        hasRequestedInitialContentFocus = false
    }
}
