// ShellCheckpointLandmarkSupport.swift
// Provides shared support for the Stratix / StratixUITests surface.
//

import XCTest

extension ShellCheckpointUITestCase {
    @MainActor
    func routeRoot(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        return query.firstMatch
    }

    @MainActor
    func diagnosticsMarker(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    func waitForDiagnosticsMarker(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) -> XCUIElement {
        let marker = diagnosticsMarker(identifier, in: app)
        XCTAssertTrue(marker.waitForExistence(timeout: timeout), "Diagnostics marker '\(identifier)' should exist")
        return marker
    }

    @MainActor
    func diagnosticsMarkerValue(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) -> String {
        let marker = waitForDiagnosticsMarker(identifier, in: app, timeout: timeout)
        return marker.value as? String ?? "missing_value"
    }

    @MainActor
    func diagnosticsMarkerValueIfPresent(
        _ identifier: String,
        in app: XCUIApplication
    ) -> String {
        let marker = diagnosticsMarker(identifier, in: app)
        guard marker.exists else { return "missing" }
        return marker.value as? String ?? "missing_value"
    }

    @MainActor
    func homeReadinessDiagnostics(in app: XCUIApplication) -> String {
        [
            "home_merchandising_state=\(diagnosticsMarkerValueIfPresent("home_merchandising_state", in: app))",
            "home_load_state=\(diagnosticsMarkerValueIfPresent("home_load_state", in: app))",
            "browse_route_state=\(diagnosticsMarkerValueIfPresent("browse_route_state", in: app))",
            "route_restore_state=\(diagnosticsMarkerValueIfPresent("route_restore_state", in: app))"
        ].joined(separator: " ")
    }

    @MainActor
    func waitForRouteRoot(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) -> XCUIElement {
        let root = routeRoot(identifier, in: app)
        XCTAssertTrue(root.waitForExistence(timeout: timeout), "Route root '\(identifier)' should exist")
        return root
    }

    @MainActor
    func waitForStoredAuthenticatedShell(
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) -> Bool {
        let authRoot = routeRoot("auth_root", in: app)
        let readyMarker = app.staticTexts.matching(identifier: "shell_ready").firstMatch
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if authRoot.exists {
                XCTFail("Stored auth is required for real-data smoke coverage, but the app presented sign-in instead of restoring a session.")
                return false
            }

            if readyMarker.exists {
                return true
            }

            settleUI(0.25)
        }

        XCTFail("Authenticated shell did not publish shell_ready within \(timeout) seconds. \(homeReadinessDiagnostics(in: app))")
        return false
    }

    @MainActor
    func waitForStoredAuthenticatedShellReadyBeforeRouteLandmarks(
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) -> Bool {
        let authRoot = routeRoot("auth_root", in: app)
        let readyMarker = app.staticTexts.matching(identifier: "shell_ready").firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var sawReadyMarker = false

        while Date() < deadline {
            if authRoot.exists {
                XCTFail("Stored auth is required for real-data smoke coverage, but the app presented sign-in instead of restoring a session.")
                return false
            }

            if readyMarker.exists {
                sawReadyMarker = true
            }

            if let visibleRouteID = primaryRouteRootIDs.first(where: { routeRoot($0, in: app).exists }) {
                if !sawReadyMarker {
                    XCTFail("Route root '\(visibleRouteID)' appeared before shell_ready. \(homeReadinessDiagnostics(in: app))")
                    return false
                }
                return true
            }

            settleUI(0.25)
        }

        XCTFail("Authenticated shell did not publish shell_ready before route landmarks within \(timeout) seconds. \(homeReadinessDiagnostics(in: app))")
        return false
    }

