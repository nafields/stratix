// AppControllerServices.swift
// Defines app controller services for the App / Composition surface.
//

import DiagnosticsKit
import Foundation
import Metal
import StratixModels
import StreamingCore
import XCloudAPI
import VideoRenderingKit

@MainActor
final class AppNetworkSessionProvider {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func session() -> URLSession {
        settingsStore.diagnostics.blockTracking ? XCloudAPIClient.makeBlockingSession() : .shared
    }
}

extension SessionController: ConsoleControllerDependencies {
    func authenticatedConsoleTokens() -> StreamTokens? {
        guard case .authenticated(let tokens) = authState else { return nil }
        return tokens
    }
}

@MainActor
final class AppProfileControllerServices: ProfileControllerDependencies {
    private let sessionController: SessionController
    private let settingsStore: SettingsStore
    private let networkSessionProvider: AppNetworkSessionProvider

    init(
        sessionController: SessionController,
        settingsStore: SettingsStore,
        networkSessionProvider: AppNetworkSessionProvider
    ) {
        self.sessionController = sessionController
        self.settingsStore = settingsStore
        self.networkSessionProvider = networkSessionProvider
    }

    func xboxWebCredentials(logContext: String) async -> XboxWebCredentials? {
        await sessionController.xboxWebCredentials(logContext: logContext)
    }

    func apiSession() -> URLSession {
        networkSessionProvider.session()
    }

    func updateProfileSettings(name: String?, imageURLString: String?) {
        settingsStore.updateProfile(name: name, imageURLString: imageURLString)
    }
}

@MainActor
final class AppAchievementsControllerServices: AchievementsControllerDependencies {
    private let sessionController: SessionController
    private let profileController: ProfileController
    private let libraryController: LibraryController
    private let networkSessionProvider: AppNetworkSessionProvider

    init(
        sessionController: SessionController,
        profileController: ProfileController,
        libraryController: LibraryController,
        networkSessionProvider: AppNetworkSessionProvider
    ) {
        self.sessionController = sessionController
        self.profileController = profileController
        self.libraryController = libraryController
        self.networkSessionProvider = networkSessionProvider
    }

    func xboxWebCredentials(logContext: String) async -> XboxWebCredentials? {
        await sessionController.xboxWebCredentials(logContext: logContext)
    }

    func apiSession() -> URLSession {
        networkSessionProvider.session()
    }

    func currentUserProfileXUID() -> String? {
        profileController.currentUserProfile?.xuid?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentUserPresenceXUID() -> String? {
        profileController.currentUserPresence?.xuid?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cacheCurrentUserProfile(_ profile: XboxCurrentUserProfile) {
        profileController.setCurrentUserProfile(profile)
    }

    func cacheCurrentUserPresence(_ presence: XboxCurrentUserPresence) {
        profileController.setCurrentUserPresence(presence)
    }

    func upsertAchievementSummary(_ summary: TitleAchievementSummary) {
        libraryController.upsertAchievementSummary(summary)
    }
}

@MainActor
final class AppLibraryControllerServices: LibraryControllerDependencies {
    private let sessionController: SessionController
    private let profileController: ProfileController
    private let achievementsController: AchievementsController

    init(
        sessionController: SessionController,
        profileController: ProfileController,
        achievementsController: AchievementsController
    ) {
        self.sessionController = sessionController
        self.profileController = profileController
        self.achievementsController = achievementsController
    }

    func authenticatedLibraryTokens() -> StreamTokens? {
        guard case .authenticated(let tokens) = sessionController.authState else { return nil }
        return tokens
    }

    func refreshStreamTokens(logContext: String) async throws -> StreamTokens {
        try await sessionController.refreshStreamTokens(logContext: logContext)
    }

    func xboxWebCredentials(logContext: String) async -> XboxWebCredentials? {
        await sessionController.xboxWebCredentials(logContext: logContext)
    }

    func achievementSnapshot(titleID: TitleID) -> TitleAchievementSnapshot? {
        achievementsController.titleAchievementSnapshot(titleID: titleID)
    }

    func loadCurrentUserProfile() async {
        await profileController.loadCurrentUserProfile()
    }

    func loadSocialPeople(maxItems: Int) async {
        await profileController.loadSocialPeople(maxItems: maxItems)
    }
}

extension StreamController: InputControllerDependencies {
    func currentStreamingSession() -> (any StreamingSessionFacade)? {
        state.streamingSession
    }
}

@MainActor
final class AppStreamControllerServices: StreamControllerDependencies {
    let settingsStore: SettingsStore
    let sessionController: SessionController
    let libraryController: LibraryController
    let consoleController: ConsoleController
    let achievementsController: AchievementsController
    let inputController: InputController

    private let networkSessionProvider: AppNetworkSessionProvider
    private let videoCapabilitiesBootstrapProbe: VideoCapabilitiesBootstrapProbe
    private let streamPriorityShellController: AppStreamPriorityShellController
    private let videoLogger = GLogger(category: .video)

    init(
        settingsStore: SettingsStore,
        sessionController: SessionController,
        libraryController: LibraryController,
        consoleController: ConsoleController,
        achievementsController: AchievementsController,
        inputController: InputController,
        networkSessionProvider: AppNetworkSessionProvider,
        videoCapabilitiesBootstrapProbe: VideoCapabilitiesBootstrapProbe,
        streamPriorityShellController: AppStreamPriorityShellController
    ) {
        self.settingsStore = settingsStore
        self.sessionController = sessionController
        self.libraryController = libraryController
        self.consoleController = consoleController
        self.achievementsController = achievementsController
        self.inputController = inputController
        self.networkSessionProvider = networkSessionProvider
        self.videoCapabilitiesBootstrapProbe = videoCapabilitiesBootstrapProbe
        self.streamPriorityShellController = streamPriorityShellController
    }

    func apiSession() -> URLSession {
        networkSessionProvider.session()
    }

    func updateControllerSettings() {
        inputController.updateControllerSettings(from: settingsStore)
    }

    func prepareStreamVideoCapabilitiesIfNeeded() {
        videoCapabilitiesBootstrapProbe.runIfNeeded(
            dependencies: .init(
                makeDevice: { MTLCreateSystemDefaultDevice() },
                makeProbe: { LiveUpscaleCapabilityProbe() },
                makeResolver: { UpscaleCapabilityResolver(probe: $0) },
                logInfo: { [videoLogger] in videoLogger.info($0) },
                logWarning: { [videoLogger] in videoLogger.warning($0) }
            )
        )
    }

    func enterStreamPriorityMode() async {
        await streamPriorityShellController.enter(policy: .tearDownShell)
    }

    func exitStreamPriorityMode() async {
        await streamPriorityShellController.exit()
    }
}
