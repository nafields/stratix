// ShellCheckpointCaptureUITests.swift
// Exercises shell checkpoint capture behavior.
//

import XCTest

final class ShellCheckpointCaptureUITests: ShellCheckpointUITestCase {
    @MainActor
    func testCaptureHomeSearchLibraryCheckpoints() throws {
        let homeApp = relaunchForShellHarness(browseRoute: .home)
        XCTAssertTrue(homeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        let homeRoot = waitForRouteRoot("route_home_root", in: homeApp, timeout: 12)
        let playNow = homeApp.buttons["home_carousel_play"]
        XCTAssertTrue(playNow.waitForExistence(timeout: 12), "Home Play Now CTA should exist in the deterministic shell harness")
        XCTAssertTrue(waitForFocus(on: playNow, timeout: 12), "Home Play Now CTA should be focused in the deterministic shell harness")
        XCTAssertTrue(homeRoot.exists, "Home route root should exist in the deterministic shell harness")
        settleUI()
        try captureCheckpoint(named: "home", in: homeApp)

        let libraryApp = relaunchForShellHarness(browseRoute: .library)
        XCTAssertTrue(libraryApp.windows.firstMatch.waitForExistence(timeout: 12), "Library harness window must load")
        let libraryRoot = routeRoot("route_library_root", in: libraryApp)
        XCTAssertTrue(libraryRoot.waitForExistence(timeout: 8), "Library route root should exist")
        settleUI()
        try captureCheckpoint(named: "library", in: libraryApp)

        let searchApp = relaunchForShellHarness(browseRoute: .search)
        XCTAssertTrue(searchApp.windows.firstMatch.waitForExistence(timeout: 12), "Search harness window must load")
        let searchRoot = routeRoot("route_search_root", in: searchApp)
        XCTAssertTrue(searchRoot.waitForExistence(timeout: 8), "Search route root should exist")
        XCTAssertTrue(waitForSearchField(in: searchApp).exists, "Search field should be visible on the deterministic empty search route")
        XCTAssertFalse(searchApp.staticTexts["Search your library"].exists, "Search capture should not show a pre-query status panel")
        settleUI()
        try captureCheckpoint(named: "search", in: searchApp)
    }
}
