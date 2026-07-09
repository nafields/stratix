// CloudLibraryFocusState.swift
// Defines the cloud library focus state.
//

import Observation
import StratixModels

@Observable
@MainActor
/// Stores shell-owned focus facts that survive route rebuilds and feed hero/background restoration.
final class CloudLibraryFocusState {
    /// A shell-issued request for a content surface to claim focus. Screens consume the
    /// request by generation so a stale request is never re-applied after a detail pop.
    /// Nonisolated so screen Equatable conformances can compare requests off the main actor.
    nonisolated struct ContentFocusRequest: Equatable, Sendable {
        let route: CloudLibraryBrowseRoute
        let generation: Int
    }

    var focusedTileIDsByRoute: [CloudLibraryBrowseRoute: TitleID] = [:]
    var settledHomeHeroTileID: TitleID?
    var settledLibraryHeroTileID: TitleID?
    var isSideRailExpanded = false
    var hasRequestedInitialContentFocus = false
    private(set) var contentFocusRequest: ContentFocusRequest?

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

    /// Asks the active browse surface to claim focus (side-rail hand-off, back navigation,
    /// stream dismissal, bootstrap). Each call bumps the generation so screens can tell a
    /// fresh request from one they already consumed.
    func requestTopContentFocus(for route: CloudLibraryBrowseRoute) {
        contentFocusRequest = ContentFocusRequest(
            route: route,
            generation: (contentFocusRequest?.generation ?? 0) + 1
        )
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
