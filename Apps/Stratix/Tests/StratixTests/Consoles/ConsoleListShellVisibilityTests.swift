// ConsoleListShellVisibilityTests.swift
// Exercises console list shell visibility behavior.
//

import XCTest

#if canImport(Stratix)
@testable import Stratix
#endif

final class ConsoleListShellVisibilityTests: XCTestCase {
    @MainActor
    func testRootShellVisibility_keepsConsoleShellMountedWhenStreamPriorityModeToggles() {
        assertVisibility(
            ConsoleListView.rootShellVisibility(isStreamPriorityModeActive: false),
            opacity: 1,
            allowsHitTesting: true,
            isAccessibilityHidden: false
        )
        assertVisibility(
            ConsoleListView.rootShellVisibility(isStreamPriorityModeActive: true),
            opacity: 0,
            allowsHitTesting: false,
            isAccessibilityHidden: true
        )
    }

    private func assertVisibility(
        _ visibility: ConsoleListView.RootShellVisibility,
        opacity: Double,
        allowsHitTesting: Bool,
        isAccessibilityHidden: Bool
    ) {
        XCTAssertEqual(visibility.opacity, opacity)
        XCTAssertEqual(visibility.allowsHitTesting, allowsHitTesting)
        XCTAssertEqual(visibility.isAccessibilityHidden, isAccessibilityHidden)
    }
}
