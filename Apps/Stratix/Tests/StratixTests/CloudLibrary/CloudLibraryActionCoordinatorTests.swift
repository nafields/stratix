// CloudLibraryActionCoordinatorTests.swift
// Exercises cloud library action coordinator behavior.
//

import Foundation
import Testing
import StratixModels
import XCloudAPI
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

@MainActor
struct CloudLibraryActionCoordinatorTests {
    @Test
    func refreshCloudLibrary_callsManualUserRefresh() async {
        var capturedReason: CloudLibraryRefreshReason?
        let controller = LibraryController(
            refreshWorkflow: { _, reason, _ in
                capturedReason = reason
            }
        )

        await CloudLibraryActionCoordinator().refreshCloudLibrary(
            forceRefresh: true,
            libraryService: controller
        )

        #expect(capturedReason == .manualUser)
    }

    @Test
    func refreshConsoles_refreshesConsoleInventory() async {
        let controller = ConsoleController(
            refreshWorkflow: { controller, _ in
                controller.setConsoles([
                    makeRemoteConsole()
                ])
                return controller.consoles
            }
        )
        let dependencies = ConsoleDependenciesStub()
        controller.attach(dependencies)

        await CloudLibraryActionCoordinator().refreshConsoles(
            consoleService: controller
        )

        #expect(controller.consoles.count == 1)
        #expect(controller.consoles.first?.serverId == "server-1")
    }

    @Test
    func refreshConsoles_allowsEmptyInventory() async {
        let controller = ConsoleController(
            refreshWorkflow: { _, _ in [] }
        )

        await CloudLibraryActionCoordinator().refreshConsoles(
            consoleService: controller
        )

        #expect(controller.consoles.isEmpty)
    }

    @Test
    func refreshProfile_loadsProfileAndPresence() async {
        var profileLoaded = false
        var presenceLoaded = false
        let controller = ProfileController(
            profileLoadWorkflow: { controller, force in
                #expect(force)
                controller.setCurrentUserProfile(
                    XboxCurrentUserProfile(
                        xuid: "xuid-1",
                        gamertag: "player1",
                        gameDisplayName: "Player One",
                        gameDisplayPicRaw: nil,
                        gamerscore: "1000"
                    )
                )
                profileLoaded = true
            },
            presenceLoadWorkflow: { controller, force in
                #expect(force)
                controller.setCurrentUserPresence(
                    XboxCurrentUserPresence(
                        xuid: "xuid-1",
                        state: "online",
                        devices: [
                            XboxPresenceDevice(
                                type: "Scarlett",
                                titles: [
                                    XboxPresenceTitle(
                                        id: "1",
                                        name: "Halo Infinite",
                                        placement: "Full",
                                        state: "Active"
                                    )
                                ]
                            )
                        ],
                        lastSeen: nil
                    )
                )
                presenceLoaded = true
            }
        )

        await CloudLibraryActionCoordinator().refreshProfile(
            profileService: controller
        )

        #expect(profileLoaded)
        #expect(presenceLoaded)
        #expect(controller.profileShellSnapshot().activeTitleName == "Halo Infinite")
    }

    @Test
    func refreshFriends_loadsSocialPeopleUsingExpectedLimit() async {
        let controller = ProfileController(
            socialLoadWorkflow: { controller, force, maxItems in
                #expect(force)
                #expect(maxItems == 96)
                controller.setLastSocialPeopleError("Xbox social is temporarily unavailable.")
            }
        )

        await CloudLibraryActionCoordinator().refreshFriends(
            profileService: controller
        )

        #expect(controller.profileShellSnapshot().friendsErrorText == "Xbox social is temporarily unavailable.")
    }

    @Test
    func exportPreviewDataDump_returnsSuccessAndFailureStrings() async throws {
        let coordinator = CloudLibraryActionCoordinator()
        let successController = PreviewExportController()
        successController.attach(PreviewExportSourceStub())

        let successMessage = await coordinator.exportPreviewDataDump(
            previewExportController: successController
        )
        #expect(successMessage.hasPrefix("Preview dump saved:\n"))

        let successPathPrefix = "Preview dump saved:\n"
        let successPath = String(successMessage.dropFirst(successPathPrefix.count))
        let exportedDump = try String(contentsOfFile: successPath, encoding: .utf8)
        Attachment.record(exportedDump, named: "Preview Dump JSON")
        #expect(exportedDump.contains("\"app\""))
        #expect(exportedDump.contains("\"cloudLibrary\""))

        let failureMessage = await coordinator.exportPreviewDataDump(
            previewExportController: PreviewExportController()
        )
        #expect(failureMessage == "Preview dump failed: Preview export source is unavailable.")
    }

