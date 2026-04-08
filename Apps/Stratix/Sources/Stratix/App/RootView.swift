// RootView.swift
// Defines the root view used in the App surface.
//

import SwiftUI
import StratixCore

/// Chooses the top-level app surface from auth state and active UI-test launch flags.
struct RootView: View {
    let coordinator: AppCoordinator

    @Environment(SessionController.self) private var sessionController
    @Environment(LibraryController.self) private var libraryController
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasTriggeredForcedLiveHomeRefreshForUITest = false

    /// Mounts the root surface and forwards active-scene transitions into the app coordinator outside UI-test harness modes.
    var body: some View {
        rootContent
        .onChange(of: scenePhase) { _, phase in
            guard shouldHandleActiveScenePhase, phase == .active else { return }
            Task {
                await coordinator.handleAppDidBecomeActive()
            }
        }
        .transaction {
            if settingsStore.accessibility.reduceMotion {
                $0.animation = nil
            }
        }
    }

    @ViewBuilder
    /// Switches between the shell harnesses and the real authenticated root based on launch mode.
    private var rootContent: some View {
        if StratixLaunchMode.isGamePassHomeUITestModeEnabled {
            CloudLibraryUITestHarnessView()
        } else if StratixLaunchMode.isShellUITestModeEnabled {
            ShellUITestHarnessView()
        } else {
            authenticatedContent
        }
    }

    @ViewBuilder
    /// Resolves the authenticated app content from the current session state and optional UI-test live refresh mode.
    private var authenticatedContent: some View {
        switch sessionController.authState {
        case .unknown:
            ProgressView("Starting...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unauthenticated:
            AuthView()

        case .authenticating(let info):
            DeviceCodeView(info: info)

        case .authenticated:
            AuthenticatedShellView()
                .task {
                    guard shouldForceLiveHomeRefresh else { return }
                    hasTriggeredForcedLiveHomeRefreshForUITest = true
                    await libraryController.refresh(forceRefresh: true, reason: .startupAuto)
                }
        }
    }

    /// Disables scene-phase side effects when the app is running inside deterministic shell harnesses.
    private var shouldHandleActiveScenePhase: Bool {
        !StratixLaunchMode.isShellUITestModeEnabled
            && !StratixLaunchMode.isGamePassHomeUITestModeEnabled
    }

    /// Forces one live home refresh in the authenticated shell when a targeted UI-test flag asks for it.
    private var shouldForceLiveHomeRefresh: Bool {
        StratixLaunchMode.shouldForceLiveHomeRefreshForUITest
            && !hasTriggeredForcedLiveHomeRefreshForUITest
    }
}
