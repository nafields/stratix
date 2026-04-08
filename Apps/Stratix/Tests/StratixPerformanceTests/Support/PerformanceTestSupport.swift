// PerformanceTestSupport.swift
// Provides shared support for the Stratix / StratixPerformanceTests surface.
//

import XCTest

func makePerformanceMeasureOptions(iterationCount: Int) -> XCTMeasureOptions {
    let options = XCTMeasureOptions()
    options.iterationCount = iterationCount
    return options
}

@MainActor
enum PerformanceTestSupport {
    static let defaultLaunchArguments = ["--uitesting", "--skip-auth"]
    static let storedAuthenticatedHomeLaunchArguments = ["-stratix-uitest-browse-route", "home"]
    static let shellHarnessHomeLaunchArguments = ["-stratix-uitest-shell", "-stratix-uitest-browse-route", "home"]
    static let homeRailIdentifier = "side_rail_nav_home"
    static let libraryRailIdentifier = "side_rail_nav_library"
    static let searchRailIdentifier = "side_rail_nav_search"
    static let consolesRailIdentifier = "side_rail_nav_consoles"
    static let jumpBackInRailIdentifier = "jump_back_in_rail"
    static let homeRouteIdentifier = "route_home_root"
    static let libraryRouteIdentifier = "route_library_root"
    static let searchRouteIdentifier = "route_search_root"
    static let consolesRouteIdentifier = "route_consoles_root"
    static let profileRouteIdentifier = "route_profile_root"
    static let settingsRouteIdentifier = "route_settings_root"
    static let detailRouteIdentifier = "route_detail_root"
    static let sideRailNavIDs = [
        searchRailIdentifier,
        homeRailIdentifier,
        libraryRailIdentifier,
        consolesRailIdentifier
    ]
    static let primaryRouteRootIDs = [
        homeRouteIdentifier,
        libraryRouteIdentifier,
        searchRouteIdentifier,
        consolesRouteIdentifier,
        profileRouteIdentifier,
        settingsRouteIdentifier,
        detailRouteIdentifier
    ]
    static var isRunningOnPhysicalDevice: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil
    }

    static func makeApp(
        additionalLaunchArguments: [String] = [],
        launchEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = defaultLaunchArguments + additionalLaunchArguments
        app.launchEnvironment = launchEnvironment
        return app
    }

    @discardableResult
    static func launchApp(
        additionalLaunchArguments: [String] = [],
        launchEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = makeApp(
            additionalLaunchArguments: additionalLaunchArguments,
            launchEnvironment: launchEnvironment
        )
        app.launch()
        return app
    }

    @discardableResult
    static func launchStoredAuthenticatedHomeApp(
        additionalLaunchArguments: [String] = [],
        launchEnvironment: [String: String] = [:],
        timeout: TimeInterval = 60
    ) -> XCUIApplication {
        let app = makeApp(
            additionalLaunchArguments: storedAuthenticatedHomeLaunchArguments + additionalLaunchArguments,
            launchEnvironment: launchEnvironment
        )
        app.launch()
        _ = waitForStoredAuthenticatedHome(in: app, timeout: timeout)
        return app
    }

    static func skipStoredAuthPerformanceIfUnavailableOnSimulator(timeout: TimeInterval = 12) throws {
        guard !isRunningOnPhysicalDevice else { return }

        let app = makeApp(additionalLaunchArguments: storedAuthenticatedHomeLaunchArguments)
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: timeout), "Stored-auth performance preflight window must load")
        let authRoot = routeRoot("auth_root", in: app)
        if authRoot.waitForExistence(timeout: 4) {
            throw XCTSkip("Stored-auth performance coverage requires a preserved authenticated simulator session. Deterministic simulator performance coverage still runs; real stored-auth proof stays on device-owned lanes.")
        }
    }

    @discardableResult
    static func launchShellHarnessHomeApp(
        additionalLaunchArguments: [String] = [],
        timeout: TimeInterval = 12
    ) -> XCUIApplication {
        let app = makeApp(additionalLaunchArguments: shellHarnessHomeLaunchArguments + additionalLaunchArguments)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: timeout), "Shell harness window should load")
        _ = waitForRouteRoot(homeRouteIdentifier, in: app, timeout: timeout)
        return app
    }

    static func waitForButton(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: timeout) {
            return button
        }

        let descendant = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
        if descendant.waitForExistence(timeout: timeout) {
            return descendant
        }

        XCTFail("Expected button '\(identifier)' to exist")
        return button
    }

    static func routeRoot(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    static func waitForRouteRoot(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) -> XCUIElement {
        let root = routeRoot(identifier, in: app)
        XCTAssertTrue(root.waitForExistence(timeout: timeout), "Route root '\(identifier)' should exist")
        return root
    }

    static func firstGameTileIfAvailable(
        in app: XCUIApplication,
        timeout: TimeInterval = 12
    ) -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "game_tile_")
        let buttonTile = app.buttons.matching(predicate).firstMatch
        if buttonTile.waitForExistence(timeout: timeout) {
            return buttonTile
        }

        settleUI(0.75)

        let descendantTile = app.descendants(matching: .any).matching(predicate).firstMatch
        if descendantTile.waitForExistence(timeout: 6) {
            return descendantTile
        }

        return nil
    }

    static func tryFocusFirstTile(_ tile: XCUIElement, maxAttempts: Int = 10) -> Bool {
        for index in 0..<maxAttempts {
            if tile.hasFocus {
                return true
            }
            if index % 4 == 3 {
                XCUIRemote.shared.press(.right)
            } else {
                XCUIRemote.shared.press(.down)
            }
        }
        return tile.hasFocus
    }

    static func focusFirstTile(_ tile: XCUIElement, maxDownPresses: Int = 8) {
        let focused = tryFocusFirstTile(tile, maxAttempts: maxDownPresses)
        XCTAssertTrue(focused, "A Game Pass tile should become focused before navigation actions")
    }

    static func focusedGameTile(in app: XCUIApplication) -> XCUIElement? {
        let tiles = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "game_tile_"))
            .allElementsBoundByIndex
        return tiles.first(where: \.hasFocus)
    }

    static func focusedSideRailNav(in app: XCUIApplication) -> XCUIElement? {
        sideRailNavIDs
            .map { app.buttons[$0] }
            .first(where: { $0.exists && $0.hasFocus })
    }

    static func selectedSideRailNavID(in app: XCUIApplication) -> String? {
        sideRailNavIDs.first { identifier in
            let button = app.buttons[identifier]
            guard button.exists else { return false }
            return (button.value as? String) == "selected"
        }
    }

    static func waitForFocusedSideRailNav(
        in app: XCUIApplication,
        maxLeftPresses: Int = 14
    ) -> XCUIElement? {
        for _ in 0..<maxLeftPresses {
            if let focused = focusedSideRailNav(in: app) {
                return focused
            }
            XCUIRemote.shared.press(.left)
            settleUI(0.08)
        }
        return focusedSideRailNav(in: app)
    }

    static func moveFocusedTileTowardLeftEdge(
        in app: XCUIApplication,
        maxLeftPresses: Int = 18
    ) {
        var lastTileID: String?
        var unchangedCount = 0

        for _ in 0..<maxLeftPresses {
            guard let focusedTile = focusedGameTile(in: app) else { return }
            let currentTileID = focusedTile.identifier
            if currentTileID == lastTileID {
                unchangedCount += 1
            } else {
                unchangedCount = 0
            }
            if unchangedCount >= 1 {
                return
            }
            lastTileID = currentTileID
            XCUIRemote.shared.press(.left)
            settleUI(0.08)
        }
    }

    static func dismissSearchKeyboardIfPresent(in app: XCUIApplication) {
        guard routeRoot(searchRouteIdentifier, in: app).exists else { return }
        guard focusedGameTile(in: app) == nil, focusedSideRailNav(in: app) == nil else { return }

        for _ in 0..<2 {
            XCUIRemote.shared.press(.menu)
            settleUI(0.35)
            if focusedGameTile(in: app) != nil ||
                focusedSideRailNav(in: app) != nil ||
                !routeRoot("route_search_root", in: app).exists {
                return
            }
        }
    }

    static func waitForSelectedSideRailNav(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3
    ) {
        let navButton = app.buttons[identifier]
        XCTAssertTrue(navButton.waitForExistence(timeout: timeout), "SideRail nav '\(identifier)' must exist")
        if (navButton.value as? String) == "selected" {
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (navButton.value as? String) == "selected" {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let currentSelected = sideRailNavIDs.first { candidate in
            (app.buttons[candidate].value as? String) == "selected"
        } ?? "none"
        XCTFail(
            "SideRail nav '\(identifier)' should be selected, found value '\(String(describing: navButton.value))' (current selected: \(currentSelected))"
        )
    }

    static func selectSideRailNav(_ identifier: String, in app: XCUIApplication) {
        dismissSearchKeyboardIfPresent(in: app)

        let selectedID = selectedSideRailNavID(in: app)
        let hasSideRailAnchor =
            focusedSideRailNav(in: app) != nil ||
            selectedID != nil

        if let selectedID {
            let selectedButton = app.buttons[selectedID]
            for _ in 0..<6 {
                if selectedButton.hasFocus {
                    break
                }
                XCUIRemote.shared.press(.left)
                settleUI(0.03)
            }
        }

        if focusedSideRailNav(in: app) == nil && !hasSideRailAnchor, let firstTile = firstGameTileIfAvailable(in: app) {
            focusFirstTile(firstTile, maxDownPresses: 10)
            moveFocusedTileTowardLeftEdge(in: app, maxLeftPresses: 12)
        } else if focusedSideRailNav(in: app) == nil && !hasSideRailAnchor {
            _ = waitForFocusedSideRailNav(in: app, maxLeftPresses: 10)
        }
        XCUIRemote.shared.press(.left)
        settleUI(0.05)
        for _ in 0..<6 {
            if focusedSideRailNav(in: app) != nil {
                break
            }
            XCUIRemote.shared.press(.left)
            settleUI(0.03)
        }

        XCUIRemote.shared.press(.left)
        settleUI(0.05)

        let navButton = app.buttons[identifier]
        guard navButton.exists else {
            XCTFail("SideRail nav '\(identifier)' must exist")
            return
        }

        if !navButton.hasFocus {
            let targetIndex = sideRailNavIDs.firstIndex(of: identifier)
            for _ in 0..<(sideRailNavIDs.count + 2) {
                if navButton.hasFocus {
                    break
                }
                guard
                    let currentFocusedID = focusedSideRailNav(in: app)?.identifier ?? selectedSideRailNavID(in: app),
                    let currentIndex = sideRailNavIDs.firstIndex(of: currentFocusedID),
                    let targetIndex
                else {
                    XCUIRemote.shared.press(.up)
                    settleUI(0.03)
                    continue
                }
                XCUIRemote.shared.press(targetIndex > currentIndex ? .down : .up)
                settleUI(0.03)
            }
        }

        if !navButton.hasFocus {
            for _ in 0..<(sideRailNavIDs.count + 2) {
                XCUIRemote.shared.press(.down)
                settleUI(0.03)
                if navButton.hasFocus {
                    break
                }
            }
        }

        if !navButton.hasFocus {
            for _ in 0..<(sideRailNavIDs.count + 2) {
                XCUIRemote.shared.press(.up)
                settleUI(0.03)
                if navButton.hasFocus {
                    break
                }
            }
        }

        if !navButton.hasFocus {
            for _ in 0..<4 {
                XCUIRemote.shared.press(.left)
                settleUI(0.03)
                if navButton.hasFocus {
                    break
                }
                XCUIRemote.shared.press(.down)
                settleUI(0.03)
                if navButton.hasFocus {
                    break
                }
            }
        }

        XCTAssertTrue(navButton.hasFocus, "Could not focus side-rail nav '\(identifier)' before selecting")
        XCUIRemote.shared.press(.select)
        waitForSelectedSideRailNav(identifier, in: app)
    }

    @discardableResult
    static func selectRoute(
        _ identifier: String,
        expectedRoot routeRootIdentifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) -> XCUIElement {
        selectSideRailNav(identifier, in: app)
        return waitForRouteRoot(routeRootIdentifier, in: app, timeout: timeout)
    }

    static func waitForStoredAuthenticatedShell(
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) -> Bool {
        let authRoot = routeRoot("auth_root", in: app)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if authRoot.exists {
                XCTFail("Stored auth is required for real-data performance coverage, but the app presented sign-in instead of restoring a session.")
                return false
            }

            if primaryRouteRootIDs.contains(where: { routeRoot($0, in: app).exists }) {
                return true
            }

            if selectedSideRailNavID(in: app) != nil {
                return true
            }

            if app.buttons["home_carousel_play"].exists {
                return true
            }

            settleUI(0.25)
        }

        XCTFail("Authenticated shell did not become ready within \(timeout) seconds.")
        return false
    }

    @discardableResult
    static func waitForStoredAuthenticatedHome(
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) -> XCUIElement {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 12), "Stored-auth performance app window must load")
        XCTAssertTrue(waitForStoredAuthenticatedShell(in: app, timeout: timeout), "Real-data performance tests require a stored authenticated session")

        let homeRoot = routeRoot(homeRouteIdentifier, in: app)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if homeRoot.exists {
                return homeRoot
            }

            let selectedNavID = selectedSideRailNavID(in: app)
            if selectedNavID == homeRailIdentifier {
                settleUI(0.25)
                continue
            }

            guard app.buttons[homeRailIdentifier].waitForExistence(timeout: 2) else {
                settleUI(0.25)
                continue
            }

            let canDriveBackHome =
                focusedGameTile(in: app) != nil ||
                focusedSideRailNav(in: app) != nil ||
                selectedNavID != nil

            if canDriveBackHome {
                selectSideRailNav(homeRailIdentifier, in: app)
            } else {
                settleUI(0.25)
            }
        }

        XCTFail("Authenticated shell did not reach Home within \(timeout) seconds.")
        return homeRoot
    }

    static func waitForFocus(
        on element: XCUIElement,
        timeout: TimeInterval = 12
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.hasFocus {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.exists && element.hasFocus
    }

    static func settleUI(_ duration: TimeInterval = 0.35) {
        let expectation = XCTestExpectation(description: "Settle UI")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            expectation.fulfill()
        }
        _ = XCTWaiter.wait(for: [expectation], timeout: duration + 1.0)
    }

    static func runtimeMarkerText(for element: XCUIElement) -> String? {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }

        let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    static func waitForElementValue(
        _ element: XCUIElement,
        containing requiredFragments: [String],
        timeout: TimeInterval
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestValue: String?

        while Date() < deadline {
            latestValue = runtimeMarkerText(for: element)
            if let latestValue {
                let normalizedValue = latestValue.lowercased()
                if requiredFragments.allSatisfy({ normalizedValue.contains($0.lowercased()) }) {
                    return latestValue
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return latestValue
    }

    static func waitForElementToDisappear(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return !element.exists
    }

    static func waitForStreamRuntimeMarker(
        in app: XCUIApplication,
        timeout: TimeInterval = 45
    ) -> XCUIElement {
        let probe = app.descendants(matching: .any).matching(identifier: "stream_runtime_probe").firstMatch
        if probe.waitForExistence(timeout: min(timeout, 8)) {
            return probe
        }

        let marker = app.descendants(matching: .any).matching(identifier: "stream_runtime_status").firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: timeout), "Stream runtime status marker should appear once a real stream starts")
        return marker
    }

    static func waitForConnectedVideoFrames(
        in app: XCUIApplication,
        timeout: TimeInterval = 90
    ) {
        let runtimeMarker = waitForStreamRuntimeMarker(in: app, timeout: timeout)
        var requiredFragments = [
            "session=present",
            "lifecycle=connected",
            "track=attached"
        ]
        if ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil {
            requiredFragments.append("frame=first_frame_rendered")
        }

        let runtimeValue = waitForElementValue(runtimeMarker, containing: requiredFragments, timeout: timeout)
        XCTAssertNotNil(runtimeValue, "Stream runtime HUD should prove a connected session with attached video, plus a rendered first frame on hardware")
    }

    static func disconnectLiveStreamAndReturnHome(
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) {
        let runtimeMarker = waitForStreamRuntimeMarker(in: app, timeout: 12)
        let disconnectButton = revealStreamDisconnectButton(in: app, timeout: 8)

        if !waitForFocus(on: disconnectButton, timeout: 4) {
            for _ in 0..<8 {
                XCUIRemote.shared.press(.down)
                if disconnectButton.hasFocus {
                    break
                }
                XCUIRemote.shared.press(.up)
                if disconnectButton.hasFocus {
                    break
                }
            }
        }

        XCTAssertTrue(disconnectButton.hasFocus, "Disconnect button should become focused before exiting a live stream")
        XCUIRemote.shared.press(.select)

        XCTAssertTrue(
            waitForElementToDisappear(runtimeMarker, timeout: timeout),
            "Stream runtime marker should disappear after disconnecting and returning to the shell"
        )

        _ = waitForStoredAuthenticatedHome(in: app, timeout: timeout)
    }

    static func disconnectHarnessStreamAndReturnHome(
        in app: XCUIApplication,
        timeout: TimeInterval = 20
    ) {
        let overlay = app.descendants(matching: .any).matching(identifier: "stream_overlay").firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: timeout), "Deterministic shell harness should display the synthetic stream overlay")

        let stopButton = app.buttons["stop_streaming"].exists
            ? app.buttons["stop_streaming"]
            : app.descendants(matching: .any).matching(identifier: "stop_streaming").firstMatch
        if stopButton.waitForExistence(timeout: 6) {
            XCTAssertTrue(waitForFocus(on: stopButton, timeout: 8), "Synthetic stream stop control should take focus before exit")
            XCUIRemote.shared.press(.select)
        } else {
            XCUIRemote.shared.press(.menu)
        }

        XCTAssertTrue(
            waitForElementToDisappear(overlay, timeout: timeout),
            "Synthetic stream overlay should disappear after stopping the deterministic stream"
        )
        XCTAssertTrue(
            routeRoot(homeRouteIdentifier, in: app).waitForExistence(timeout: timeout),
            "Stopping the deterministic stream should return to the Home route"
        )
    }

    static func revealStreamDisconnectButton(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement {
        let disconnectButton = app.buttons["stream_disconnect_button"]
        guard !disconnectButton.exists else { return disconnectButton }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            XCUIRemote.shared.press(.playPause)
            if disconnectButton.waitForExistence(timeout: 1.5) {
                return disconnectButton
            }
            settleUI(0.35)
        }

        XCTFail("Disconnect button should appear after opening the stream overlay")
        return disconnectButton
    }

    static func homeContinueSignalCount(in app: XCUIApplication) -> Int {
        let continueSignals = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Continue", "Resume")
        )
        let badgeSignals = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "game_tile_badge_")
        )
        let buttonSignals = app.buttons.matching(
            NSPredicate(
                format: """
                label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR value CONTAINS[c] %@ OR value CONTAINS[c] %@
                """,
                "Continue",
                "Resume",
                "Continue",
                "Resume"
            )
        )
        return max(continueSignals.count, badgeSignals.count, buttonSignals.count)
    }

    static func waitForHomeContinueSignals(
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var latestCount = 0

        while Date() < deadline {
            latestCount = homeContinueSignalCount(in: app)
            if latestCount > 0 {
                return latestCount
            }
            settleUI(0.25)
        }

        return latestCount
    }
}
