// AppCoordinator.swift
// Defines the root coordinator that assembles shared controllers and app boot behavior.
//

import Foundation
import Observation
import StratixModels
import StreamingCore
import DiagnosticsKit
import XCloudAPI

public enum CloudLibraryRefreshReason: String, Sendable {
    case startupAuto
    case foregroundResume
    case postStreamResume
    case manualUser
    case backgroundRefresh
    case focusPrefetch
    case detailOpen
}

// MARK: - App Coordinator
//
// Root coordinator that owns auth state, API clients, and streaming session.
// The SwiftUI app observes this object for navigation and state.
// NOTE: AppCoordinator is in extraction-only mode.
// New permanent domain responsibilities must not be added here.
// Prefer dedicated controllers and keep forwarding/composition glue only.

@Observable
@MainActor
/// Holds the top-level app graph and forwards lifecycle work to dedicated controller surfaces.
public final class AppCoordinator: SessionControllerEventSink {
    public let settingsStore: SettingsStore
    public let sessionController: SessionController
    public let libraryController: LibraryController
    public let profileController: ProfileController
    public let consoleController: ConsoleController
    public let streamController: StreamController
    public let shellBootstrapController: ShellBootstrapController
    public let inputController: InputController
    public let achievementsController: AchievementsController
    public let previewExportController: PreviewExportController
    let streamPriorityShellController: AppStreamPriorityShellController
    private let profileControllerServices: AppProfileControllerServices
    private let achievementsControllerServices: AppAchievementsControllerServices
    private let libraryControllerServices: AppLibraryControllerServices
    private let streamControllerServices: AppStreamControllerServices
    private let lifecycleCoordinator: any AppLifecycleHandling
    private let shellBootCoordinator: any AppShellBootHandling

    // MARK: - Init

    /// Builds the default app graph for the live app target.
    public convenience init(settingsStore: SettingsStore = SettingsStore()) {
        self.init(graph: AppControllerBuilder.make(settingsStore: settingsStore))
    }

    /// Installs an already-built controller graph and optional override coordinators for tests.
    init(
        graph: AppControllerGraph,
        lifecycleCoordinator: (any AppLifecycleHandling)? = nil,
        shellBootCoordinator: (any AppShellBootHandling)? = nil
    ) {
        self.settingsStore = graph.settingsStore
        self.sessionController = graph.sessionController
        self.libraryController = graph.libraryController
        self.profileController = graph.profileController
        self.consoleController = graph.consoleController
        self.streamController = graph.streamController
        self.shellBootstrapController = graph.shellBootstrapController
        self.inputController = graph.inputController
        self.achievementsController = graph.achievementsController
        self.previewExportController = graph.previewExportController
        self.streamPriorityShellController = graph.streamPriorityShellController
        self.profileControllerServices = graph.profileControllerServices
        self.achievementsControllerServices = graph.achievementsControllerServices
        self.libraryControllerServices = graph.libraryControllerServices
        self.streamControllerServices = graph.streamControllerServices
        self.lifecycleCoordinator = lifecycleCoordinator ?? graph.lifecycleCoordinator
        self.shellBootCoordinator = shellBootCoordinator ?? graph.shellBootCoordinator
        if self.settingsStore.didMigrateLegacyStatsHUDThisLaunch {
            GLogger(category: .auth).info("Migrated legacy stats HUD setting to guide.show_stream_stats")
        }
        sessionController.attach(self)
        libraryController.attach(libraryControllerServices)
        profileController.attach(profileControllerServices)
        consoleController.attach(sessionController)
        streamController.attach(streamControllerServices)
        inputController.attach(streamController)
        achievementsController.attach(achievementsControllerServices)
    }

    // MARK: - Startup

    /// Starts the normal foreground app boot sequence.
    public func onAppear() async {
        await lifecycleCoordinator.onAppear()
    }

    /// Handles app re-entry after the system marks the app active again.
    public func handleAppDidBecomeActive() async {
        await lifecycleCoordinator.handleAppDidBecomeActive()
    }

    /// Runs the background refresh path and reports whether coordinator-owned state changed.
    public func performBackgroundAppRefresh() async -> Bool {
        await lifecycleCoordinator.performBackgroundAppRefresh()
    }

    /// Clears app-owned session state after a controller-driven sign-out event.
    func handleSessionDidSignOutFromController() async {
        await lifecycleCoordinator.handleSessionDidSignOut()
    }

    /// Starts shell boot hydration after a full token application succeeds.
    func handleSessionDidAuthenticateFromController(
        tokens _: StreamTokens,
        mode: SessionTokenApplyMode
    ) async {
        guard mode == .full else { return }
        await shellBootCoordinator.beginShellBootHydrationIfNeeded(restoreCachesBeforeBoot: true)
    }

    /// Triggers shell boot hydration when callers need to guarantee hydrated shell state explicitly.
    public func beginShellBootHydrationIfNeeded() async {
        await shellBootCoordinator.beginShellBootHydrationIfNeeded(restoreCachesBeforeBoot: true)
    }
}
