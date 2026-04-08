// CloudLibraryBackActionPolicy.swift
// Defines cloud library back action policy for the CloudLibrary / Root surface.
//

enum CloudLibraryBackAction: Equatable {
    case closeUtilityRoute
    case popDetail
    case returnBrowseHome
    case enterSideRail
    case noOp
}

/// Resolves a single shell-level back action from the current route and side-rail state.
struct CloudLibraryBackActionPolicy {
    @MainActor
    /// Prefers closing overlays and detail before falling back to home-or-side-rail restoration.
    func resolve(
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState
    ) -> CloudLibraryBackAction {
        if routeState.utilityRoute != nil {
            return .closeUtilityRoute
        }
        if !routeState.detailPath.isEmpty {
            return .popDetail
        }
        if routeState.browseRoute != .home {
            return .returnBrowseHome
        }
        if !focusState.isSideRailExpanded {
            return .enterSideRail
        }
        return .noOp
    }
}