    @MainActor
    func waitForStoredAuthenticatedHome(
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) -> XCUIElement {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 12), "Real-data app window must load")
        XCTAssertTrue(waitForStoredAuthenticatedShell(in: app, timeout: timeout), "Real-data tests require a stored authenticated session")

        let homeRoot = routeRoot("route_home_root", in: app)
        let deadline = Date().addingTimeInterval(timeout)
        var homeSelectionRetryCount = 0

        while Date() < deadline {
            if homeRoot.exists {
                return homeRoot
            }

            let selectedNavID = selectedSideRailNavID(in: app)
            if selectedNavID == "side_rail_nav_home" {
                if homeSelectionRetryCount == 0 {
                    settleUI(0.5)
                    homeSelectionRetryCount += 1
                    continue
                }

                if homeSelectionRetryCount == 1,
                   app.buttons["side_rail_nav_home"].waitForExistence(timeout: 1.5) {
                    selectSideRailNav("side_rail_nav_home", in: app)
                    settleUI(0.5)
                    homeSelectionRetryCount += 1
                    continue
                }

                XCTFail(
                    "Home navigation was selected but route_home_root did not appear. \(homeReadinessDiagnostics(in: app))"
                )
                return homeRoot
            }

            homeSelectionRetryCount = 0

            guard app.buttons["side_rail_nav_home"].waitForExistence(timeout: 2) else {
                settleUI(0.25)
                continue
            }

            let canDriveBackHome =
                focusedGameTile(in: app) != nil ||
                focusedSideRailNav(in: app) != nil ||
                selectedNavID != nil

            if canDriveBackHome {
                selectSideRailNav("side_rail_nav_home", in: app)
            } else {
                settleUI(0.25)
            }
        }

        XCTFail("Authenticated shell did not reach Home within \(timeout) seconds.")
        return homeRoot
    }

    @MainActor
    func waitForStoredAuthenticatedHomeMerchandisingReady(
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) -> XCUIElement {
        let homeRoot = waitForStoredAuthenticatedHome(in: app, timeout: timeout)
        _ = waitForHomeLiveFreshState(in: app, timeout: timeout)
        _ = waitForHomeMerchandisingReadyMarker(in: app, timeout: timeout)
        waitForSelectedSideRailNav("side_rail_nav_home", in: app, timeout: 10)
        let playNow = app.buttons["home_carousel_play"]
        XCTAssertTrue(
            playNow.waitForExistence(timeout: min(timeout, 20)),
            "Home Play Now CTA should exist after the merchandising-ready gate. \(homeReadinessDiagnostics(in: app))"
        )
        XCTAssertTrue(
            waitForFocus(on: playNow, timeout: min(timeout, 20)),
            "Home Play Now CTA should become focused after the merchandising-ready gate. \(homeReadinessDiagnostics(in: app))"
        )
        return homeRoot
    }

    @MainActor
    func waitForHomeLiveFreshState(
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let loadState = diagnosticsMarkerValueIfPresent("home_load_state", in: app)
            if loadState == "liveFresh" {
                return loadState
            }
            settleUI(0.25)
        }

        let finalState = diagnosticsMarkerValueIfPresent("home_load_state", in: app)
        XCTFail("Home should reach liveFresh before capture. \(homeReadinessDiagnostics(in: app)) final_state=\(finalState)")
        return finalState
    }

    @MainActor
    func waitForPostStreamHomeDeltaReady(
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) -> XCUIElement {
        _ = waitForStreamExitCompletionMarker(in: app, timeout: timeout)
        let homeRoot = waitForRouteRoot("route_home_root", in: app, timeout: timeout)
        _ = waitForHomeMerchandisingReadyMarker(in: app, timeout: timeout)
        return homeRoot
    }

    @MainActor
    func homeContinueSignalCount(in app: XCUIApplication) -> Int {
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

    @MainActor
    func waitForHomeContinueSignals(in app: XCUIApplication, timeout: TimeInterval = 30) -> Int {
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

    @MainActor
    func waitForSearchField(
        in app: XCUIApplication,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        let candidates = [
            app.searchFields["Search cloud titles"],
            app.searchFields.firstMatch,
            app.textFields["Search cloud titles"],
            app.textFields.firstMatch
        ]

        while Date() < deadline {
            if let field = candidates.first(where: \.exists) {
                return field
            }
            settleUI(0.25)
        }

        XCTFail("Search field did not appear on the real search route.")
        return app.searchFields.firstMatch
    }

    @MainActor
    func focusSearchField(
        _ searchField: XCUIElement,
        in app: XCUIApplication,
        maxRightPresses: Int = 8,
        maxVerticalPresses: Int = 8
    ) {
        if waitForFocus(on: searchField, timeout: 4) {
            return
        }

        if (focusedSideRailNav(in: app)?.identifier == "side_rail_nav_search") || app.buttons["side_rail_nav_search"].hasFocus {
            for _ in 0..<maxRightPresses {
                XCUIRemote.shared.press(.right)
                if waitForFocus(on: searchField, timeout: 0.5) {
                    return
                }
            }
        }

        for _ in 0..<maxVerticalPresses {
            XCUIRemote.shared.press(.up)
            if waitForFocus(on: searchField, timeout: 0.35) {
                return
            }
        }

        for _ in 0..<maxVerticalPresses {
            XCUIRemote.shared.press(.down)
            if waitForFocus(on: searchField, timeout: 0.35) {
                return
            }
        }

        for _ in 0..<4 {
            XCUIRemote.shared.press(.left)
            if waitForFocus(on: searchField, timeout: 0.35) {
                return
            }
            XCUIRemote.shared.press(.right)
            if waitForFocus(on: searchField, timeout: 0.35) {
                return
            }
        }

        XCTAssertTrue(searchField.hasFocus, "Search field should become focused before entering a live query")
    }

    @MainActor
    func liveSearchQuerySeed(from label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if let token = tokens.first(where: { $0.count >= 3 }) {
            return String(token.prefix(6))
        }

        let scalarFallback = trimmed.filter { $0.isLetter || $0.isNumber }
        return String(scalarFallback.prefix(4))
    }

    @MainActor
    func waitForElementValue(
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
                let satisfied = requiredFragments.allSatisfy { normalizedValue.contains($0.lowercased()) }
                if satisfied {
                    return latestValue
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return latestValue
    }

    @MainActor
    func runtimeMarkerText(for element: XCUIElement) -> String? {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }

        let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    @MainActor
    func waitForChangedElementValue(
        _ element: XCUIElement,
        from originalValue: String?,
        timeout: TimeInterval
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestValue = originalValue

        while Date() < deadline {
            latestValue = element.value as? String
            if latestValue != originalValue, let latestValue, !latestValue.isEmpty {
                return latestValue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return latestValue
    }

    @MainActor
    func waitForElementToDisappear(
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

    @MainActor
    func waitForHomeMerchandisingReadyMarker(
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) -> XCUIElement {
        let stateMarker = app.descendants(matching: .any)
            .matching(identifier: "home_merchandising_state")
            .firstMatch
        let hasStateMarker = stateMarker.waitForExistence(timeout: min(timeout, 5))
        let stateValue = hasStateMarker
            ? (stateMarker.value as? String ?? "missing_value")
            : "missing"
        let marker = app.descendants(matching: .any)
            .matching(identifier: "home_merchandising_ready")
            .firstMatch
        XCTAssertTrue(
            marker.waitForExistence(timeout: timeout),
            "Home should publish a readiness marker once real merchandising has recovered. \(homeReadinessDiagnostics(in: app)) current_state=\(stateValue)"
        )
        XCTAssertEqual(
            marker.value as? String,
            "ready",
            "Home merchandising readiness marker should report ready. \(homeReadinessDiagnostics(in: app)) current_state=\(stateValue)"
        )
        return marker
    }
}
