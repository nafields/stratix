// ShellCheckpointRouteBehaviorUITests.swift
// Exercises shell checkpoint route behavior behavior.
//

import XCTest

final class ShellCheckpointRouteBehaviorUITests: ShellCheckpointUITestCase {
    @MainActor
    func testGamePassRoutePaddingConsistency() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        _ = waitForFirstGameTile(in: smokeApp)

        let homeRoot = routeRoot("route_home_root", in: smokeApp)
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 8), "Home route root should exist")
        let homeMinX = homeRoot.frame.minX

        selectSideRailNav("side_rail_nav_library", in: smokeApp)
        let libraryRoot = routeRoot("route_library_root", in: smokeApp)
        XCTAssertTrue(libraryRoot.waitForExistence(timeout: 8), "Library route root should exist")
        let libraryMinX = libraryRoot.frame.minX

        _ = waitForFirstGameTile(in: smokeApp)
        guard let focusedLibraryTile = focusAnyGameTile(in: smokeApp, maxAttempts: 28) else {
            XCTFail("Could not acquire focus on a library game tile")
            return
        }
        XCTAssertTrue(focusedLibraryTile.exists, "Focused library tile should exist before opening detail")
        XCUIRemote.shared.press(.select)

        let detailRoot = routeRoot("route_detail_root", in: smokeApp)
        XCTAssertTrue(detailRoot.waitForExistence(timeout: 8), "Detail route root should exist")
        let detailMinX = detailRoot.frame.minX

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(libraryRoot.waitForExistence(timeout: 8), "Library route should return after exiting detail")

        selectSideRailNav("side_rail_nav_search", in: smokeApp)
        let searchRoot = routeRoot("route_search_root", in: smokeApp)
        XCTAssertTrue(searchRoot.waitForExistence(timeout: 8), "Search route root should exist")
        let searchMinX = searchRoot.frame.minX

        XCTAssertGreaterThan(
            libraryMinX - homeMinX,
            40,
            "Library should remain visually inset relative to Home"
        )
        XCTAssertGreaterThan(
            searchMinX - homeMinX,
            40,
            "Search should remain visually inset relative to Home"
        )
        XCTAssertGreaterThan(
            detailMinX - homeMinX,
            40,
            "Detail should remain visually inset relative to Home"
        )
        XCTAssertLessThanOrEqual(abs(libraryMinX - searchMinX), 4, "Library and Search should share aligned browse-route padding")
        XCTAssertLessThanOrEqual(abs(libraryMinX - detailMinX), 4, "Library and Detail should share aligned browse-route padding")
    }

    @MainActor
    func testSideRailEntryRequiresLeftEdgeHandoff() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        let firstTile = waitForFirstGameTile(in: smokeApp)
        focusFirstTile(firstTile, maxDownPresses: 10)
        XCTAssertNil(focusedSideRailNav(in: smokeApp), "Side rail should not be focused immediately after content focus")

        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.right)
        XCTAssertNil(
            focusedSideRailNav(in: smokeApp),
            "Normal up/down/right traversal should not auto-enter side rail"
        )

        let focusedNav = waitForFocusedSideRailNav(in: smokeApp)
        XCTAssertNotNil(
            focusedNav,
            "Side rail should become focusable only after explicit left-edge handoff"
        )
    }

    @MainActor
    func testDetailPushPopDoesNotAutoFocusSideRail() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        _ = waitForFirstGameTile(in: smokeApp)
        selectSideRailNav("side_rail_nav_library", in: smokeApp)
        let libraryRoot = routeRoot("route_library_root", in: smokeApp)
        XCTAssertTrue(libraryRoot.waitForExistence(timeout: 8), "Library route root should exist before opening detail")
        _ = waitForFirstGameTile(in: smokeApp)
        guard focusAnyGameTile(in: smokeApp, maxAttempts: 28) != nil else {
            XCTFail("Could not acquire focus on any library game tile before opening detail")
            return
        }
        XCUIRemote.shared.press(.select)

        let detailRoot = routeRoot("route_detail_root", in: smokeApp)
        XCTAssertTrue(detailRoot.waitForExistence(timeout: 8), "Detail route root should exist")
        _ = detailRoot.frame.minX

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            libraryRoot.waitForExistence(timeout: 8),
            "Library route should be visible after popping detail"
        )
        settleUI(0.3)
        XCTAssertNil(
            focusedSideRailNav(in: smokeApp),
            "Detail pop should not auto-focus side rail"
        )
    }

    @MainActor
    func testSettingsRoutePlayPauseOpenClose() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")
        _ = waitForFirstGameTile(in: smokeApp)

        let settingsRoot = routeRoot("route_settings_root", in: smokeApp)
        XCTAssertFalse(settingsRoot.exists, "Settings route should be closed before the roundtrip starts")

        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 5), "Settings route should open from Play/Pause")

        XCUIRemote.shared.press(.playPause)
        let closedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == NO"),
            object: settingsRoot
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [closedExpectation], timeout: 5),
            .completed,
            "Settings route should close on the second Play/Pause press"
        )
    }

    @MainActor
    func testSearchRouteDoesNotAutoFocusGridTileOnEntry() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        _ = waitForFirstGameTile(in: smokeApp)
        selectSideRailNav("side_rail_nav_search", in: smokeApp)

        let searchRoot = routeRoot("route_search_root", in: smokeApp)
        XCTAssertTrue(searchRoot.waitForExistence(timeout: 8), "Search route root should exist")
        settleUI(0.25)

        XCTAssertNil(
            focusedGameTile(in: smokeApp),
            "Search entry should prefer search input state and not auto-focus a browse tile"
        )
        XCTAssertFalse(
            smokeApp.staticTexts["Search your library"].exists,
            "Search entry should not render a pre-query status panel"
        )
    }

    @MainActor
    func testProfileRailExposesPrimaryDestinations() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        _ = waitForFirstGameTile(in: smokeApp)
        openProfileRail(in: smokeApp)

        XCTAssertTrue(smokeApp.buttons["profile_rail_consoles"].exists, "Profile page should expose Consoles")
        XCTAssertTrue(smokeApp.buttons["profile_rail_settings"].exists, "Profile page should expose Settings")
        XCTAssertTrue(smokeApp.buttons["profile_rail_signout"].exists, "Profile page should expose Sign Out")
    }

    @MainActor
    func testConsolesRouteBackReturnsHome() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        _ = waitForFirstGameTile(in: smokeApp)
        selectSideRailNav("side_rail_nav_consoles", in: smokeApp)

        let consolesRoot = routeRoot("route_consoles_root", in: smokeApp)
        XCTAssertTrue(consolesRoot.waitForExistence(timeout: 8), "Consoles route root should exist")
        waitForSelectedSideRailNav("side_rail_nav_consoles", in: smokeApp)

        XCUIRemote.shared.press(.menu)

        let homeRoot = routeRoot("route_home_root", in: smokeApp)
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 8), "Back from Consoles should return to Home")
        waitForSelectedSideRailNav("side_rail_nav_home", in: smokeApp)
    }

    @MainActor
    func testUtilityRoutesReturnToCurrentPrimaryRoute() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        _ = waitForFirstGameTile(in: smokeApp)
        selectSideRailNav("side_rail_nav_library", in: smokeApp)
        let libraryRoot = waitForRouteRoot("route_library_root", in: smokeApp)

        openProfileRail(in: smokeApp)
        let profileRoot = waitForRouteRoot("route_profile_root", in: smokeApp, timeout: 5)
        XCTAssertTrue(profileRoot.exists, "Profile route should open from the side rail")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(libraryRoot.waitForExistence(timeout: 5), "Back from Profile should return to the previous primary route")

        XCUIRemote.shared.press(.playPause)
        let settingsRoot = waitForRouteRoot("route_settings_root", in: smokeApp, timeout: 5)
        XCTAssertTrue(settingsRoot.exists, "Settings route should open from Play/Pause")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(libraryRoot.waitForExistence(timeout: 5), "Back from Settings should return to the previous primary route")
    }

    @MainActor
    func testShellRouteSwitchPerformance() throws {
        let smokeApp = try relaunchForRealDataSmoke()
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Game Pass app window must load")

        let homeRoot = waitForRouteRoot("route_home_root", in: smokeApp)

        let startedAt = Date()
        let libraryRoot = selectRoute(
            "side_rail_nav_library",
            expectedRoot: "route_library_root",
            in: smokeApp,
            timeout: 10
        )
        let didOpenLibrary = libraryRoot.exists
        let restoredHomeRoot = selectRoute(
            "side_rail_nav_home",
            expectedRoot: "route_home_root",
            in: smokeApp,
            timeout: 10
        )
        let didRestoreHome = restoredHomeRoot.exists
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertTrue(didOpenLibrary, "Library route should open during the route-switch roundtrip")
        XCTAssertTrue(didRestoreHome, "Home route should be restored during the route-switch roundtrip")
        XCTAssertLessThan(elapsed, 30, "Route switching roundtrip should stay within budget")
        XCTAssertTrue(homeRoot.exists, "Home route should remain available after switching away and back")
    }
}
