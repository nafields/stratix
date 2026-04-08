// CloudLibraryFocusStateTests.swift
// Exercises cloud library focus state behavior.
//

import XCTest
import StratixModels

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryFocusStateTests: XCTestCase {
    @MainActor
    func testSetFocusedTileIDStoresTypedIDPerRoute() {
        let focusState = CloudLibraryFocusState()
        let homeID = TitleID(rawValue: "home-title")
        let searchID = TitleID(rawValue: "search-title")

        focusState.setFocusedTileID(homeID, for: .home)
        focusState.setFocusedTileID(searchID, for: .search)

        XCTAssertEqual(focusState.focusedTileID(for: .home), homeID)
        XCTAssertEqual(focusState.focusedTileID(for: .search), searchID)
        XCTAssertEqual(focusState.focusedTileIDsByRoute[.home], homeID)
        XCTAssertEqual(focusState.focusedTileIDsByRoute[.search], searchID)
    }

    @MainActor
    func testSetSettledHeroTileIDTracksHomeAndLibrarySeparately() {
        let focusState = CloudLibraryFocusState()
        let homeID = TitleID(rawValue: "home-title")
        let libraryID = TitleID(rawValue: "library-title")

        focusState.setSettledHeroTileID(homeID, for: .home)
        focusState.setSettledHeroTileID(libraryID, for: .library)

        XCTAssertEqual(focusState.settledHeroTileID(for: .home), homeID)
        XCTAssertEqual(focusState.settledHeroTileID(for: .library), libraryID)
        XCTAssertEqual(focusState.settledHomeHeroTileID, homeID)
        XCTAssertEqual(focusState.settledLibraryHeroTileID, libraryID)
    }

    @MainActor
    func testRequestTopContentFocusLeavesStoredFocusStateUnchanged() {
        let focusState = CloudLibraryFocusState()
        let homeID = TitleID(rawValue: "home-title")
        focusState.setFocusedTileID(homeID, for: .home)

        focusState.requestTopContentFocus(for: .home)
        focusState.requestTopContentFocus(for: .library)
        focusState.requestTopContentFocus(for: .search)
        focusState.requestTopContentFocus(for: .consoles)

        XCTAssertEqual(focusState.focusedTileID(for: .home), homeID)
    }

    @MainActor
    func testRequestUtilityFocusLeavesSideRailTokensUnchanged() {
        let focusState = CloudLibraryFocusState()
        focusState.isSideRailExpanded = true

        focusState.requestUtilityFocus(for: .profile)
        focusState.requestUtilityFocus(for: .settings)

        XCTAssertTrue(focusState.isSideRailExpanded)
    }

    @MainActor
    func testRequestSideRailEntryAndCollapseToggleExpansionState() {
        let focusState = CloudLibraryFocusState()

        focusState.requestSideRailEntry()
        XCTAssertTrue(focusState.isSideRailExpanded)

        focusState.requestSideRailCollapse()
        XCTAssertFalse(focusState.isSideRailExpanded)
    }
}
