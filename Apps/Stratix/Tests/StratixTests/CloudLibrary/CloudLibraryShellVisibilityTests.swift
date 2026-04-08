// CloudLibraryShellVisibilityTests.swift
// Exercises cloud library shell visibility behavior.
//

import XCTest

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryShellVisibilityTests: XCTestCase {
    @MainActor
    func testRootShellVisibility_keepsShellMountedWhenStreamPriorityModeToggles() {
        assertVisibility(
            CloudLibraryView.rootShellVisibility(isStreamPriorityModeActive: false),
            opacity: 1,
            allowsHitTesting: true,
            isAccessibilityHidden: false
        )
        assertVisibility(
            CloudLibraryView.rootShellVisibility(isStreamPriorityModeActive: true),
            opacity: 0,
            allowsHitTesting: false,
            isAccessibilityHidden: true
        )
    }

    private func assertVisibility(
        _ visibility: CloudLibraryView.RootShellVisibility,
        opacity: Double,
        allowsHitTesting: Bool,
        isAccessibilityHidden: Bool
    ) {
        XCTAssertEqual(visibility.opacity, opacity)
        XCTAssertEqual(visibility.allowsHitTesting, allowsHitTesting)
        XCTAssertEqual(visibility.isAccessibilityHidden, isAccessibilityHidden)
    }
}
