#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, assert_contains, assert_not_contains, fail

errors: list[str] = []

required_paths = [
    rel("Packages/StratixCore/Sources/StratixCore/App/Composition/AppControllerProtocols.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Composition/AppControllerServices.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Composition/AppControllerBuilder.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Composition/AppControllerGraph.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Lifecycle/AppCacheRestoreWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Lifecycle/AppStartupWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Lifecycle/AppForegroundRefreshWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Lifecycle/AppBackgroundRefreshWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Lifecycle/AppSignOutWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Lifecycle/AppLifecycleCoordinator.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Shell/AppShellBootCoordinator.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/Shell/AppStreamPriorityShellController.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/App/AppCoordinatorTestingSupport.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/PostStreamShellRecoveryWorkflow.swift"),
]
errors.extend(require_paths(required_paths))

app_coordinator = rel("Packages/StratixCore/Sources/StratixCore/App/AppCoordinator.swift")
lifecycle_coordinator = rel("Packages/StratixCore/Sources/StratixCore/App/Lifecycle/AppLifecycleCoordinator.swift")
shell_boot_coordinator = rel("Packages/StratixCore/Sources/StratixCore/App/Shell/AppShellBootCoordinator.swift")
testing_extension = rel("Packages/StratixCore/Sources/StratixCore/App/AppCoordinatorTestingSupport.swift")

errors.extend(assert_contains(app_coordinator, [
    "let streamPriorityShellController: AppStreamPriorityShellController",
    "private let profileControllerServices: AppProfileControllerServices",
    "private let achievementsControllerServices: AppAchievementsControllerServices",
    "private let libraryControllerServices: AppLibraryControllerServices",
    "private let streamControllerServices: AppStreamControllerServices",
    "private let lifecycleCoordinator: any AppLifecycleHandling",
    "private let shellBootCoordinator: any AppShellBootHandling",
    "sessionController.attach(self)",
    "libraryController.attach(libraryControllerServices)",
    "profileController.attach(profileControllerServices)",
    "consoleController.attach(sessionController)",
    "streamController.attach(streamControllerServices)",
    "inputController.attach(streamController)",
    "achievementsController.attach(achievementsControllerServices)",
    "await lifecycleCoordinator.onAppear()",
    "await lifecycleCoordinator.handleAppDidBecomeActive()",
    "await lifecycleCoordinator.performBackgroundAppRefresh()",
    "await lifecycleCoordinator.handleSessionDidSignOut()",
    "await shellBootCoordinator.beginShellBootHydrationIfNeeded(restoreCachesBeforeBoot: true)",
]))

errors.extend(assert_contains(lifecycle_coordinator, [
    "protocol AppLifecycleHandling: AnyObject",
    "final class AppLifecycleCoordinator: AppLifecycleHandling",
    "private let startupWorkflow: AppStartupWorkflow",
    "private let foregroundRefreshWorkflow: AppForegroundRefreshWorkflow",
    "private let backgroundRefreshWorkflow: AppBackgroundRefreshWorkflow",
    "private let signOutWorkflow: AppSignOutWorkflow",
    "func onAppear() async",
    "func handleAppDidBecomeActive() async",
    "func performBackgroundAppRefresh() async -> Bool",
    "func handleSessionDidSignOut() async",
]))

errors.extend(assert_contains(shell_boot_coordinator, [
    "protocol AppShellBootHandling: AnyObject",
    "final class AppShellBootCoordinator: AppShellBootHandling",
    "private let cacheRestoreWorkflow: AppCacheRestoreWorkflow",
    "private let startupWorkflow: AppStartupWorkflow",
    "private let streamPriorityShellController: AppStreamPriorityShellController",
    "func beginShellBootHydrationIfNeeded(restoreCachesBeforeBoot: Bool) async",
    "streamPriorityShellController.isShellSuspendedForStreaming",
    "cacheRestoreWorkflow.run(",
]))

errors.extend(assert_contains(testing_extension, [
    "extension AppCoordinator",
    "func testingApplyTokensFull(",
    "func testingApplyTokensStreamRefresh(",
    "var testingPostStreamRefreshInvocationCount: Int",
]))

errors.extend(assert_not_contains(app_coordinator, [
    "private let consoleControllerServices: AppConsoleControllerServices",
    "private let inputControllerServices: AppInputControllerServices",
    "import Metal",
    "import InputBridge",
    "import VideoRenderingKit",
    "private let startupWorkflow: AppStartupWorkflow",
    "private let foregroundRefreshWorkflow: AppForegroundRefreshWorkflow",
    "private let backgroundRefreshWorkflow: AppBackgroundRefreshWorkflow",
    "private let cacheRestoreWorkflow: AppCacheRestoreWorkflow",
    "private let signOutWorkflow: AppSignOutWorkflow",
    "func xboxWebCredentialsForController(",
    "func authenticatedTokensForConsoleController(",
    "func apiSessionForController(",
    "private func authenticatedTokensWithWebToken(",
    "private func xboxWebCredentials(",
    "private func beginShellBootHydrationIfNeeded(",
    "AppCoordinatorEnvironmentFactory",
    "refreshStreamTokensInBackground(",
    "libraryController.refresh(",
    "previewExportController.refresh(",
    "streamPriorityShellController.handle",
    "clearPersistedLibraryCaches(",
    "clearPersistedAchievementCache(",
    "resetForSignOut()",
    "shellBootstrapController.attach(self)",
]))

fail(errors)
print("Stage 7 coordinator composition guard passed.")
