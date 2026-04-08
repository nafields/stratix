// AppPreviewExportSource.swift
// Defines app preview export source for the App / Composition surface.
//

import Foundation
import StratixModels
import XCloudAPI

@MainActor
final class AppPreviewExportSource: PreviewExportSource {
    private let settingsStore: SettingsStore
    private let sessionController: SessionController
    private let libraryController: LibraryController
    private let profileController: ProfileController
    private let consoleController: ConsoleController
    private let streamController: StreamController

    init(
        settingsStore: SettingsStore,
        sessionController: SessionController,
        libraryController: LibraryController,
        profileController: ProfileController,
        consoleController: ConsoleController,
        streamController: StreamController
    ) {
        self.settingsStore = settingsStore
        self.sessionController = sessionController
        self.libraryController = libraryController
        self.profileController = profileController
        self.consoleController = consoleController
        self.streamController = streamController
    }

    var previewExportAuthStateDescription: String {
        switch sessionController.authState {
        case .unknown: return "unknown"
        case .unauthenticated: return "unauthenticated"
        case .authenticating: return "authenticating"
        case .authenticated: return "authenticated"
        }
    }

    var previewExportCurrentTokens: StreamTokens? {
        guard case .authenticated(let tokens) = sessionController.authState else { return nil }
        return tokens
    }

    var previewExportProfile: XboxCurrentUserProfile? { profileController.currentUserProfile }
    var previewExportPresence: XboxCurrentUserPresence? { profileController.currentUserPresence }
    var previewExportSocialPeople: [XboxSocialPerson] { profileController.socialPeople }
    var previewExportSocialPeopleTotalCount: Int { profileController.socialPeopleTotalCount }
    var previewExportCloudLibrarySections: [CloudLibrarySection] { libraryController.state.sections }
    var previewExportConsoles: [RemoteConsole] { consoleController.consoles }
    var previewExportSettingsStore: SettingsStore { settingsStore }
    var previewExportLastAuthError: String? { sessionController.lastAuthError }
    var previewExportLastCloudLibraryError: String? { libraryController.state.lastError }
    var previewExportLastPresenceReadError: String? { profileController.lastCurrentUserPresenceError }
    var previewExportLastPresenceWriteError: String? { profileController.lastCurrentUserPresenceWriteError }
    var previewExportLastSocialError: String? { profileController.lastSocialPeopleError }
    var previewExportIsLoadingCloudLibrary: Bool { libraryController.state.isLoading }
    var previewExportIsLoadingConsoles: Bool { consoleController.isLoading }
    var previewExportIsStreaming: Bool { streamController.state.streamingSession != nil }
    var previewExportCloudLibraryNeedsReauth: Bool { libraryController.state.needsReauth }

    func refreshPreviewExportData() async {
        async let profileTask: Void = profileController.loadCurrentUserProfile(force: true)
        async let presenceTask: Void = profileController.loadCurrentUserPresence(force: true)
        async let socialTask: Void = profileController.loadSocialPeople(force: true, maxItems: 48)
        async let consolesTask: Void = consoleController.refresh()
        async let libraryTask: Void = libraryController.refresh(forceRefresh: true, reason: .manualUser)
        _ = await (profileTask, presenceTask, socialTask, consolesTask, libraryTask)
    }
}
