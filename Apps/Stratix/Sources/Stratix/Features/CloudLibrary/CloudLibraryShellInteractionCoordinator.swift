// CloudLibraryShellInteractionCoordinator.swift
// Defines the cloud library shell interaction coordinator for the Features / CloudLibrary surface.
//

import SwiftUI
import Foundation
import StratixCore
import StratixModels

@MainActor
/// Centralizes shell-facing route and focus mutations so view hosts can stay declarative.
struct CloudLibraryShellInteractionCoordinator {
    /// Restores the initial shell route and primes the first content-focus request.
    func bootstrapShell(
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        settingsStore: SettingsStore,
        overrideRawValue: String?
    ) {
        routeState.restoreStoredRouteIfNeeded(
            settingsStore: settingsStore,
            overrideRawValue: overrideRawValue
        )
        focusState.requestInitialContentFocus()
        guard focusState.hasRequestedInitialContentFocus else { return }
        focusState.clearInitialContentFocusRequest()
        focusState.requestTopContentFocus(for: routeState.browseRoute)
    }

    /// Prewarms detail state before pushing the title so the first detail frame can reuse cached projections.
    func openDetail(
        _ titleID: TitleID,
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        stateSnapshot: CloudLibraryStateSnapshot,
        viewModel: CloudLibraryViewModel,
        prewarmDetailState: @MainActor (TitleID) async -> Void
    ) async {
        guard routeState.utilityRoute == nil else { return }
        guard stateSnapshot.item(titleID: titleID) != nil else { return }
        await prewarmDetailState(titleID)
        viewModel.detailStateCache.touch(titleID)
        focusState.setFocusedTileID(titleID, for: routeState.browseRoute)
        if routeState.browseRoute == .home {
            focusState.setSettledHeroTileID(titleID, for: .home)
        }
        focusState.isSideRailExpanded = false
        NavigationPerformanceTracker.recordRouteChange(
            from: routeState.routeName(for: routeState.browseRoute),
            to: "detail:\(titleID.rawValue)",
            reason: "detail_open"
        )
        routeState.pushDetail(titleID)
    }

    /// Switches the active browse route and clears route-local state that should not survive the transition.
    func selectPrimaryRoute(
        _ targetRoute: CloudLibraryBrowseRoute,
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        settingsStore: SettingsStore,
        queryState: Binding<LibraryQueryState>
    ) {
        routeState.closeUtilityRoute()
        routeState.clearDetailPath()
        routeState.setBrowseRoute(targetRoute)
        routeState.persistLastDestination(targetRoute, settingsStore: settingsStore)
        if targetRoute != .library {
            queryState.wrappedValue.scopedCategory = nil
        }
        focusState.requestTopContentFocus(for: targetRoute)
    }

    /// Opens the profile overlay and hands focus ownership to the utility surface.
    func openProfileUtility(
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState
    ) {
        routeState.openUtilityRoute(.profile)
        focusState.isSideRailExpanded = false
        focusState.requestUtilityFocus(for: .profile)
    }

    /// Opens settings on the overview pane so every settings entry path lands on the same root surface.
    func openSettingsUtility(
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        selectedSettingsPane: Binding<CloudLibrarySettingsPane>
    ) {
        routeState.openUtilityRoute(.settings)
        selectedSettingsPane.wrappedValue = .overview
        focusState.isSideRailExpanded = false
        focusState.requestUtilityFocus(for: .settings)
    }

    /// Routes into the consoles browse surface and persists it as the last non-utility destination.
    func openConsoles(
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        settingsStore: SettingsStore
    ) {
        routeState.closeUtilityRoute()
        routeState.setBrowseRoute(.consoles)
        routeState.persistLastDestination(.consoles, settingsStore: settingsStore)
        focusState.isSideRailExpanded = false
        focusState.requestTopContentFocus(for: .consoles)
    }

