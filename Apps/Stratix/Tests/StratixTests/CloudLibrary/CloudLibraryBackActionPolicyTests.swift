// CloudLibraryBackActionPolicyTests.swift
// Exercises cloud library back action policy behavior.
//

import XCTest
import StratixModels

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryBackActionPolicyTests: XCTestCase {
    @MainActor
    func testResolveClosesUtilityRouteFirst() {
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()
        routeState.openUtilityRoute(.settings)

        XCTAssertEqual(
            CloudLibraryBackActionPolicy().resolve(routeState: routeState, focusState: focusState),
            .closeUtilityRoute
        )
    }

    @MainActor
    func testResolvePopsDetailBeforeReturningHome() {
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()
        routeState.setBrowseRoute(.library)
        routeState.pushDetail(TitleID(rawValue: "forza-title"))

        XCTAssertEqual(
            CloudLibraryBackActionPolicy().resolve(routeState: routeState, focusState: focusState),
            .popDetail
        )
    }

    @MainActor
    func testResolveReturnsBrowseHomeWhenOnNonHomeRoute() {
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()
        routeState.setBrowseRoute(.library)

        XCTAssertEqual(
            CloudLibraryBackActionPolicy().resolve(routeState: routeState, focusState: focusState),
            .returnBrowseHome
        )
    }

    @MainActor
    func testResolveEntersSideRailWhenHomeAndCollapsed() {
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()
        focusState.isSideRailExpanded = false

        XCTAssertEqual(
            CloudLibraryBackActionPolicy().resolve(routeState: routeState, focusState: focusState),
            .enterSideRail
        )
    }

    @MainActor
    func testResolveNoOpWhenHomeAndExpandedWithoutDetailOrUtility() {
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()
        focusState.isSideRailExpanded = true

        XCTAssertEqual(
            CloudLibraryBackActionPolicy().resolve(routeState: routeState, focusState: focusState),
            .noOp
        )
    }
}
