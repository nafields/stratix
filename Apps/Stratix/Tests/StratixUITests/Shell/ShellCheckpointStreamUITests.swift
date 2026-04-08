// ShellCheckpointStreamUITests.swift
// Exercises shell checkpoint stream behavior.
//

import XCTest

final class ShellCheckpointStreamUITests: ShellCheckpointUITestCase {
    @MainActor
    func testStreamExitCompletionMarkerFollowsHomeVisibilityAndFocusRestore() throws {
        let smokeApp = try relaunchForRealDataSmoke(
            arguments: [
                "-stratix-app-logs",
                "-stratix-uitest-force-live-home-refresh",
                "-stratix-uitest-stream-disconnect-focus",
                "-stratix-uitest-stream-runtime-probe",
                "-debug_stream_frame_probe", "YES"
            ]
        )
        XCTAssertTrue(smokeApp.windows.firstMatch.waitForExistence(timeout: 12), "Home roundtrip smoke app window must load")

        _ = waitForStoredAuthenticatedHomeMerchandisingReady(in: smokeApp, timeout: 60)
        let playNow = smokeApp.buttons["home_carousel_play"]
        XCTAssertTrue(playNow.waitForExistence(timeout: 45), "Home carousel Play Now CTA should appear after background refresh")
        XCTAssertTrue(waitForFocus(on: playNow, timeout: 20), "Home carousel Play Now CTA should take focus once merchandising is ready")

        XCUIRemote.shared.press(.select)

        waitForConnectedVideoFrames(in: smokeApp, timeout: 90)

        let restoredHomeRoot = disconnectLiveStreamAndAssertHomeVisibilityBeforeCompletionMarker(
            in: smokeApp,
            timeout: 45
        )
        XCTAssertTrue(restoredHomeRoot.exists, "Home route should be visible before the stream exit completion marker is treated as final proof")
        waitForSelectedSideRailNav("side_rail_nav_home", in: smokeApp, timeout: 12)
    }
}
