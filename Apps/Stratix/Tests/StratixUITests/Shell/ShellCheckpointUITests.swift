// ShellCheckpointUITests.swift
// Exercises shell checkpoint behavior.
//

import XCTest

class ShellCheckpointUITestCase: XCTestCase {
    var app: XCUIApplication!
    let sideRailNavIDs = [
        "side_rail_nav_search",
        "side_rail_nav_home",
        "side_rail_nav_library",
        "side_rail_nav_consoles"
    ]
    let primaryRouteRootIDs = [
        "route_home_root",
        "route_library_root",
        "route_search_root",
        "route_consoles_root",
        "route_profile_root",
        "route_settings_root",
        "route_detail_root"
    ]

    var isRunningOnPhysicalDevice: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil
    }

    override nonisolated func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = MainActor.assumeIsolated {
            let app = XCUIApplication()
            app.launchArguments += ["-stratix-uitest-shell"]
            app.launch()
            return app
        }
    }

    override nonisolated func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }
}
