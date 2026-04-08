// CloudLibraryRouteState.swift
// Defines the cloud library route state.
//

import SwiftUI
import Observation
import StratixCore
import StratixModels

@Observable
@MainActor
/// Owns the shell’s browse, utility, and detail route facts plus remembered-route restoration diagnostics.
final class CloudLibraryRouteState {
    enum RestoreDiagnosticsSource: String {
        case notRestored = "not_restored"
        case overrideHome = "override_home"
        case overrideLibrary = "override_library"
        case overrideSearch = "override_search"
        case overrideConsoles = "override_consoles"
        case rememberedHome = "remembered_home"
        case rememberedLibrary = "remembered_library"
        case rememberedSearch = "remembered_search"
        case rememberedConsoles = "remembered_consoles"
        case defaultHome = "default_home"
    }

    var browseRoute: CloudLibraryBrowseRoute = .home
    var utilityRoute: ShellUtilityRoute?
    var detailPath: [TitleID] = []
    var hasRestoredStoredRoute = false
    var restoreDiagnosticsValue = RestoreDiagnosticsSource.notRestored.rawValue

    /// Restores the startup browse route once per session from launch overrides or remembered shell state.
    func restoreStoredRouteIfNeeded(
        settingsStore: SettingsStore,
        overrideRawValue: String?
    ) {
        guard !hasRestoredStoredRoute else { return }
        hasRestoredStoredRoute = true

        if let overrideRawValue,
           let overrideRoute = CloudLibraryBrowseRoute(rawValue: overrideRawValue) {
            applyRestoredBrowseRoute(
                overrideRoute,
                diagnosticsSource: diagnosticsSource(for: overrideRoute, prefix: "override")
            )
            return
        }

        guard settingsStore.shell.rememberLastSection,
              let restoredRoute = CloudLibraryBrowseRoute(rawValue: settingsStore.shell.lastDestinationRawValue) else {
            applyRestoredBrowseRoute(.home, diagnosticsSource: .defaultHome)
            return
        }
        applyRestoredBrowseRoute(
            restoredRoute,
            diagnosticsSource: diagnosticsSource(for: restoredRoute, prefix: "remembered")
        )
    }

    /// Persists the last browse destination only when the raw value has changed.
    func persistLastDestination(
        _ route: CloudLibraryBrowseRoute,
        settingsStore: SettingsStore
    ) {
        guard settingsStore.shell.lastDestinationRawValue != route.rawValue else { return }
        var shell = settingsStore.shell
        shell.lastDestinationRawValue = route.rawValue
        settingsStore.shell = shell
    }

    /// Updates the active browse route without mutating utility or detail state.
    func setBrowseRoute(_ route: CloudLibraryBrowseRoute) {
        browseRoute = route
    }

    /// Presents a utility overlay over the current browse route.
    func openUtilityRoute(_ route: ShellUtilityRoute) {
        utilityRoute = route
    }

    /// Dismisses the active utility overlay.
    func closeUtilityRoute() {
        utilityRoute = nil
    }

    /// Pushes a title onto the detail stack.
    func pushDetail(_ titleID: TitleID) {
        detailPath.append(titleID)
    }

    /// Pops the active detail route when one exists.
    func popDetail() {
        guard !detailPath.isEmpty else { return }
        detailPath.removeLast()
    }

    /// Clears the entire detail stack.
    func clearDetailPath() {
        detailPath.removeAll()
    }

    /// Returns the shell to the home browse route and clears overlays and detail state.
    func returnHome() {
        utilityRoute = nil
        detailPath.removeAll()
        browseRoute = .home
    }

    /// Maps side-rail navigation identifiers into browse routes.
    func route(for navID: SideRailNavID) -> CloudLibraryBrowseRoute {
        switch navID {
        case .home: .home
        case .library: .library
        case .search: .search
        case .consoles: .consoles
        }
    }

    /// Produces the stable analytics/debug route name used by the shell.
    func routeName(for route: CloudLibraryBrowseRoute) -> String {
        route.rawValue
    }

    /// Maps browse routes onto the app-level route enum used by detail and shell state.
    func browseRouteToAppRoute(_ route: CloudLibraryBrowseRoute) -> AppRoute {
        switch route {
        case .home: .home
        case .library: .library
        case .search: .search
        case .consoles: .home
        }
    }

    /// Applies a restored browse route while clearing any stale overlay or detail state.
    private func applyRestoredBrowseRoute(
        _ route: CloudLibraryBrowseRoute,
        diagnosticsSource: RestoreDiagnosticsSource
    ) {
        utilityRoute = nil
        detailPath.removeAll()
        browseRoute = route
        restoreDiagnosticsValue = diagnosticsSource.rawValue
    }

    /// Converts a restored route plus source prefix into the stored diagnostics enum.
    private func diagnosticsSource(
        for route: CloudLibraryBrowseRoute,
        prefix: String
    ) -> RestoreDiagnosticsSource {
        switch (prefix, route) {
        case ("override", .home): .overrideHome
        case ("override", .library): .overrideLibrary
        case ("override", .search): .overrideSearch
        case ("override", .consoles): .overrideConsoles
        case ("remembered", .home): .rememberedHome
        case ("remembered", .library): .rememberedLibrary
        case ("remembered", .search): .rememberedSearch
        case ("remembered", .consoles): .rememberedConsoles
        default: .defaultHome
        }
    }
}
