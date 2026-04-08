// ShellPerformanceUITests.swift
// Exercises shell performance behavior.
//

import XCTest

final class ShellPerformanceUITests: XCTestCase {
    override nonisolated func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testStoredAuthHomeLibraryRouteSwitchLatency() throws {
        try PerformanceTestSupport.skipStoredAuthPerformanceIfUnavailableOnSimulator()
        let launchedApp = PerformanceTestSupport.launchStoredAuthenticatedHomeApp(timeout: 60)
        defer { launchedApp.terminate() }

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: makePerformanceMeasureOptions(iterationCount: 5)
        ) {
            _ = PerformanceTestSupport.selectRoute(
                PerformanceTestSupport.libraryRailIdentifier,
                expectedRoot: PerformanceTestSupport.libraryRouteIdentifier,
                in: launchedApp,
                timeout: 20
            )
            _ = PerformanceTestSupport.selectRoute(
                PerformanceTestSupport.homeRailIdentifier,
                expectedRoot: PerformanceTestSupport.homeRouteIdentifier,
                in: launchedApp,
                timeout: 20
            )
        }
    }

    @MainActor
    func testShellHarnessHomePlayNowRoundtripLatency() throws {
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: makePerformanceMeasureOptions(iterationCount: 3)
        ) {
            let launchedApp = PerformanceTestSupport.launchShellHarnessHomeApp(timeout: 12)
            let playNow = PerformanceTestSupport.waitForButton(
                in: launchedApp,
                identifier: "home_carousel_play",
                timeout: 20
            )
            XCTAssertTrue(
                PerformanceTestSupport.waitForFocus(on: playNow, timeout: 20),
                "Deterministic Home Play Now CTA should take focus before the measured shell roundtrip"
            )

            XCUIRemote.shared.press(.select)

            PerformanceTestSupport.disconnectHarnessStreamAndReturnHome(in: launchedApp, timeout: 20)

            launchedApp.terminate()
        }
    }
}
