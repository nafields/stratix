// CloudLibraryShellHostTests.swift
// Exercises cloud library shell host behavior.
//

import XCTest
import SwiftUI
import StratixModels
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryShellHostTests: XCTestCase {
    @MainActor
    func testShellHostBootstrapsStoredRouteAndRequestsInitialFocus() {
        let harness = makeHarness()
        let shell = harness.host()

        harness.settingsStore.shell = .init(
            rememberLastSection: true,
            lastDestinationRawValue: CloudLibraryBrowseRoute.library.rawValue
        )

        shell.bootstrapShell()

        XCTAssertEqual(harness.routeState.browseRoute, .library)
        XCTAssertFalse(harness.focusState.hasRequestedInitialContentFocus)
    }

    @MainActor
    func testShellHostHandlesBackByApplyingBackActionPolicy() {
        let harness = makeHarness()
        let shell = harness.host()

        harness.routeState.openUtilityRoute(.settings)
        shell.handleBack()
        XCTAssertNil(harness.routeState.utilityRoute)

        harness.routeState.setBrowseRoute(.library)
        harness.routeState.pushDetail(TitleID(rawValue: "detail-title"))
        shell.handleBack()
        XCTAssertTrue(harness.routeState.detailPath.isEmpty)

        harness.routeState.setBrowseRoute(.library)
        shell.handleBack()
        XCTAssertEqual(harness.routeState.browseRoute, .home)

        harness.focusState.isSideRailExpanded = false
        shell.handleBack()
        XCTAssertTrue(harness.focusState.isSideRailExpanded)
    }

    @MainActor
    func testShellHostHandlesSettingsShortcutWithoutOuterViewLogic() {
        let harness = makeHarness(selectedSettingsPane: .diagnostics)
        let shell = harness.host()

        shell.handleSettingsShortcut()

        XCTAssertEqual(harness.routeState.utilityRoute, .settings)
        XCTAssertEqual(harness.selectedSettingsPaneBox.value, .overview)
    }

    @MainActor
    func testShellHostSelectsCorrectContentHostForBrowseUtilityAndDetailStates() {
        let harness = makeHarness()

        XCTAssertEqual(harness.host().contentMode, .browse)

        harness.routeState.openUtilityRoute(.profile)
        XCTAssertEqual(harness.host().contentMode, .utility)

        harness.routeState.closeUtilityRoute()
        harness.routeState.pushDetail(TitleID(rawValue: "detail-title"))
        XCTAssertEqual(harness.host().contentMode, .detail)
    }

    @MainActor
    private func makeHarness(
        selectedSettingsPane: CloudLibrarySettingsPane = .overview
    ) -> ShellHostHarness {
        let settingsStore = CloudLibraryTestSupport.makeSettingsStore()
        return ShellHostHarness(
            settingsStore: settingsStore,
            selectedSettingsPane: selectedSettingsPane
        )
    }
}

@MainActor
private struct ShellHostHarness {
    final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    let settingsStore: SettingsStore
    let routeState = CloudLibraryRouteState()
    let focusState = CloudLibraryFocusState()
    let presentationStore = CloudLibraryPresentationStore()
    let sceneModel = CloudLibrarySceneModel()
    let viewModel = CloudLibraryViewModel()
    let profileSnapshot = CloudLibraryTestSupport.makeProfileController().profileShellSnapshot()
    let libraryStatus = LibraryController(initialState: .empty).libraryShellStatusSnapshot()
    let queryStateBox = Box(LibraryQueryState())
    let selectedSettingsPaneBox: Box<CloudLibrarySettingsPane>

    init(
        settingsStore: SettingsStore,
        selectedSettingsPane: CloudLibrarySettingsPane
    ) {
        self.settingsStore = settingsStore
        self.selectedSettingsPaneBox = Box(selectedSettingsPane)
    }

    func host() -> CloudLibraryShellHost {
        CloudLibraryShellHost(
            settingsStore: settingsStore,
            routeState: routeState,
            focusState: focusState,
            presentationStore: presentationStore,
            layoutPolicy: CloudLibraryLayoutPolicy(),
            backActionPolicy: CloudLibraryBackActionPolicy(),
            shellInteractionCoordinator: CloudLibraryShellInteractionCoordinator(),
            stateSnapshot: CloudLibraryStateSnapshot(state: .empty),
            loadState: .notLoaded,
            sceneModel: sceneModel,
            queryState: Binding(
                get: { queryStateBox.value },
                set: { queryStateBox.value = $0 }
            ),
            selectedSettingsPane: Binding(
                get: { selectedSettingsPaneBox.value },
                set: { selectedSettingsPaneBox.value = $0 }
            ),
            viewModel: viewModel,
            profileSnapshot: profileSnapshot,
            libraryStatus: libraryStatus,
            consoleCount: 0,
            regionOverrideDiagnostics: nil,
            launchCloudStream: { _, _ in },
            refreshCloudLibrary: { _ in },
            refreshConsoles: {},
            refreshProfile: {},
            refreshFriends: {},
            signOut: {},
            exportPreviewDump: { "" },
            loadDetail: { _ in },
            loadAchievements: { _ in },
            productDetail: { _ in nil },
            achievementSnapshot: { _ in nil },
            achievementErrorText: { _ in nil }
        )
    }
}
