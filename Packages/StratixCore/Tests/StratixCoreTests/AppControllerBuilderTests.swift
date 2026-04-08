// AppControllerBuilderTests.swift
// Exercises app controller builder behavior.
//

import Foundation
@testable import StratixCore
import Testing
import XCloudAPI

@MainActor
@Suite(.serialized)
struct AppControllerBuilderTests {
    @Test
    func build_createsDistinctControllerGraphAndAttachesServices() {
        let graph = AppControllerBuilder.make(settingsStore: SettingsStore())
        let graphLabels = Set(Mirror(reflecting: graph).children.compactMap(\.label))
        let consoleDependencies: any ConsoleControllerDependencies = graph.sessionController
        let inputDependencies: any InputControllerDependencies = graph.streamController

        #expect(ObjectIdentifier(graph.sessionController) != ObjectIdentifier(graph.libraryController))
        #expect(ObjectIdentifier(graph.libraryController) != ObjectIdentifier(graph.streamController))
        #expect(ObjectIdentifier(graph.streamController) != ObjectIdentifier(graph.profileController))
        #expect(ObjectIdentifier(graph.consoleController) != ObjectIdentifier(graph.achievementsController))
        #expect(ObjectIdentifier(graph.shellBootstrapController) != ObjectIdentifier(graph.inputController))
        #expect(!graphLabels.contains("consoleControllerServices"))
        #expect(!graphLabels.contains("inputControllerServices"))
        #expect(consoleDependencies.authenticatedConsoleTokens() == nil)
        #expect(inputDependencies.isStreamOverlayVisible == false)
        #expect(graph.libraryController.dependencies == nil)
        #expect(graph.streamController.streamingSession == nil)
        #expect(graph.shellBootstrapController.phase == .idle)
    }

    @Test
    func coordinatorInit_leavesStartupWorkOwnedByExplicitTriggers() async {
        let coordinator = AppCoordinator()

        #expect(coordinator.shellBootstrapController.phase == .idle)
        #expect(coordinator.streamController.shellRestoredAfterStreamExit == false)
        #expect(coordinator.testingPostStreamRefreshInvocationCount == 0)
        #expect(await coordinator.testingIsCloudLibraryLoadTaskActive() == false)
    }

    @Test
    func coordinatorInit_preservesShellBootTransitionAfterFullTokenApply() async {
        let coordinator = AppCoordinator()

        #expect(coordinator.shellBootstrapController.phase == .idle)

        await coordinator.testingApplyTokensFull(
            StreamTokens(
                xhomeToken: "xhome-token",
                xhomeHost: "https://xhome.example.com",
                xcloudToken: "xcloud-token",
                xcloudHost: "https://xcloud.example.com",
                webToken: nil,
                webTokenUHS: nil,
                xcloudRegions: []
            )
        )

        #expect(coordinator.shellBootstrapController.phase != .idle)
    }

    @Test
    func build_attachesDedicatedPreviewExportSource() async throws {
        let graph = AppControllerBuilder.make(settingsStore: SettingsStore())

        let outputURL = try await graph.previewExportController.exportPreviewDataDump(
            refreshBeforeExport: false
        )

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(outputURL.lastPathComponent.contains("GreenlightPreviewDump"))
    }
}