    @Test
    func launchCloudStream_preservesTypedTitleIDIntoContextAndPriorityMode() async {
        let coordinator = CloudLibraryActionCoordinator()
        let titleId = TitleID("1234")
        var enteredContext: StreamRuntimeContext?
        var activeStreamContext: StreamContext?
        var trackedMetadata: [String: String]?
        var trackedFirstPlay = false

        await coordinator.launchCloudStream(
            titleId: titleId,
            source: "home_carousel_play",
            currentActiveStreamContext: { activeStreamContext },
            setActiveStreamContext: { activeStreamContext = $0 },
            enterPriorityMode: { enteredContext = $0 },
            trackEvent: { trackedMetadata = $0 },
            trackFirstPlayIfNeeded: { trackedFirstPlay = true }
        )

        #expect(enteredContext == .cloud(titleId: titleId))
        #expect(trackedMetadata?["source"] == "home_carousel_play")
        #expect(trackedMetadata?["title_id"] == titleId.rawValue)
        #expect(trackedFirstPlay)

        if case .cloud(let activeTitleId) = activeStreamContext {
            #expect(activeTitleId == titleId)
        } else {
            Issue.record("Expected a cloud stream context")
        }
    }

    @Test
    func handleStreamDismiss_stopsStreaming_exitsPriorityMode_andRequestsFocus() async {
        let coordinator = CloudLibraryActionCoordinator()
        var steps: [String] = []
        var focusedRoute: CloudLibraryBrowseRoute?

        await coordinator.handleStreamDismiss(
            browseRoute: .home,
            stopStreaming: { steps.append("stop") },
            exitPriorityMode: { steps.append("exit") },
            requestTopContentFocus: {
                focusedRoute = $0
                steps.append("focus")
            }
        )

        #expect(steps == ["stop", "exit", "focus"])
        #expect(focusedRoute == .home)
    }
}

@MainActor
private final class PreviewExportSourceStub: PreviewExportSource {
    let previewExportAuthStateDescription = "authenticated"
    let previewExportCurrentTokens: StreamTokens? = nil
    let previewExportProfile: XboxCurrentUserProfile? = nil
    let previewExportPresence: XboxCurrentUserPresence? = nil
    let previewExportSocialPeople: [XboxSocialPerson] = []
    let previewExportSocialPeopleTotalCount = 0
    let previewExportCloudLibrarySections: [CloudLibrarySection] = []
    let previewExportConsoles: [RemoteConsole] = []
    let previewExportSettingsStore = SettingsStore(defaults: UserDefaults(suiteName: "PreviewExportSourceStub")!)
    let previewExportLastAuthError: String? = nil
    let previewExportLastCloudLibraryError: String? = nil
    let previewExportLastPresenceReadError: String? = nil
    let previewExportLastPresenceWriteError: String? = nil
    let previewExportLastSocialError: String? = nil
    let previewExportIsLoadingCloudLibrary = false
    let previewExportIsLoadingConsoles = false
    let previewExportIsStreaming = false
    let previewExportCloudLibraryNeedsReauth = false

    func refreshPreviewExportData() async {}
}

private func makeRemoteConsole() -> RemoteConsole {
    let data = """
    {
      "deviceName": "Fixture Xbox",
      "serverId": "server-1",
      "powerState": "ConnectedStandby",
      "consoleType": "XboxSeriesX",
      "playPath": "/play",
      "outOfHomeWarning": false,
      "wirelessWarning": false,
      "isDevKit": false
    }
    """.data(using: .utf8)!

    return try! JSONDecoder().decode(RemoteConsole.self, from: data)
}

@MainActor
private final class ConsoleDependenciesStub: ConsoleControllerDependencies {
    func authenticatedConsoleTokens() -> StreamTokens? {
        StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "xhome.test",
            xcloudToken: nil,
            xcloudHost: nil
        )
    }
}
