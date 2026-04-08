// StoredAuthShellRestorePerformanceUITests.swift
// Exercises stored auth shell restore performance behavior.
//

import XCTest

final class StoredAuthShellRestorePerformanceUITests: XCTestCase {
    override nonisolated func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testStoredAuthShellRestoreLatency() throws {
        try PerformanceTestSupport.skipStoredAuthPerformanceIfUnavailableOnSimulator()

        measure(
            metrics: [XCTApplicationLaunchMetric(), XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: makePerformanceMeasureOptions(iterationCount: 3)
        ) {
            let app = PerformanceTestSupport.launchStoredAuthenticatedHomeApp(timeout: 60)
            let homeRoot = PerformanceTestSupport.waitForStoredAuthenticatedHome(in: app, timeout: 60)
            XCTAssertTrue(homeRoot.exists, "Stored-auth restore should land directly in the authenticated shell")
            _ = PerformanceTestSupport.waitForButton(
                in: app,
                identifier: PerformanceTestSupport.homeRailIdentifier,
                timeout: 20
            )

            app.terminate()
        }
    }
}
