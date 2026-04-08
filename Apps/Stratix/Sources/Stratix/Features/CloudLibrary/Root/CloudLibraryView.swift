// CloudLibraryView.swift
// Defines the top-level CloudLibrary root that wires controllers into shell, detail, and stream presentation.
//

import SwiftUI
import DiagnosticsKit
import StratixCore
import StratixModels
import OSLog
import os.signpost

// MARK: - Cloud Library View

/// Owns the app-side CloudLibrary state graph and mounts the main authenticated browse shell.
struct CloudLibraryView: View {
    static let debugQuickLaunchProductID = ProductID("9NZQPT0MWTD0")
    static let uiLogger = GLogger(category: .ui)
    private static let perfLogger = Logger(subsystem: "com.stratix.app", category: "CloudLibraryPerf")
    private static let perfSignpostLog = OSLog(subsystem: "com.stratix.app", category: "CloudLibraryPerf")
    
    @Environment(LibraryController.self) private var libraryController
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SessionController.self) private var sessionController
    @Environment(AchievementsController.self) var achievementsController
    @Environment(ConsoleController.self) private var consoleController
    @Environment(ProfileController.self) private var profileController
    @Environment(StreamController.self) private var streamController
    @Environment(PreviewExportController.self) private var previewExportController
    @State var vm = CloudLibraryViewModel()
    @State var sceneModel = CloudLibrarySceneModel()
    @State var routeState = CloudLibraryRouteState()
    @State var focusState = CloudLibraryFocusState()
    @State private var presentationStore = CloudLibraryPresentationStore()

    @State var queryState = LibraryQueryState()
    @State var activeStreamContext: StreamContext?
    @State var pendingDebugQuickLaunchProductID: ProductID?
    private let layoutPolicy = CloudLibraryLayoutPolicy()
    private let backActionPolicy = CloudLibraryBackActionPolicy()
    private let shellInteractionCoordinator = CloudLibraryShellInteractionCoordinator()
    private let loadStateBuilder = CloudLibraryLoadStateBuilder()
    private let actionCoordinator = CloudLibraryActionCoordinator()

    struct RootShellVisibility: Equatable {
        let opacity: Double
        let allowsHitTesting: Bool
        let isAccessibilityHidden: Bool
    }
    // MARK: - Body

    /// Mounts the shell and presents the full-screen stream surface when a launch succeeds.
    var body: some View {
        mountedShell
        .fullScreenCover(item: $activeStreamContext, onDismiss: handleActiveStreamDismissed) { ctx in
            StreamControllerInputHost(onOverlayToggle: {
                streamController.requestOverlayToggle()
            }) {
                StreamView(context: ctx)
            }
            .ignoresSafeArea()
            .interactiveDismissDisabled(true)
        }
    }

    /// Builds the routed shell host with the current controller snapshots and refresh closures.
    private var mountedShell: some View {
        let visibility = Self.rootShellVisibility(
            isStreamPriorityModeActive: streamController.isStreamPriorityModeActive
        )

        return CloudLibraryShellHost(
            settingsStore: settingsStore,
            routeState: routeState,
            focusState: focusState,
            presentationStore: presentationStore,
            layoutPolicy: layoutPolicy,
            backActionPolicy: backActionPolicy,
            shellInteractionCoordinator: shellInteractionCoordinator,
            stateSnapshot: stateSnapshot,
            loadState: loadState,
            sceneModel: sceneModel,
            queryState: $queryState,
            selectedSettingsPane: selectedSettingsPaneBinding,
            viewModel: vm,
            profileSnapshot: profileShellSnapshot,
            libraryStatus: libraryShellStatus,
            consoleCount: consoleInventory.count,
            regionOverrideDiagnostics: streamRegionOverrideDiagnostics,
            launchCloudStream: launchCloudStream,
            refreshCloudLibrary: refreshCloudLibrary,
            refreshConsoles: refreshConsoles,
            refreshProfile: refreshProfileData,
            refreshFriends: refreshFriends,
            signOut: signOutFromShell,
            exportPreviewDump: exportPreviewDataDump,
            loadDetail: { productID in
                await libraryController.loadDetail(productID: productID)
            },
            loadAchievements: { titleID in
                await achievementsController.loadTitleAchievements(titleID: titleID)
            },
            productDetail: { productID in
                libraryController.productDetail(productID: productID)
            },
            achievementSnapshot: { titleID in
                achievementsController.titleAchievementSnapshot(titleID: titleID)
            },
            achievementErrorText: { titleID in
                achievementsController.lastTitleAchievementsError(titleID: titleID)
            }
        )
        .opacity(visibility.opacity)
        .allowsHitTesting(visibility.allowsHitTesting)
        .accessibilityHidden(visibility.isAccessibilityHidden)
        .overlay(alignment: .topLeading) {
            CloudLibraryDiagnosticsOverlay(
                browseRouteRawValue: routeState.browseRoute.rawValue,
                homeLoadStateValue: loadState.diagnosticsValue,
                routeRestoreStateValue: routeState.restoreDiagnosticsValue,
                homeMerchandisingReady: homeMerchandisingReady,
                homeMerchandisingStateValue: sceneModel.statusState.homeMerchandisingStateValue
            )
        }
        .onChange(of: stateSnapshot.sections) { oldSections, newSections in
            handleSectionRefresh(oldSections: oldSections, newSections: newSections)
            attemptPendingDebugQuickLaunch()
        }
        .task(id: sceneModel.sceneMutationTaskID(
            libraryStateInputs: stateSnapshot,
            queryState: queryState,
            showsContinueBadge: quickResumeTile
        )) {
            shellInteractionCoordinator.applySceneMutation(
                sceneModel: sceneModel,
                stateSnapshot: stateSnapshot,
                queryState: queryState,
                quickResumeTile: quickResumeTile,
                viewModel: vm
            )
        }
        .task(id: sceneModel.statusMutationTaskID(
            isHomeRoute: routeState.browseRoute == .home,
            loadState: loadState,
            sections: stateSnapshot.sections,
            hasCompletedInitialHomeMerchandising: stateSnapshot.hasCompletedInitialHomeMerchandising,
            hasRecoveredLiveHomeMerchandisingThisSession: stateSnapshot.hasRecoveredLiveHomeMerchandisingThisSession,
            hasHomeMerchandisingSnapshot: stateSnapshot.hasHomeMerchandisingSnapshot,
            homeState: vm.cachedHomeState
        )) {
            shellInteractionCoordinator.applyStatusMutation(
                sceneModel: sceneModel,
                routeState: routeState,
                loadState: loadState,
                stateSnapshot: stateSnapshot,
                viewModel: vm
            )
        }
        .task(id: sceneModel.routeMutationTaskID(
            browseRouteRawValue: routeState.browseRoute.rawValue,
            utilityRouteRawValue: routeState.utilityRoute?.rawValue
        )) {
            shellInteractionCoordinator.applyRouteMutation(
                sceneModel: sceneModel,
                routeState: routeState
            )
        }
        .task(id: vm.heroBackgroundTaskID(
            browseRouteRawValue: routeState.browseRoute.rawValue,
            utilityRouteVisible: routeState.utilityRoute != nil,
            detailTitleID: routeState.detailPath.last,
            homeFocusedTitleID: focusState.settledHeroTileID(for: .home),
            libraryFocusedTitleID: focusState.settledHeroTileID(for: .library)
        )) {
            shellInteractionCoordinator.rebuildHeroBackgroundContext(
                viewModel: vm,
                routeState: routeState,
                focusState: focusState
            )
        }
        .task(id: vm.cachedHeroBackgroundContext.taskID) {
            shellInteractionCoordinator.applyHeroBackgroundMutation(
                sceneModel: sceneModel,
                viewModel: vm
            )
        }
        .onChange(of: vm.cachedHomeState, initial: true) { oldState, newState in
            logHomeStateTransition(oldState: oldState, newState: newState)
        }
        .onChange(of: achievementsController.titleAchievementSnapshots) { _, _ in
            invalidateDetailCacheForChangedInputs()
        }
        .onChange(of: achievementsController.lastTitleAchievementsErrorByTitleID) { _, _ in
            invalidateDetailCacheForChangedInputs()
        }
    }

    /// Hides the browse shell while the stream-priority mode owns the screen.
    static func rootShellVisibility(isStreamPriorityModeActive: Bool) -> RootShellVisibility {
        if isStreamPriorityModeActive {
            return .init(
                opacity: 0,
                allowsHitTesting: false,
                isAccessibilityHidden: true
            )
        }

        return .init(
            opacity: 1,
            allowsHitTesting: true,
            isAccessibilityHidden: false
        )
    }

    /// Captures the current library-controller state as a value snapshot for app-side shaping.
    var stateSnapshot: CloudLibraryStateSnapshot {
        CloudLibraryStateSnapshot(state: libraryController.state)
    }

    private var libraryShellStatus: LibraryShellStatusSnapshot {
        libraryController.libraryShellStatusSnapshot()
    }

    private var profileShellSnapshot: ProfileShellSnapshot {
        profileController.profileShellSnapshot()
    }

    private var consoleInventory: ConsoleInventorySnapshot {
        consoleController.consoleInventorySnapshot()
    }

    private var streamRegionOverrideDiagnostics: String? {
        streamController.regionOverrideDiagnostics(for: settingsStore.stream.regionOverride)
    }

    /// Converts the live library snapshot into the shell-facing load-state envelope.
    private var loadState: CloudLibraryLoadState {
        loadStateBuilder.makeLoadState(from: stateSnapshot)
    }

    private var selectedSettingsPaneBinding: Binding<CloudLibrarySettingsPane> {
        Binding(
            get: {
                CloudLibrarySettingsPane(rawValue: settingsStore.shell.lastSettingsCategoryRawValue) ?? .overview
            },
            set: { pane in
                var shell = settingsStore.shell
                shell.lastSettingsCategoryRawValue = pane.rawValue
                settingsStore.shell = shell
            }
        )
    }

    private var quickResumeTile: Bool {
        settingsStore.shell.quickResumeTile
    }

    private var homeMerchandisingReady: Bool {
        sceneModel.statusState.homeMerchandisingReady
    }

    // MARK: - Streaming

    func launchCloudStream(titleId: TitleID, source: String) {
        Task { @MainActor in
            await actionCoordinator.launchCloudStream(
                titleId: titleId,
                source: source,
                currentActiveStreamContext: { activeStreamContext },
                setActiveStreamContext: { activeStreamContext = $0 },
                enterPriorityMode: { await streamController.enterStreamPriorityMode(context: $0) },
                trackEvent: { metadata in
                    UXAnalyticsTracker.shared.track(event: "stream_launch", metadata: metadata)
                },
                trackFirstPlayIfNeeded: {
                    UXAnalyticsTracker.shared.trackFirstPlayIfNeeded()
                }
            )
        }
    }

    private func handleActiveStreamDismissed() {
        Task { @MainActor in
            await actionCoordinator.handleStreamDismiss(
                browseRoute: routeState.browseRoute,
                stopStreaming: { await streamController.stopStreaming() },
                exitPriorityMode: { await streamController.exitStreamPriorityMode() },
                requestTopContentFocus: { focusState.requestTopContentFocus(for: $0) }
            )
        }
    }

    // MARK: - Data Loading

    func refreshCloudLibrary(forceRefresh: Bool) async {
        await actionCoordinator.refreshCloudLibrary(
            forceRefresh: forceRefresh,
            libraryService: libraryController
        )
    }

    private func refreshConsoles() async {
        await actionCoordinator.refreshConsoles(
            consoleService: consoleController
        )
    }

    private func refreshProfileData() async {
        await actionCoordinator.refreshProfile(
            profileService: profileController
        )
    }

    private func refreshFriends() async {
        await actionCoordinator.refreshFriends(
            profileService: profileController
        )
    }

    private func signOutFromShell() async {
        await actionCoordinator.signOut(
            routeState: routeState,
            focusState: focusState,
            presentationStore: presentationStore,
            signOutAction: { await sessionController.signOut() }
        )
    }

    private func exportPreviewDataDump() async -> String {
        await actionCoordinator.exportPreviewDataDump(
            previewExportController: previewExportController
        )
    }

    // MARK: - Debug

    private static func perfLog(_ message: @autoclosure @escaping () -> String) {
        #if DEBUG
        perfLogger.log("\(message(), privacy: .public)")
        #endif
    }
}

#if DEBUG
#Preview("CloudLibraryView", traits: .fixedLayout(width: 1920, height: 1080)) {
    let settingsStore = StratixPreviewStores.makeSettingsStore(
        profileName: "stratix-preview",
        initialSettingsCategory: CloudLibrarySettingsPane.overview.rawValue
    )
    let coordinator = StratixPreviewStores.makeCoordinator(settingsStore: settingsStore)
    return CloudLibraryView()
        .environment(coordinator.libraryController)
        .environment(coordinator.sessionController)
        .environment(coordinator.achievementsController)
        .environment(coordinator.consoleController)
        .environment(coordinator.profileController)
        .environment(coordinator.streamController)
        .environment(coordinator.settingsStore)
        .environment(coordinator.previewExportController)
}
#endif
