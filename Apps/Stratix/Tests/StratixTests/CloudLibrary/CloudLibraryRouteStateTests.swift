// CloudLibraryRouteStateTests.swift
// Exercises cloud library route state behavior.
//

import XCTest
import StratixModels

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryRouteStateTests: XCTestCase {
    @MainActor
    func testRestoreStoredRouteIfNeededUsesOverrideWhenPresent() {
        let settingsStore = CloudLibraryTestSupport.makeSettingsStore()
        let routeState = CloudLibraryRouteState()

        routeState.restoreStoredRouteIfNeeded(
            settingsStore: settingsStore,
            overrideRawValue: CloudLibraryBrowseRoute.library.rawValue
        )

        XCTAssertEqual(routeState.browseRoute, .library)
        XCTAssertTrue(routeState.hasRestoredStoredRoute)
    }

    @MainActor
    func testRestoreStoredRouteIfNeededUsesRememberedRouteWhenAllowed() {
        let settingsStore = CloudLibraryTestSupport.makeSettingsStore()
        var shell = settingsStore.shell
        shell.rememberLastSection = true
        shell.lastDestinationRawValue = CloudLibraryBrowseRoute.search.rawValue
        settingsStore.shell = shell
        let routeState = CloudLibraryRouteState()

        routeState.restoreStoredRouteIfNeeded(settingsStore: settingsStore, overrideRawValue: nil)

        XCTAssertEqual(routeState.browseRoute, .search)
    }

    @MainActor
    func testPersistLastDestinationUpdatesSettingsStore() {
        let settingsStore = CloudLibraryTestSupport.makeSettingsStore()
        let routeState = CloudLibraryRouteState()

        routeState.persistLastDestination(.library, settingsStore: settingsStore)

        XCTAssertEqual(settingsStore.shell.lastDestinationRawValue, CloudLibraryBrowseRoute.library.rawValue)
    }

    @MainActor
    func testPushDetailAppendsTypedTitleID() {
        let routeState = CloudLibraryRouteState()
        let titleID = TitleID(rawValue: "forza-title")

        routeState.pushDetail(titleID)

        XCTAssertEqual(routeState.detailPath.count, 1)
        XCTAssertEqual(routeState.detailPath.last, titleID)
        XCTAssertEqual(routeState.detailPath.map(\.rawValue), ["forza-title"])
    }

    func testAppRouteDetailCarriesTypedTitleID() {
        let titleID = TitleID(rawValue: "typed-detail")
        let route = AppRoute.detail(titleID: titleID)

        switch route {
        case .detail(let storedTitleID):
            XCTAssertEqual(storedTitleID, titleID)
        default:
            XCTFail("Expected typed detail route")
        }
    }

    @MainActor
    func testPopDetailRemovesLastTypedTitleID() {
        let routeState = CloudLibraryRouteState()
        let titleID = TitleID(rawValue: "forza-title")
        routeState.pushDetail(titleID)

        routeState.popDetail()

        XCTAssertTrue(routeState.detailPath.isEmpty)
    }

    @MainActor
    func testReturnHomeClearsDetailPathWithoutStringFallbackHelpers() {
        let routeState = CloudLibraryRouteState()
        routeState.setBrowseRoute(.search)
        routeState.openUtilityRoute(.settings)
        routeState.pushDetail(TitleID(rawValue: "typed-title"))

        routeState.returnHome()

        XCTAssertEqual(routeState.browseRoute, .home)
        XCTAssertNil(routeState.utilityRoute)
        XCTAssertTrue(routeState.detailPath.isEmpty)
    }

    @MainActor
    func testCloseUtilityRouteClearsUtilityRouteOnly() {
        let routeState = CloudLibraryRouteState()
        routeState.setBrowseRoute(.library)
        routeState.openUtilityRoute(.settings)

        routeState.closeUtilityRoute()

        XCTAssertNil(routeState.utilityRoute)
        XCTAssertEqual(routeState.browseRoute, .library)
    }
}
