// NavigationTypes.swift
// Defines navigation types for the RouteState surface.
//

import Foundation
import StratixCore
import StratixModels
import XCloudAPI

/// Mirrors the shell’s primary navigation tabs in a form that can be stored and compared outside the side rail.
enum StratixTab: String, CaseIterable, Hashable, Sendable {
    case home
    case library
    case search
    case consoles

    /// Bridges a tab back into the matching side-rail destination when one exists.
    var toNavID: SideRailNavID? {
        switch self {
        case .home: return .home
        case .library: return .library
        case .search: return .search
        case .consoles: return .consoles
        }
    }

    /// Rebuilds a tab value from the currently selected side-rail destination.
    static func from(_ navID: SideRailNavID) -> StratixTab {
        switch navID {
        case .home: return .home
        case .library: return .library
        case .search: return .search
        case .consoles: return .consoles
        }
    }
}

/// Captures the app-level route used by shell state and detail restoration.
enum AppRoute: Equatable, Hashable {
    case home
    case library
    case search
    case detail(titleID: TitleID)

    /// Flags whether the route currently points at a detail destination.
    var isDetail: Bool {
        if case .detail = self { return true }
        return false
    }
}

/// Controls how the library view orders the current browse result set.
enum LibrarySortOption: String, CaseIterable, Hashable {
    case alphabetical
    case publisher
    case recentlyPlayed

    /// Provides the short label used by the library sort button.
    var label: String {
        switch self {
        case .alphabetical:
            return "A-Z"
        case .publisher:
            return "Publisher"
        case .recentlyPlayed:
            return "Recent"
        }
    }
}

/// Stores the mutable library query state shared across browse surfaces.
struct LibraryQueryState: Equatable {
    var searchText = ""
    var selectedTabID = "full-library"
    var activeFilterIDs: Set<String> = []
    var sortOption: LibrarySortOption = .alphabetical
    var displayMode: CloudLibraryLibraryDisplayMode = .grid
    var scopedCategory: LibraryScopedCategoryContext?
}

/// Narrows the visible library set to a specific category while preserving its label and allowed title IDs.
struct LibraryScopedCategoryContext: Equatable, Hashable, Sendable {
    let alias: String
    let label: String
    let allowedTitleIDs: Set<TitleID>
}

/// Represents the currently active stream launch target for cloud and home-console entry paths.
enum StreamContext: Identifiable {
    enum ID: Hashable {
        case cloud(TitleID)
        case home(consoleID: String)
    }

    case cloud(titleId: TitleID)
    case home(console: RemoteConsole)

    /// Produces a stable stream identity for routing, presentation, and cover presentation state.
    var id: ID {
        switch self {
        case .cloud(let titleId): return .cloud(titleId)
        case .home(let console): return .home(consoleID: console.serverId)
        }
    }
}
