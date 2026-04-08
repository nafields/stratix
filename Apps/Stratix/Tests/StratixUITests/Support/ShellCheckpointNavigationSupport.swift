// ShellCheckpointNavigationSupport.swift
// Provides shared support for the Stratix / StratixUITests surface.
//

import XCTest

extension ShellCheckpointUITestCase {
    @MainActor
    func waitForFirstGameTile(in app: XCUIApplication, timeout: TimeInterval = 45) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "game_tile_")
        let buttonTile = app.buttons.matching(predicate).firstMatch
        if buttonTile.waitForExistence(timeout: timeout) {
            return buttonTile
        }

        settleUI(0.75)

        let descendantTile = app.descendants(matching: .any).matching(predicate).firstMatch
        if descendantTile.waitForExistence(timeout: 8) {
            return descendantTile
        }

        app.terminate()
        app.launch()
        _ = waitForStoredAuthenticatedHome(in: app)

        let relaunchedTile = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(relaunchedTile.waitForExistence(timeout: timeout), "At least one Game Pass tile must load")
        return relaunchedTile
    }

    @MainActor
    func firstGameTileIfAvailable(in app: XCUIApplication, timeout: TimeInterval = 12) -> XCUIElement? {
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

    @MainActor
    func tryFocusFirstTile(_ tile: XCUIElement, maxAttempts: Int = 10) -> Bool {
        for index in 0..<maxAttempts {
            if tile.hasFocus { return true }
            if index % 4 == 3 {
                XCUIRemote.shared.press(.right)
            } else {
                XCUIRemote.shared.press(.down)
            }
        }
        return tile.hasFocus
    }

    @MainActor
    func focusFirstTile(_ tile: XCUIElement, maxDownPresses: Int = 8) {
        let focused = tryFocusFirstTile(tile, maxAttempts: maxDownPresses)
        XCTAssertTrue(focused, "A Game Pass tile should become focused before navigation actions")
    }

    @MainActor
    func focusedGameTile(in app: XCUIApplication) -> XCUIElement? {
        let tiles = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "game_tile_"))
            .allElementsBoundByIndex
        return tiles.first(where: \.hasFocus)
    }

    @discardableResult
    @MainActor
    func focusAnyGameTile(in app: XCUIApplication, maxAttempts: Int = 24) -> XCUIElement? {
        for index in 0..<maxAttempts {
            if let focused = focusedGameTile(in: app) {
                return focused
            }
            switch index % 6 {
            case 0, 1, 3:
                XCUIRemote.shared.press(.down)
            case 2, 5:
                XCUIRemote.shared.press(.right)
            default:
                XCUIRemote.shared.press(.left)
            }
        }
        return focusedGameTile(in: app)
    }

    @MainActor
    func focusedSideRailNav(in app: XCUIApplication) -> XCUIElement? {
        sideRailNavIDs
            .map { app.buttons[$0] }
            .first(where: { $0.exists && $0.hasFocus })
    }

    @MainActor
    func selectedSideRailNavID(in app: XCUIApplication) -> String? {
        sideRailNavIDs.first { identifier in
            let button = app.buttons[identifier]
            guard button.exists else { return false }
            return (button.value as? String) == "selected"
        }
    }

    @MainActor
    func waitForFocusedSideRailNav(
        in app: XCUIApplication,
        maxLeftPresses: Int = 14
    ) -> XCUIElement? {
        for _ in 0..<maxLeftPresses {
            if let focused = focusedSideRailNav(in: app) {
                return focused
            }
            if let selectedID = selectedSideRailNavID(in: app) {
                let selectedButton = app.buttons[selectedID]
                if selectedButton.exists {
                    return selectedButton
                }
            }
            XCUIRemote.shared.press(.left)
            settleUI(0.08)
        }
        return focusedSideRailNav(in: app) ?? selectedSideRailNavID(in: app).map { app.buttons[$0] }
    }

    @MainActor
    func moveFocusedTileTowardLeftEdge(in app: XCUIApplication, maxLeftPresses: Int = 18) {
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
            if unchangedCount >= 1 { return }
            lastTileID = currentTileID
            XCUIRemote.shared.press(.left)
            settleUI(0.08)
        }
    }

    @MainActor
    func dismissSearchKeyboardIfPresent(in app: XCUIApplication) {
        guard routeRoot("route_search_root", in: app).exists else { return }
        guard focusedGameTile(in: app) == nil, focusedSideRailNav(in: app) == nil else { return }

        for _ in 0..<2 {
            XCUIRemote.shared.press(.menu)
            settleUI(0.35)
            if focusedGameTile(in: app) != nil || focusedSideRailNav(in: app) != nil || !routeRoot("route_search_root", in: app).exists {
                return
            }
        }
    }

    @MainActor
    func selectSideRailNav(_ identifier: String, in app: XCUIApplication) {
        dismissSearchKeyboardIfPresent(in: app)

        let selectedID = selectedSideRailNavID(in: app)

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

        if focusedSideRailNav(in: app) == nil, let firstTile = firstGameTileIfAvailable(in: app) {
            focusFirstTile(firstTile, maxDownPresses: 10)
            moveFocusedTileTowardLeftEdge(in: app, maxLeftPresses: 12)
        } else if focusedSideRailNav(in: app) == nil {
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

    @MainActor
    func openProfileRail(in app: XCUIApplication) {
        if let firstTile = firstGameTileIfAvailable(in: app) {
            focusFirstTile(firstTile, maxDownPresses: 14)
            moveFocusedTileTowardLeftEdge(in: app, maxLeftPresses: 22)
        } else {
            _ = waitForFocusedSideRailNav(in: app, maxLeftPresses: 18)
        }

        for _ in 0..<18 {
            XCUIRemote.shared.press(.left)
            if focusedSideRailNav(in: app) != nil {
                break
            }
        }
        XCUIRemote.shared.press(.left)
        settleUI(0.15)

        let profileButton = app.buttons["side_rail_action_profile_menu"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5), "Profile rail entry should exist")

        for _ in 0..<10 {
            if profileButton.hasFocus { break }
            XCUIRemote.shared.press(.up)
        }

        XCTAssertTrue(profileButton.hasFocus, "Profile rail entry should be focusable before opening")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            routeRoot("route_profile_root", in: app).waitForExistence(timeout: 5),
            "Profile page should open from the account entry"
        )
    }

    @MainActor
    func selectRoute(
        _ identifier: String,
        expectedRoot routeRootIdentifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) -> XCUIElement {
        selectSideRailNav(identifier, in: app)
        return waitForRouteRoot(routeRootIdentifier, in: app, timeout: timeout)
    }

    @MainActor
    func waitForSelectedSideRailNav(
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
        let visibleRoutes = [
            "home": routeRoot("route_home_root", in: app).exists,
            "library": routeRoot("route_library_root", in: app).exists,
            "search": routeRoot("route_search_root", in: app).exists,
            "consoles": routeRoot("route_consoles_root", in: app).exists,
            "profile": routeRoot("route_profile_root", in: app).exists,
            "settings": routeRoot("route_settings_root", in: app).exists,
            "detail": routeRoot("route_detail_root", in: app).exists
        ]
        XCTFail(
            "SideRail nav '\(identifier)' should be selected, found value '\(String(describing: navButton.value))' (current selected: \(currentSelected), routes: \(visibleRoutes))"
        )
    }

    @MainActor
    func waitForFocus(
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
}
