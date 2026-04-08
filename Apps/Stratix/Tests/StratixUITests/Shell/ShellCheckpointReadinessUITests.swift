// ShellCheckpointReadinessUITests.swift
// Exercises shell checkpoint readiness behavior.
//

import XCTest

final class ShellCheckpointReadinessUITests: ShellCheckpointUITestCase {
    @MainActor
    func testStoredAuthenticatedHomeOverrideWinsOverRememberedRoute() throws {
        let seededApp = try relaunchForStoredAuthenticatedShell(browseRoute: .search)
        XCTAssertTrue(seededApp.windows.firstMatch.waitForExistence(timeout: 12), "Seeded app window must load")
        XCTAssertTrue(waitForStoredAuthenticatedShell(in: seededApp, timeout: 60), "Stored authenticated shell is required")
        XCTAssertTrue(routeRoot("route_search_root", in: seededApp).waitForExistence(timeout: 12), "Search route should exist for remembered-route seeding")
        seededApp.terminate()

        let smokeApp = try relaunchForStoredAuthenticatedShell(browseRoute: .home)
        let homeRoot = waitForStoredAuthenticatedHome(in: smokeApp, timeout: 60)
        XCTAssertTrue(homeRoot.exists, "Home route root should exist after explicit home override")
        XCTAssertEqual(diagnosticsMarkerValue("browse_route_state", in: smokeApp, timeout: 12), "home")
        XCTAssertEqual(diagnosticsMarkerValue("route_restore_state", in: smokeApp, timeout: 12), "override_home")
        waitForSelectedSideRailNav("side_rail_nav_home", in: smokeApp, timeout: 12)
    }

    @MainActor
    func testHomeRouteRootExistsBeforeMerchandisingReady() throws {
        let smokeApp = try relaunchForStoredAuthenticatedShell(browseRoute: .home)
        let homeRoot = waitForStoredAuthenticatedHome(in: smokeApp, timeout: 60)
        XCTAssertTrue(homeRoot.exists, "Home route root should exist before requiring merchandising readiness")
        let merchandisingState = diagnosticsMarkerValue("home_merchandising_state", in: smokeApp, timeout: 12)
        XCTAssertFalse(merchandisingState.isEmpty, "Home should expose merchandising-state diagnostics once the Home route is mounted")

        let readyMarker = smokeApp.staticTexts.matching(identifier: "home_merchandising_ready").firstMatch
        if readyMarker.waitForExistence(timeout: 12) {
            XCTAssertTrue(readyMarker.exists, "If Home becomes merch-ready during the check window, the ready marker should appear")
        } else {
            XCTAssertTrue(homeRoot.exists, "Home route root must remain present even when merchandising is not yet marked ready")
        }
    }

    @MainActor
    func testHomeSideRailSelectionFollowsRouteBeforeMerchandisingReady() throws {
        let smokeApp = try relaunchForStoredAuthenticatedShell(browseRoute: .home)
        let homeRoot = waitForStoredAuthenticatedHome(in: smokeApp, timeout: 60)
        XCTAssertTrue(homeRoot.exists, "Home route root should exist before checking selected side rail state")
        waitForSelectedSideRailNav("side_rail_nav_home", in: smokeApp, timeout: 12)
    }

    @MainActor
    func testHomeLoadStateMarkerAppearsDuringHomeReachability() throws {
        let smokeApp = try relaunchForStoredAuthenticatedShell(browseRoute: .home)
        let homeRoot = waitForStoredAuthenticatedHome(in: smokeApp, timeout: 60)
        XCTAssertTrue(homeRoot.exists, "Home route root should exist")
        let loadState = diagnosticsMarkerValue("home_load_state", in: smokeApp, timeout: 12)
        XCTAssertFalse(loadState.isEmpty, "Home load state marker should expose an operational load-state value")
    }

    @MainActor
    func testRouteRestoreDiagnosticsMarkerShowsOverrideSource() throws {
        let smokeApp = try relaunchForStoredAuthenticatedShell(browseRoute: .home)
        _ = waitForStoredAuthenticatedHome(in: smokeApp, timeout: 60)
        XCTAssertEqual(
            diagnosticsMarkerValue("route_restore_state", in: smokeApp, timeout: 12),
            "override_home",
            "Route restore diagnostics should report the explicit UI-test override source"
        )
    }

    @MainActor
    func testStoredAuthenticatedShellPublishesShellReadyBeforeRouteLandmarks() throws {
        let smokeApp = try relaunchForStoredAuthenticatedShell(
            browseRoute: .home,
            waitForShellLandmarks: false
        )

        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Real-data app window must load")

        XCTAssertTrue(
            waitForStoredAuthenticatedShellReadyBeforeRouteLandmarks(in: smokeApp, timeout: 60),
            "Stored-auth launch should publish shell_ready before any route root becomes visible"
        )
        XCTAssertTrue(
            smokeApp.staticTexts.matching(identifier: "shell_ready").firstMatch.exists,
            "shell_ready marker should exist once the stored-auth shell is ready"
        )
        XCTAssertTrue(
            routeRoot("route_home_root", in: smokeApp).waitForExistence(timeout: 12),
            "Home route root should appear after the shell_ready marker on stored-auth launch"
        )
    }
}
