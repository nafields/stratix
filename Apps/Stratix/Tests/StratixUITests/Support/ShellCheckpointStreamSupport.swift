// ShellCheckpointStreamSupport.swift
// Provides shared support for the Stratix / StratixUITests surface.
//

import XCTest

extension ShellCheckpointUITestCase {
    @MainActor
    func waitForStreamRuntimeMarker(
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

    @MainActor
    func waitForConnectedVideoFrames(
        in app: XCUIApplication,
        timeout: TimeInterval = 90
    ) {
        let runtimeMarker = waitForStreamRuntimeMarker(in: app, timeout: timeout)
        var requiredFragments = [
            "session=present",
            "lifecycle=connected",
            "track=attached"
        ]
        let requiresFirstFrameProof = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == nil
        if requiresFirstFrameProof {
            requiredFragments.append("frame=first_frame_rendered")
        }
        let runtimeValue = waitForElementValue(
            runtimeMarker,
            containing: requiredFragments,
            timeout: timeout
        )
        XCTAssertNotNil(
            runtimeValue,
            requiresFirstFrameProof
                ? "Real-device stream validation must report a connected session with attached track and rendered first frame"
                : "Simulator stream validation must report a connected session with an attached WebRTC track in the runtime HUD"
        )
    }

    @MainActor
    func disconnectLiveStreamAndReturnHome(
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) {
        let runtimeMarker = waitForStreamRuntimeMarker(in: app, timeout: 12)
        let overlayValue = waitForStreamOverlayDisconnectArmed(in: app, runtimeMarker: runtimeMarker, timeout: 8)
        XCTAssertNotNil(
            overlayValue,
            "Stream runtime marker should report overlay=visible and disconnect=armed before disconnecting"
        )
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

        _ = waitForStreamExitCompletionMarker(in: app, timeout: timeout)
        XCTAssertTrue(
            waitForElementToDisappear(runtimeMarker, timeout: timeout),
            "Stream runtime marker should disappear after disconnecting and returning to the shell"
        )
        _ = waitForPostStreamHomeDeltaReady(in: app, timeout: timeout)
    }

    @MainActor
    func disconnectLiveStreamAndAssertHomeVisibilityBeforeCompletionMarker(
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) -> XCUIElement {
        let runtimeMarker = waitForStreamRuntimeMarker(in: app, timeout: 12)
        let overlayValue = waitForStreamOverlayDisconnectArmed(in: app, runtimeMarker: runtimeMarker, timeout: 8)
        XCTAssertNotNil(
            overlayValue,
            "Stream runtime marker should report overlay=visible and disconnect=armed before disconnecting"
        )
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

        let homeRoot = waitForHomeVisibilityBeforeStreamExitCompletionMarker(in: app, timeout: timeout)
        _ = waitForStreamExitCompletionMarker(in: app, timeout: timeout)
        XCTAssertTrue(
            waitForElementToDisappear(runtimeMarker, timeout: timeout),
            "Stream runtime marker should disappear after disconnecting and returning to the shell"
        )
        _ = waitForPostStreamHomeDeltaReady(in: app, timeout: timeout)
        return homeRoot
    }

    @MainActor
    func disconnectHarnessStreamAndReturnHome(
        in app: XCUIApplication,
        timeout: TimeInterval = 20
    ) {
        let overlay = app.descendants(matching: .any).matching(identifier: "stream_overlay").firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: timeout), "Deterministic stream overlay should appear after starting the synthetic stream")

        let stopButton = app.descendants(matching: .any).matching(identifier: "stop_streaming").firstMatch
        if stopButton.waitForExistence(timeout: 6) {
            XCTAssertTrue(waitForFocus(on: stopButton, timeout: 8), "Stop Streaming should take focus in the deterministic shell harness")
            XCUIRemote.shared.press(.select)
        } else {
            XCUIRemote.shared.press(.menu)
        }

        XCTAssertTrue(
            waitForElementToDisappear(overlay, timeout: timeout),
            "Deterministic stream overlay should disappear after stopping the synthetic stream"
        )
        XCTAssertTrue(
            routeRoot("route_home_root", in: app).waitForExistence(timeout: timeout),
            "Stopping the deterministic stream should return the shell to the Home route"
        )
    }

    @MainActor
    func revealStreamDisconnectButton(
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

    @MainActor
    func waitForStreamOverlayDisconnectArmed(
        in app: XCUIApplication,
        runtimeMarker: XCUIElement,
        timeout: TimeInterval
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let markerValue = waitForElementValue(
                runtimeMarker,
                containing: ["overlay=visible", "disconnect=armed"],
                timeout: 0.8
            )
            if markerValue != nil {
                return markerValue
            }
            XCUIRemote.shared.press(.playPause)
            settleUI(0.35)
        }

        return runtimeMarkerText(for: runtimeMarker)
    }

    @MainActor
    func waitForStreamExitCompletionMarker(
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) -> XCUIElement {
        let marker = app.descendants(matching: .any)
            .matching(identifier: "stream_exit_complete")
            .firstMatch
        XCTAssertTrue(
            marker.waitForExistence(timeout: timeout),
            "Shell should publish an explicit stream exit completion marker after teardown"
        )
        XCTAssertEqual(
            marker.value as? String,
            "shell_restored",
            "Stream exit completion marker should report a restored shell state"
        )
        return marker
    }

    @MainActor
    func waitForHomeVisibilityBeforeStreamExitCompletionMarker(
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) -> XCUIElement {
        let homeRoot = routeRoot("route_home_root", in: app)
        let homeNav = app.buttons["side_rail_nav_home"]
        let marker = app.descendants(matching: .any)
            .matching(identifier: "stream_exit_complete")
            .firstMatch
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if homeRoot.exists, (homeNav.value as? String) == "selected" {
                return homeRoot
            }

            if marker.exists {
                XCTFail(
                    "Stream exit completion marker appeared before Home visibility and focus restore. \(homeReadinessDiagnostics(in: app))"
                )
                return homeRoot
            }

            settleUI(0.25)
        }

        XCTFail("Home visibility and focus were not restored before the stream exit completion marker.")
        return homeRoot
    }
}
