// SideRailFocusCoordinatorTests.swift
// Exercises side rail focus coordinator behavior.
//

import XCTest

#if canImport(Stratix)
@testable import Stratix
#endif

final class SideRailFocusCoordinatorTests: XCTestCase {
    func testPreferredEntryTarget_prefersSettingsActionForSettingsRoute() {
        XCTAssertEqual(
            SideRailFocusCoordinator.preferredEntryTarget(
                activeUtilityRoute: .settings,
                trailingActions: [.init(id: "settings", systemImage: "gearshape", accessibilityLabel: "Settings")],
                selectedNavID: .library
            ),
            .action("settings")
        )
    }

    func testIsCollapsedFocusable_onlyAllowsSelectedNavWhenEnabled() {
        XCTAssertTrue(
            SideRailFocusCoordinator.isCollapsedFocusable(
                .nav(.library),
                selectedNavID: .library,
                collapsedSelectedNavFocusable: true
            )
        )
        XCTAssertFalse(
            SideRailFocusCoordinator.isCollapsedFocusable(
                .nav(.home),
                selectedNavID: .library,
                collapsedSelectedNavFocusable: true
            )
        )
    }
}
