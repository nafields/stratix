// CloudLibraryActionCoordinator.swift
// Defines the cloud library action coordinator for the CloudLibrary / Root surface.
//

import Foundation
import StratixCore
import StratixModels

@MainActor
struct CloudLibraryActionCoordinator {
    func refreshCloudLibrary(
        forceRefresh: Bool,
        libraryService: any LibraryCommanding
    ) async {
        await libraryService.refresh(forceRefresh: forceRefresh, reason: .manualUser)
    }

    func refreshConsoles(
        consoleService: any ConsoleCommanding
    ) async {
        await consoleService.refresh()
    }

    func refreshProfile(
        profileService: any ProfileCommanding
    ) async {
        await profileService.loadCurrentUserProfile(force: true)
        await profileService.loadCurrentUserPresence(force: true)
    }

    func refreshFriends(
        profileService: any ProfileCommanding
    ) async {
        await profileService.loadSocialPeople(force: true, maxItems: 96)
    }

    func exportPreviewDataDump(
        previewExportController: PreviewExportController
    ) async -> String {
        do {
            let url = try await previewExportController.exportPreviewDataDump(refreshBeforeExport: true)
            return "Preview dump saved:\n\(url.path)"
        } catch {
            return "Preview dump failed: \(error.localizedDescription)"
        }
    }

    func signOut(
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        presentationStore: CloudLibraryPresentationStore,
        signOutAction: @escaping @MainActor () async -> Void
    ) async {
        routeState.closeUtilityRoute()
        routeState.clearDetailPath()
        focusState.isSideRailExpanded = false
        presentationStore.resetForSignOut()
        await signOutAction()
    }

    func launchCloudStream(
        titleId: TitleID,
        source: String,
        currentActiveStreamContext: @escaping @MainActor () -> StreamContext?,
        setActiveStreamContext: @escaping @MainActor (StreamContext?) -> Void,
        enterPriorityMode: @escaping @MainActor (StreamRuntimeContext) async -> Void,
        trackEvent: @escaping @MainActor ([String: String]) -> Void,
        trackFirstPlayIfNeeded: @escaping @MainActor () -> Void
    ) async {
        guard currentActiveStreamContext() == nil else { return }
        trackEvent(["source": source, "title_id": titleId.rawValue])
        trackFirstPlayIfNeeded()
        await enterPriorityMode(.cloud(titleId: titleId))
        setActiveStreamContext(.cloud(titleId: titleId))
    }

    func handleStreamDismiss(
        browseRoute: CloudLibraryBrowseRoute,
        stopStreaming: @escaping @MainActor () async -> Void,
        exitPriorityMode: @escaping @MainActor () async -> Void,
        requestTopContentFocus: @escaping @MainActor (CloudLibraryBrowseRoute) -> Void
    ) async {
        await stopStreaming()
        await exitPriorityMode()
        requestTopContentFocus(browseRoute)
    }
}
