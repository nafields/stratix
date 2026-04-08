// CloudLibraryHomeFocusCoordinatorTests.swift
// Exercises cloud library home focus coordinator behavior.
//

import XCTest
import StratixModels

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryHomeFocusCoordinatorTests: XCTestCase {
    func testPreferredTitleID_returnsTypedTitleIDForKnownTitle() {
        let titleID = TitleID(rawValue: "known-title")
        let tile = MediaTileViewState(id: "tile-1", titleID: titleID, title: "Known")
        let entry = CloudLibraryHomeScreen.TileLookupEntry(sectionID: "home", tile: tile, titleID: titleID)

        XCTAssertEqual(
            CloudLibraryHomeFocusCoordinator.preferredTitleID(
                for: titleID,
                tileLookup: [titleID: entry]
            ),
            titleID
        )
    }

    func testLookupEntry_returnsEntryForMatchingTitleID() {
        let titleID = TitleID(rawValue: "known-title")
        let tile = MediaTileViewState(id: "tile-1", titleID: titleID, title: "Known")
        let entry = CloudLibraryHomeScreen.TileLookupEntry(sectionID: "home", tile: tile, titleID: titleID)

        XCTAssertEqual(
            CloudLibraryHomeFocusCoordinator.lookupEntry(
                for: titleID,
                tileLookup: [titleID: entry]
            )?.titleID,
            titleID
        )
        XCTAssertEqual(
            CloudLibraryHomeFocusCoordinator.lookupEntry(
                for: titleID,
                tileLookup: [titleID: entry]
            )?.sectionID,
            "home"
        )
    }
}
