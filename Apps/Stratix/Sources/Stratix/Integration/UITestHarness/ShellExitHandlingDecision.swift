// ShellExitHandlingDecision.swift
// Defines shell exit handling decision for the Integration / UITestHarness surface.
//

struct ShellExitHandlingDecision: Equatable {
    let shouldConsumeBackEvent: Bool

    static func resolve(
        utilityRoute: ShellUtilityRoute?,
        selectedTile: MediaTileViewState?,
        streamOverlayVisible: Bool,
        primaryRoute: SideRailNavID,
        isSideRailExpanded: Bool
    ) -> Self {
        .init(
            shouldConsumeBackEvent: utilityRoute != nil
                || selectedTile != nil
                || streamOverlayVisible
                || primaryRoute != .home
                || !isSideRailExpanded
        )
    }
}
