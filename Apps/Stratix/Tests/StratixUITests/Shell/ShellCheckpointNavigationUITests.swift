// ShellCheckpointNavigationUITests.swift
// Exercises shell checkpoint navigation behavior.
//

import XCTest

final class ShellCheckpointNavigationUITests: ShellCheckpointUITestCase {
    @MainActor
    func testShellNavigationCheckpoints() {
        let appWindow = app.windows.firstMatch
        XCTAssertTrue(
            appWindow.waitForExistence(timeout: 10),
            "App window must appear within 10 seconds"
        )

        let hasNavigableContent =
            app.buttons.count > 0 ||
            app.textFields.count > 0 ||
            app.staticTexts.count > 0

        XCTAssertTrue(
            hasNavigableContent,
            "Shell must render navigable content — app appears blank"
        )

        XCTAssertTrue(app.state == .runningForeground, "App must remain in foreground after launch")
    }

    @MainActor
    func testNoSceneBleedAcrossDestinationSwitches() {
        let appWindow = app.windows.firstMatch
        XCTAssertTrue(
            appWindow.waitForExistence(timeout: 10),
            "App window must appear before testing destination switches"
        )

        let isOnAuthScreen = app.staticTexts["STRATIX"].exists
            || app.buttons.matching(identifier: "sign_in").firstMatch.exists

        if isOnAuthScreen {
            let primaryButtons = app.buttons.allElementsBoundByIndex.filter { $0.isHittable }
            XCTAssertFalse(
                primaryButtons.isEmpty,
                "Auth screen must have at least one hittable button — scene appears blank"
            )
            let streamOverlayExists = app.otherElements["stream_overlay"].exists
                || app.buttons["stop_streaming"].exists
            XCTAssertFalse(
                streamOverlayExists,
                "Stream overlay must not bleed into auth screen — scene isolation violated"
            )
            return
        }

        let tabBar = app.tabBars.firstMatch
        guard tabBar.exists else {
            XCTAssertFalse(
                app.otherElements["stream_overlay"].exists,
                "Stream overlay must not be visible in non-streaming state"
            )
            return
        }

        let tabs = tabBar.buttons.allElementsBoundByIndex
        guard tabs.count >= 2 else { return }

        var previousTabLabel: String?
        for (index, tab) in tabs.prefix(3).enumerated() {
            guard tab.isHittable else { continue }

            let tabLabel = tab.label
            if index > 0 {
                XCUIRemote.shared.press(.right)
            }
            XCUIRemote.shared.press(.select)

            let settled = XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == YES"),
                    object: app.windows.firstMatch
                )],
                timeout: 2
            )
            XCTAssertEqual(settled, .completed, "App must remain stable after tab switch to '\(tabLabel)'")

            XCTAssertFalse(
                app.otherElements["stream_overlay"].exists,
                "Stream overlay must not bleed into '\(tabLabel)' tab — scene isolation violated"
            )

            XCTAssertEqual(
                app.state, .runningForeground,
                "App must remain in foreground after switching from '\(previousTabLabel ?? "initial")' to '\(tabLabel)'"
            )

            previousTabLabel = tabLabel
        }
    }
}
