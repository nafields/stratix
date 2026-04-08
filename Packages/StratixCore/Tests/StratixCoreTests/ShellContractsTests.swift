// ShellContractsTests.swift
// Exercises shell contracts behavior.
//

import XCTest
@testable import StratixCore

final class ShellContractsTests: XCTestCase {

    // MARK: - BackActionResolver (shell)

    func testMainShellBackActionClosesOverlayFirst() {
        let action = BackActionResolver.resolveMainShellBackAction(
            overlayRoute: .guide,
            selectedSection: .consoles,
            previousSection: .gamePass
        )
        XCTAssertEqual(action, .closeOverlay)
    }

    func testMainShellBackActionClosesProfileOverlay() {
        let action = BackActionResolver.resolveMainShellBackAction(
            overlayRoute: .profile,
            selectedSection: .gamePass,
            previousSection: .gamePass
        )
        XCTAssertEqual(action, .closeOverlay)
    }

    func testMainShellBackActionReturnsToPreviousSection() {
        let action = BackActionResolver.resolveMainShellBackAction(
            overlayRoute: .none,
            selectedSection: .consoles,
            previousSection: .gamePass
        )
        XCTAssertEqual(action, .returnToPreviousSection)
    }

    func testMainShellBackActionNoOpOnGamePassBaseState() {
        let action = BackActionResolver.resolveMainShellBackAction(
            overlayRoute: .none,
            selectedSection: .gamePass,
            previousSection: .gamePass
        )
        XCTAssertEqual(action, .none)
    }

    func testMainShellBackActionNoOpWhenSectionUnchanged() {
        let action = BackActionResolver.resolveMainShellBackAction(
            overlayRoute: .none,
            selectedSection: .consoles,
            previousSection: .consoles
        )
        XCTAssertEqual(action, .none)
    }

    // MARK: - AppShellSection

    func testAppShellSectionIdentifiable() {
        XCTAssertEqual(AppShellSection.gamePass.id, "gamePass")
        XCTAssertEqual(AppShellSection.consoles.id, "consoles")
    }

    func testAppShellSectionTitles() {
        XCTAssertEqual(AppShellSection.gamePass.title, "Game Pass")
        XCTAssertEqual(AppShellSection.consoles.title, "My Consoles")
    }

    func testAppShellSectionSystemImages() {
        XCTAssertEqual(AppShellSection.gamePass.systemImage, "cloud.fill")
        XCTAssertEqual(AppShellSection.consoles.systemImage, "tv.fill")
    }

    func testAppShellSectionCaseCount() {
        XCTAssertEqual(AppShellSection.allCases.count, 2)
    }
}
