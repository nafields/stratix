// CloudLibrarySettingsPaneTests.swift
// Exercises cloud library settings pane behavior.
//

import XCTest

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibrarySettingsPaneTests: XCTestCase {
    func testResolvedPane_restoresStoredVisiblePane() {
        XCTAssertEqual(
            CloudLibrarySettingsBindings.resolvedPane(
                currentPane: .overview,
                storedRawValue: CloudLibrarySettingsPane.diagnostics.rawValue,
                isAdvancedMode: true,
                restoreStoredSelection: true
            ),
            .diagnostics
        )
    }

    func testResolvedPane_fallsBackToOverviewWhenStoredPaneIsHiddenInBasicMode() {
        XCTAssertEqual(
            CloudLibrarySettingsBindings.resolvedPane(
                currentPane: .diagnostics,
                storedRawValue: CloudLibrarySettingsPane.diagnostics.rawValue,
                isAdvancedMode: false,
                restoreStoredSelection: true
            ),
            .overview
        )
    }

    func testVisibleCases_basicModeKeepsPlayerFacingPanes() {
        XCTAssertEqual(
            CloudLibrarySettingsPane.visibleCases(isAdvanced: false),
            [.overview, .stream, .controller, .interface]
        )
        XCTAssertEqual(
            CloudLibrarySettingsPane.visibleCases(isAdvanced: true),
            CloudLibrarySettingsPane.allCases
        )
    }
}
