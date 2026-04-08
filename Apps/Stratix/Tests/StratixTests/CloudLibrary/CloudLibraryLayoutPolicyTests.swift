// CloudLibraryLayoutPolicyTests.swift
// Exercises cloud library layout policy behavior.
//

import XCTest

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryLayoutPolicyTests: XCTestCase {
    func testHomeRouteUsesEdgeToEdgeShellSpacing() {
        let policy = CloudLibraryLayoutPolicy()

        XCTAssertEqual(
            policy.shellContentHorizontalPadding(browseRoute: .home, utilityRoute: nil),
            0
        )
        XCTAssertEqual(
            policy.shellContentTopPadding(browseRoute: .home, utilityRoute: nil),
            0
        )
        XCTAssertEqual(
            policy.shellContentLeadingAdjustment(browseRoute: .home, utilityRoute: nil),
            0
        )
    }

    func testLibraryAndSearchRoutesUseBrowseSpacing() {
        let policy = CloudLibraryLayoutPolicy()

        XCTAssertEqual(
            policy.shellContentHorizontalPadding(browseRoute: .library, utilityRoute: nil),
            StratixTheme.Layout.outerPadding
        )
        XCTAssertEqual(
            policy.shellContentHorizontalPadding(browseRoute: .search, utilityRoute: nil),
            StratixTheme.Layout.outerPadding
        )
        XCTAssertEqual(
            policy.shellContentTopPadding(browseRoute: .library, utilityRoute: nil),
            StratixTheme.Shell.contentTopPadding
        )
        XCTAssertEqual(
            policy.shellContentTopPadding(browseRoute: .search, utilityRoute: nil),
            StratixTheme.Shell.contentTopPadding
        )
        XCTAssertEqual(
            policy.shellContentLeadingAdjustment(browseRoute: .library, utilityRoute: nil),
            StratixTheme.Shell.browseRouteLeadingInset
        )
        XCTAssertEqual(
            policy.shellContentLeadingAdjustment(browseRoute: .search, utilityRoute: nil),
            StratixTheme.Shell.browseRouteLeadingInset
        )
    }

    func testUtilityAndConsoleRoutesOverrideBrowseSpacingToZero() {
        let policy = CloudLibraryLayoutPolicy()

        XCTAssertEqual(
            policy.shellContentHorizontalPadding(browseRoute: .library, utilityRoute: .settings),
            0
        )
        XCTAssertEqual(
            policy.shellContentTopPadding(browseRoute: .library, utilityRoute: .settings),
            0
        )
        XCTAssertEqual(
            policy.shellContentLeadingAdjustment(browseRoute: .library, utilityRoute: .settings),
            0
        )
        XCTAssertEqual(
            policy.shellContentHorizontalPadding(browseRoute: .consoles, utilityRoute: nil),
            0
        )
        XCTAssertEqual(
            policy.shellContentTopPadding(browseRoute: .consoles, utilityRoute: nil),
            0
        )
        XCTAssertEqual(
            policy.shellContentLeadingAdjustment(browseRoute: .consoles, utilityRoute: nil),
            0
        )
    }
}
