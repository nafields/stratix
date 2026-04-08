// ConsoleListView.swift
// Defines the console inventory screen and the home-stream launch handoff into the stream surface.
//

import SwiftUI
import StratixCore
import XCloudAPI

/// Renders the available remote-play consoles and owns the console-to-stream modal transition.
struct ConsoleListView: View {
    @Environment(ConsoleController.self) var consoleController
    @Environment(StreamController.self) var streamController
    var onRequestSideRailEntry: () -> Void = {}
    @State var showingStream = false
    @State var selectedConsole: RemoteConsole?
    @State var showTroubleshootDetails = false
    @FocusState var focusedTarget: ConsoleFocusTarget?
    @State var focusSettler = FocusSettleDebouncer()
    @State var pendingFocusTask: Task<Void, Never>?
    @State var lastFocusedConsoleID: String?
    @State var shouldRequestDeferredFocus = false
    @State var consoleGridColumns: [GridItem] = [
        GridItem(.flexible(minimum: 720), spacing: 28, alignment: .top)
    ]

    struct RootShellVisibility: Equatable {
        let opacity: Double
        let allowsHitTesting: Bool
        let isAccessibilityHidden: Bool
    }

    init(
        onRequestSideRailEntry: @escaping () -> Void = {}
    ) {
        self.onRequestSideRailEntry = onRequestSideRailEntry
    }

    /// Mounts the console shell and presents the stream surface when a console launch is active.
    var body: some View {
        rootContent
            .opacity(shellVisibility.opacity)
            .allowsHitTesting(shellVisibility.allowsHitTesting)
            .accessibilityHidden(shellVisibility.isAccessibilityHidden)
            .fullScreenCover(isPresented: $showingStream, onDismiss: handleStreamDismissed) {
                if let console = selectedConsole {
                    StreamControllerInputHost(onOverlayToggle: {
                        streamController.requestOverlayToggle()
                    }) {
                        StreamView(context: .home(console: console))
                    }
                    .ignoresSafeArea()
                    .interactiveDismissDisabled(true)
                    .onExitCommand {
                        // Prevent controller back/menu from dismissing the stream modal.
                    }
                }
            }
    }

    private var shellVisibility: RootShellVisibility {
        Self.rootShellVisibility(isStreamPriorityModeActive: streamController.isStreamPriorityModeActive)
    }

    /// Hides the console shell while stream-priority mode owns the screen.
    static func rootShellVisibility(isStreamPriorityModeActive: Bool) -> RootShellVisibility {
        if isStreamPriorityModeActive {
            return .init(
                opacity: 0,
                allowsHitTesting: false,
                isAccessibilityHidden: true
            )
        }

        return .init(
            opacity: 1,
            allowsHitTesting: true,
            isAccessibilityHidden: false
        )
    }

    /// Builds the console route body, including refresh and focus-restoration behavior.
    private var rootContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            contentSection
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 28)
        .padding(.horizontal, StratixTheme.Layout.outerPadding)
        .padding(.bottom, 22)
        .accessibilityIdentifier("route_consoles_root")
        .task { await refreshConsoles() }
        .onAppear {
            requestPrimaryFocus()
        }
        .onDisappear {
            focusSettler.cancel()
            pendingFocusTask?.cancel()
        }
        .onChange(of: focusedTarget) { _, target in
            handleFocusedTargetChange(target)
        }
        .onChange(of: consoleController.isLoading) { _, isLoading in
            guard !isLoading, shouldRequestDeferredFocus else { return }
            shouldRequestDeferredFocus = false
            requestPrimaryFocus()
        }
        .onChange(of: consoleIDs) { _, consoleIDs in
            handleConsoleIDsChange(consoleIDs)
        }
        .onMoveCommand { direction in
            NavigationPerformanceTracker.recordRemoteMoveStart(surface: "consoles", direction: direction)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if consoleController.isLoading {
            CloudLibraryStatusPanel(
                state: .init(
                    kind: .loading,
                    title: "Finding your Xbox",
                    message: "Checking your home consoles and remote play availability.",
                    primaryActionTitle: nil
                )
            )
        } else if consoleController.consoles.isEmpty {
            emptyState
        } else {
            consoleGrid
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("My Consoles")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)

                Text(headerSubtitle)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    var consoleIDs: [String] {
        consoleController.consoles.map(\.serverId)
    }

    private var headerSubtitle: String {
        if consoleController.isLoading {
            return "Syncing your remote play devices..."
        }
        let count = consoleController.consoles.count
        if count == 0 {
            return "No consoles detected yet. Make sure your Xbox is online and remote features are enabled."
        }
        return count == 1 ? "1 console ready for remote play." : "\(count) consoles ready for remote play."
    }

    /// Refreshes the console inventory before the consoles route becomes interactive.
    func refreshConsoles() async {
        await consoleController.refresh()
    }
    // MARK: - Stream launch

    /// Starts the modal home-stream launch flow for the selected console.
    func launchHomeStream(_ console: RemoteConsole) {
        Task { @MainActor in
            selectedConsole = await Self.prepareHomeStreamLaunch(
                console: console,
                isShowingStream: showingStream,
                enterPriorityMode: { context in
                    await streamController.enterStreamPriorityMode(context: context)
                }
            )
            guard selectedConsole != nil else { return }
            showingStream = true
        }
    }

    /// Restores console-shell state after the full-screen stream view is dismissed.
    func handleStreamDismissed() {
        Task { @MainActor in
            selectedConsole = nil
            showingStream = false
            await Self.restoreShellAfterStreamDismissal(
                stopStreaming: {
                    await streamController.stopStreaming()
                },
                exitPriorityMode: {
                    await streamController.exitStreamPriorityMode()
                },
                restoreFocus: {
                    requestPrimaryFocus()
                }
            )
        }
    }

    /// Enters stream-priority mode and returns the selected console when launch can proceed.
    static func prepareHomeStreamLaunch(
        console: RemoteConsole,
        isShowingStream: Bool,
        enterPriorityMode: (StreamRuntimeContext) async -> Void
    ) async -> RemoteConsole? {
        guard !isShowingStream else { return nil }
        await enterPriorityMode(.home(consoleId: console.serverId))
        return console
    }

    /// Stops streaming, exits priority mode, and restores focus to the console shell.
    static func restoreShellAfterStreamDismissal(
        stopStreaming: () async -> Void,
        exitPriorityMode: () async -> Void,
        restoreFocus: @MainActor () -> Void
    ) async {
        await stopStreaming()
        await exitPriorityMode()
        await MainActor.run {
            restoreFocus()
        }
    }
}

#if DEBUG
#Preview("ConsoleListView", traits: .fixedLayout(width: 1920, height: 1080)) {
    let coordinator = AppCoordinator()
    ZStack {
        CloudLibraryAmbientBackground(imageURL: nil)
        ConsoleListView()
            .environment(coordinator.consoleController)
            .environment(coordinator.streamController)
            .environment(coordinator.libraryController)
            .environment(coordinator.settingsStore)
    }
}
#endif
