// ShellCheckpointLaunchSupport.swift
// Provides shared support for the Stratix / StratixUITests surface.
//

import XCTest

enum UITestBrowseRoute: String {
    case home
    case library
    case search
    case consoles
}

extension ShellCheckpointUITestCase {
    @MainActor
    func captureCheckpoint(named name: String, in app: XCUIApplication) throws {
        _ = app.windows.firstMatch.waitForExistence(timeout: 2)

        let environment = ProcessInfo.processInfo.environment
        let environmentOverride =
            environment["STRATIX_CHECKPOINT_DIR"]
            ?? environment["STRATIX_SHELL_CAPTURE_DIR"]
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let defaultDirectory = (cachesDirectory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("stratix-shell-checkpoints", isDirectory: true)
        let candidateDirectories: [URL] = {
            if let environmentOverride, !environmentOverride.isEmpty {
                let overrideURL = URL(fileURLWithPath: environmentOverride, isDirectory: true)
                return [overrideURL, defaultDirectory]
            }
            return [defaultDirectory]
        }()

        var selectedDirectoryURL: URL?
        for directoryURL in candidateDirectories {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let probeURL = directoryURL.appendingPathComponent(".write_probe")
                try Data("probe".utf8).write(to: probeURL, options: .atomic)
                try? FileManager.default.removeItem(at: probeURL)
                selectedDirectoryURL = directoryURL
                break
            } catch {
                continue
            }
        }

        guard let directoryURL = selectedDirectoryURL else {
            throw NSError(
                domain: "ShellCheckpointUITestCase",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No writable checkpoint directory was available."]
            )
        }

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "checkpoint_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let checkpointURL = directoryURL.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: checkpointURL, options: .atomic)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: checkpointURL.path),
            "Expected checkpoint capture at \(checkpointURL.path)"
        )
    }

    @MainActor
    func settleUI(_ duration: TimeInterval = 0.35) {
        let expectation = XCTestExpectation(description: "Settle UI")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            expectation.fulfill()
        }
        _ = XCTWaiter.wait(for: [expectation], timeout: duration + 1.0)
    }

    @MainActor
    func launchApp(arguments: [String], environment: [String: String] = [:]) -> XCUIApplication {
        let launchedApp = XCUIApplication()
        launchedApp.launchArguments = arguments
        launchedApp.launchEnvironment = environment
        launchedApp.launch()
        return launchedApp
    }

    @MainActor
    func relaunchForRealDataSmoke(
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> XCUIApplication {
        app.terminate()
        app.launchArguments = mergedLaunchArguments(arguments, browseRoute: .home)
        app.launchEnvironment = environment
        app.launch()
        try skipStoredAuthDependentSmokeIfUnavailable(in: app)
        _ = waitForStoredAuthenticatedHome(in: app)
        return app
    }

    @MainActor
    func relaunchForStoredAuthenticatedShell(
        arguments: [String] = [],
        environment: [String: String] = [:],
        browseRoute: UITestBrowseRoute? = nil,
        waitForShellLandmarks: Bool = true
    ) throws -> XCUIApplication {
        app.terminate()
        app.launchArguments = mergedLaunchArguments(arguments, browseRoute: browseRoute)
        app.launchEnvironment = environment
        app.launch()
        try skipStoredAuthDependentSmokeIfUnavailable(in: app)
        if waitForShellLandmarks {
            XCTAssertTrue(waitForStoredAuthenticatedShell(in: app), "Real-data tests require a stored authenticated session")
        }
        return app
    }

    @MainActor
    func skipStoredAuthDependentSmokeIfUnavailable(
        in app: XCUIApplication,
        timeout: TimeInterval = 4
    ) throws {
        guard !isRunningOnPhysicalDevice else { return }
        guard app.windows.firstMatch.waitForExistence(timeout: min(timeout, 12)) else { return }

        let authRoot = routeRoot("auth_root", in: app)
        if authRoot.waitForExistence(timeout: timeout) {
            throw XCTSkip("Stored-auth shell smoke requires a preserved authenticated session. Simulator proof skips when no stored session exists; hardware-device validation owns this coverage.")
        }
    }

    @MainActor
    func relaunchForShellHarness(
        arguments: [String] = [],
        browseRoute: UITestBrowseRoute
    ) -> XCUIApplication {
        app.terminate()
        app.launchArguments = mergedLaunchArguments(["-stratix-uitest-shell"] + arguments, browseRoute: browseRoute)
        app.launchEnvironment = [:]
        app.launch()
        return app
    }

    @MainActor
    func relaunchForGamePassHomeHarness() -> XCUIApplication {
        app.terminate()
        app.launchArguments = ["-stratix-uitest-gamepass-home"]
        app.launchEnvironment = ["STRATIX_UI_TEST_GAMEPASS_HOME": "1"]
        app.launch()
        return app
    }

    @MainActor
    func mergedLaunchArguments(
        _ arguments: [String],
        browseRoute: UITestBrowseRoute?
    ) -> [String] {
        guard let browseRoute else { return arguments }
        guard !arguments.contains("-stratix-uitest-browse-route") else { return arguments }
        return ["-stratix-uitest-browse-route", browseRoute.rawValue] + arguments
    }
}
