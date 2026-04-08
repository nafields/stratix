// AppControllerProtocols.swift
// Defines app controller protocols for the App / Composition surface.
//

import Foundation
import StratixModels
import StreamingCore
import XCloudAPI

@MainActor
protocol SessionControllerEventSink: AnyObject {
    func handleSessionDidSignOutFromController() async
    func handleSessionDidAuthenticateFromController(tokens: StreamTokens, mode: SessionTokenApplyMode) async
}

@MainActor
protocol ConsoleControllerDependencies: AnyObject {
    func authenticatedConsoleTokens() -> StreamTokens?
}

@MainActor
protocol ProfileControllerDependencies: AnyObject {
    func xboxWebCredentials(logContext: String) async -> XboxWebCredentials?
    func apiSession() -> URLSession
    func updateProfileSettings(name: String?, imageURLString: String?)
}

@MainActor
protocol AchievementsControllerDependencies: AnyObject {
    func xboxWebCredentials(logContext: String) async -> XboxWebCredentials?
    func apiSession() -> URLSession
    func currentUserProfileXUID() -> String?
    func currentUserPresenceXUID() -> String?
    func cacheCurrentUserProfile(_ profile: XboxCurrentUserProfile)
    func cacheCurrentUserPresence(_ presence: XboxCurrentUserPresence)
    func upsertAchievementSummary(_ summary: TitleAchievementSummary)
}

@MainActor
protocol LibraryControllerDependencies: AnyObject, Sendable {
    func authenticatedLibraryTokens() -> StreamTokens?
    func refreshStreamTokens(logContext: String) async throws -> StreamTokens
    func xboxWebCredentials(logContext: String) async -> XboxWebCredentials?
    func achievementSnapshot(titleID: TitleID) -> TitleAchievementSnapshot?
    func loadCurrentUserProfile() async
    func loadSocialPeople(maxItems: Int) async
}

@MainActor
protocol InputControllerDependencies: AnyObject {
    func currentStreamingSession() -> (any StreamingSessionFacade)?
    func requestOverlayToggle()
    func requestDisconnect()
    var isStreamOverlayVisible: Bool { get }
    func toggleStatsHUD()
}

@MainActor
protocol StreamControllerDependencies: AnyObject, Sendable {
    var settingsStore: SettingsStore { get }
    var sessionController: SessionController { get }
    var libraryController: LibraryController { get }
    var consoleController: ConsoleController { get }
    var achievementsController: AchievementsController { get }
    var inputController: InputController { get }
    func apiSession() -> URLSession
    func updateControllerSettings()
    func prepareStreamVideoCapabilitiesIfNeeded()
    func enterStreamPriorityMode() async
    func exitStreamPriorityMode() async
}
