// AppCoordinatorCompositionTests.swift
// Exercises app coordinator composition behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@MainActor
@Suite(.serialized)
struct AppCoordinatorCompositionTests {
    @Test
    func rootStoresCompositionHandlersInsteadOfWorkflowAndServiceWrappers() {
        let coordinator = AppCoordinator()
        let labels = Set(Mirror(reflecting: coordinator).children.compactMap(\.label))

        #expect(labels.contains("lifecycleCoordinator"))
        #expect(labels.contains("shellBootCoordinator"))
        #expect(!labels.contains("consoleControllerServices"))
        #expect(!labels.contains("inputControllerServices"))
        #expect(!labels.contains("startupWorkflow"))
        #expect(!labels.contains("foregroundRefreshWorkflow"))
        #expect(!labels.contains("backgroundRefreshWorkflow"))
        #expect(!labels.contains("cacheRestoreWorkflow"))
        #expect(!labels.contains("signOutWorkflow"))
    }

    @Test
    func lifecycleEntryPointsDelegateToLifecycleHandler() async {
        let graph = AppControllerBuilder.make(settingsStore: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let lifecycle = LifecycleSpy(backgroundRefreshResult: true)
        let shell = ShellBootSpy()
        let coordinator = AppCoordinator(graph: graph, lifecycleCoordinator: lifecycle, shellBootCoordinator: shell)

        await coordinator.onAppear()
        await coordinator.handleAppDidBecomeActive()
        let refreshed = await coordinator.performBackgroundAppRefresh()
        await coordinator.handleSessionDidSignOutFromController()

        #expect(lifecycle.onAppearCount == 1)
        #expect(lifecycle.foregroundCount == 1)
        #expect(lifecycle.backgroundCount == 1)
        #expect(lifecycle.signOutCount == 1)
        #expect(refreshed == true)
        #expect(shell.beginCalls.isEmpty)
    }

    @Test
    func shellBootEntryPointsDelegateToShellHandler() async {
        let graph = AppControllerBuilder.make(settingsStore: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let lifecycle = LifecycleSpy(backgroundRefreshResult: false)
        let shell = ShellBootSpy()
        let coordinator = AppCoordinator(graph: graph, lifecycleCoordinator: lifecycle, shellBootCoordinator: shell)

        await coordinator.beginShellBootHydrationIfNeeded()
        await coordinator.handleSessionDidAuthenticateFromController(tokens: makeTokens(), mode: .full)
        await coordinator.handleSessionDidAuthenticateFromController(tokens: makeTokens(), mode: .streamRefresh)

        #expect(shell.beginCalls == [true, true])
        #expect(lifecycle.onAppearCount == 0)
        #expect(lifecycle.foregroundCount == 0)
        #expect(lifecycle.backgroundCount == 0)
        #expect(lifecycle.signOutCount == 0)
    }

    private func makeTokens() -> StreamTokens {
        StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: "https://xcloud.example.com",
            webToken: nil,
            webTokenUHS: nil,
            xcloudRegions: []
        )
    }
}

@MainActor
private final class LifecycleSpy: AppLifecycleHandling {
    var onAppearCount = 0
    var foregroundCount = 0
    var backgroundCount = 0
    var signOutCount = 0
    let backgroundRefreshResult: Bool

    init(backgroundRefreshResult: Bool) {
        self.backgroundRefreshResult = backgroundRefreshResult
    }

    func onAppear() async {
        onAppearCount += 1
    }

    func handleAppDidBecomeActive() async {
        foregroundCount += 1
    }

    func performBackgroundAppRefresh() async -> Bool {
        backgroundCount += 1
        return backgroundRefreshResult
    }

    func handleSessionDidSignOut() async {
        signOutCount += 1
    }
}

@MainActor
private final class ShellBootSpy: AppShellBootHandling {
    var beginCalls: [Bool] = []

    func beginShellBootHydrationIfNeeded(restoreCachesBeforeBoot: Bool) async {
        beginCalls.append(restoreCachesBeforeBoot)
    }
}