    /// Applies the resolved shell back action without exposing route/focus bookkeeping to the view layer.
    func handleBack(
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        backActionPolicy: CloudLibraryBackActionPolicy,
        settingsStore: SettingsStore,
        queryState: Binding<LibraryQueryState>
    ) {
        switch backActionPolicy.resolve(routeState: routeState, focusState: focusState) {
        case .closeUtilityRoute:
            guard let utilityRoute = routeState.utilityRoute else { return }
            routeState.closeUtilityRoute()
            focusState.requestTopContentFocus(for: routeState.browseRoute)
            NavigationPerformanceTracker.recordRouteChange(
                from: utilityRoute.rawValue,
                to: routeState.routeName(for: routeState.browseRoute),
                reason: "utility_route_close"
            )
        case .popDetail:
            routeState.popDetail()
            if routeState.browseRoute == .search,
               queryState.wrappedValue.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focusState.requestTopContentFocus(for: .search)
            }
        case .returnBrowseHome:
            let fromRoute = routeState.routeName(for: routeState.browseRoute)
            queryState.wrappedValue.scopedCategory = nil
            routeState.setBrowseRoute(.home)
            routeState.persistLastDestination(.home, settingsStore: settingsStore)
            focusState.isSideRailExpanded = false
            focusState.requestTopContentFocus(for: .home)
            NavigationPerformanceTracker.recordRouteChange(
                from: fromRoute,
                to: "home",
                reason: "back_home"
            )
        case .enterSideRail:
            focusState.isSideRailExpanded = true
        case .noOp:
            break
        }
    }

    /// Toggles the settings overlay from the remote shortcut while respecting the active detail stack.
    func handleSettingsShortcut(
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        selectedSettingsPane: Binding<CloudLibrarySettingsPane>
    ) {
        guard routeState.detailPath.isEmpty else { return }
        guard routeState.utilityRoute != .settings else {
            routeState.closeUtilityRoute()
            focusState.requestTopContentFocus(for: routeState.browseRoute)
            return
        }
        openSettingsUtility(
            routeState: routeState,
            focusState: focusState,
            selectedSettingsPane: selectedSettingsPane
        )
    }

    /// Recomputes scene-level derived state from the latest view-model projections and query state.
    func applySceneMutation(
        sceneModel: CloudLibrarySceneModel,
        stateSnapshot: CloudLibraryStateSnapshot,
        queryState: LibraryQueryState,
        quickResumeTile: Bool,
        viewModel: CloudLibraryViewModel
    ) {
        sceneModel.applySceneMutation(
            libraryStateInputs: stateSnapshot,
            queryState: queryState,
            showsContinueBadge: quickResumeTile,
            viewModel: viewModel
        )
    }

    /// Rebuilds shell status derived state, including library-load readiness and cached-home merchandising status.
    func applyStatusMutation(
        sceneModel: CloudLibrarySceneModel,
        routeState: CloudLibraryRouteState,
        loadState: CloudLibraryLoadState,
        stateSnapshot: CloudLibraryStateSnapshot,
        viewModel: CloudLibraryViewModel
    ) {
        sceneModel.applyStatusMutation(
            isHomeRoute: routeState.browseRoute == .home,
            loadState: loadState,
            sections: stateSnapshot.sections,
            hasCompletedInitialHomeMerchandising: stateSnapshot.hasCompletedInitialHomeMerchandising,
            hasRecoveredLiveHomeMerchandisingThisSession: stateSnapshot.hasRecoveredLiveHomeMerchandisingThisSession,
            hasHomeMerchandisingSnapshot: stateSnapshot.hasHomeMerchandisingSnapshot,
            homeState: viewModel.cachedHomeState
        )
    }

    /// Keeps the scene route projection in sync with the active browse and utility routes.
    func applyRouteMutation(
        sceneModel: CloudLibrarySceneModel,
        routeState: CloudLibraryRouteState
    ) {
        sceneModel.applyRouteMutation(
            browseRouteRawValue: routeState.browseRoute.rawValue,
            utilityRouteRawValue: routeState.utilityRoute?.rawValue
        )
    }

    /// Rebuilds the hero-background inputs that bridge route state and the currently focused hero tiles.
    func rebuildHeroBackgroundContext(
        viewModel: CloudLibraryViewModel,
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState
    ) {
        viewModel.rebuildHeroBackgroundContext(
            browseRouteRawValue: routeState.browseRoute.rawValue,
            utilityRouteVisible: routeState.utilityRoute != nil,
            detailTitleID: routeState.detailPath.last,
            homeFocusedTitleID: focusState.settledHeroTileID(for: .home),
            libraryFocusedTitleID: focusState.settledHeroTileID(for: .library)
        )
    }

    /// Commits the resolved hero-background URL into scene state only after the inputs have been rebuilt.
    func applyHeroBackgroundMutation(
        sceneModel: CloudLibrarySceneModel,
        viewModel: CloudLibraryViewModel
    ) {
        sceneModel.applyHeroBackgroundMutation(inputs: viewModel.cachedHeroBackgroundContext.inputs)
    }
}
