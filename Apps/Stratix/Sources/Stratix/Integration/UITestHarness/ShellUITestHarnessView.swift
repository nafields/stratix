// ShellUITestHarnessView.swift
// Defines the shell ui test harness view used in the Integration / UITestHarness surface.
//

import SwiftUI
import StratixCore
import StratixModels

struct ShellUITestHarnessView: View {
    @Environment(SettingsStore.self) private var settingsStore

    @State private var primaryRoute = Self.initialPrimaryRoute
    @State private var utilityRoute: ShellUtilityRoute?
    @State private var selectedTile: MediaTileViewState?
    @State private var streamOverlayVisible = false
    @State private var selectedSettingsPane: CloudLibrarySettingsPane = .overview
    @State private var searchQueryText = ""
    @State private var isSideRailExpanded = false
    @State private var didRequestInitialFocus = false

    private var activeHeroBackgroundURL: URL? {
        if let selectedTile {
            return selectedTile.artworkURL
        }

        switch primaryRoute {
        case .home:
            return ShellUITestHarnessFixtures.homeState.heroBackgroundURL
        case .library:
            return ShellUITestHarnessFixtures.libraryState.heroBackdropURL
        case .search:
            return ShellUITestHarnessFixtures.homeState.heroBackgroundURL
        case .consoles:
            return nil
        }
    }

    private var currentSurfaceID: String {
        if streamOverlayVisible { return "stream" }
        if selectedTile != nil { return "detail" }
        return utilityRoute?.rawValue ?? primaryRoute.rawValue
    }

    private var shellContentHorizontalPadding: CGFloat {
        if utilityRoute != nil || selectedTile != nil || primaryRoute == .consoles {
            return 0
        }
        switch primaryRoute {
        case .home:
            return 0
        case .library, .search:
            return StratixTheme.Layout.outerPadding
        case .consoles:
            return 0
        }
    }

    private var shellContentTopPadding: CGFloat {
        if utilityRoute != nil || selectedTile != nil || primaryRoute == .consoles {
            return 0
        }
        switch primaryRoute {
        case .home:
            return 0
        case .library, .search:
            return StratixTheme.Shell.contentTopPadding
        case .consoles:
            return 0
        }
    }

    private var shellContentLeadingAdjustment: CGFloat {
        if utilityRoute != nil {
            return 0
        }
        switch primaryRoute {
        case .home, .consoles:
            return 0
        case .library, .search:
            return StratixTheme.Shell.browseRouteLeadingInset
        }
    }

    private var shouldConsumeBackEvent: Bool {
        ShellExitHandlingDecision.resolve(
            utilityRoute: utilityRoute,
            selectedTile: selectedTile,
            streamOverlayVisible: streamOverlayVisible,
            primaryRoute: primaryRoute,
            isSideRailExpanded: isSideRailExpanded
        ).shouldConsumeBackEvent
    }

    var body: some View {
        shellScaffold
            .applyExitCommandIfNeeded(shouldConsumeBackEvent, perform: handleLocalBack)
            .onPlayPauseCommand {
                handleSettingsShortcut()
            }
            .onAppear {
                guard !didRequestInitialFocus else { return }
                didRequestInitialFocus = true
                requestTopContentFocus(for: primaryRoute)
            }
    }

    private static var initialPrimaryRoute: SideRailNavID {
        guard let override = StratixLaunchMode.uiTestBrowseRouteOverrideRawValue else {
            return .home
        }

        switch override {
        case "home":
            return .home
        case "library":
            return .library
        case "search":
            return .search
        case "consoles":
            return .consoles
        default:
            return .home
        }
    }

    private var shellScaffold: some View {
        CloudLibraryShellView(
            sideRail: CloudLibraryPreviewData.sideRail,
            selectedNavID: primaryRoute,
            activeUtilityRoute: utilityRoute,
            heroBackgroundURL: activeHeroBackgroundURL,
            contentTopPadding: shellContentTopPadding,
            contentHorizontalPadding: shellContentHorizontalPadding,
            contentLeadingAdjustment: shellContentLeadingAdjustment,
            contentBottomPadding: 18,
            sideRailSurfaceID: currentSurfaceID,
            onSelectNav: { navID in
                selectPrimaryRoute(navID)
            },
            onSelectSideRailAction: handleSideRailAction,
            onMoveFromSideRailToContent: handleMoveFromSideRailToContent,
            isSideRailExpanded: $isSideRailExpanded,
            forceCollapsedSideRail: false,
            collapsedSelectedNavFocusable: false,
            onExpansionChanged: { expanded in
                isSideRailExpanded = expanded
            }
        ) {
            shellContent
        }
    }

    @ViewBuilder
    private var shellContent: some View {
        routeContent

        if streamOverlayVisible {
            ShellUITestStreamOverlay {
                streamOverlayVisible = false
                requestTopContentFocus(for: .home)
            }
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        if let activeUtilityRoute = utilityRoute {
            switch activeUtilityRoute {
            case .profile:
                CloudLibraryProfileView(
                    profileName: ShellUITestHarnessFixtures.profileName,
                    profileStatus: ShellUITestHarnessFixtures.presenceState,
                    profileStatusDetail: "Playing \(ShellUITestHarnessFixtures.featuredItemName)",
                    profileDetail: "Gamerscore \(ShellUITestHarnessFixtures.gamerscore)",
                    profileImageURL: ShellUITestHarnessFixtures.profileImageURL,
                    profileInitials: "SP",
                    gameDisplayName: ShellUITestHarnessFixtures.profileName,
                    gamertag: ShellUITestHarnessFixtures.gamertag,
                    gamerscore: ShellUITestHarnessFixtures.gamerscore,
                    cloudLibraryCount: ShellUITestHarnessFixtures.cloudLibraryCount,
                    consoleCount: ShellUITestHarnessFixtures.consoleCount,
                    friendsCount: ShellUITestHarnessFixtures.friendsCount,
                    friendsLastUpdatedAt: Date(),
                    friendsErrorText: nil,
                    onOpenConsoles: {
                        self.utilityRoute = nil
                        primaryRoute = .consoles
                        isSideRailExpanded = false
                        requestTopContentFocus(for: .consoles)
                    },
                    onOpenSettings: {
                        openUtilityRoute(.settings)
                    },
                    onRefreshProfileData: {},
                    onRefreshFriends: {},
                    onSignOut: {},
                    onRequestSideRailEntry: requestSideRailEntry
                )
            case .settings:
                CloudLibrarySettingsView(
                    selectedPane: $selectedSettingsPane,
                    profileName: ShellUITestHarnessFixtures.profileName,
                    profileInitials: "SP",
                    profileImageURL: ShellUITestHarnessFixtures.profileImageURL,
                    profileStatusText: ShellUITestHarnessFixtures.presenceState,
                    profileStatusDetail: "Preview shell settings",
                    cloudLibraryCount: ShellUITestHarnessFixtures.cloudLibraryCount,
                    consoleCount: ShellUITestHarnessFixtures.consoleCount,
                    isLoadingCloudLibrary: false,
                    regionOverrideDiagnostics: nil,
                    onRefreshCloudLibrary: {},
                    onRefreshConsoles: {},
                    onSignOut: {},
                    onRequestSideRailEntry: requestSideRailEntry
                )
            }
        } else if let selectedTile {
            CloudLibraryTitleDetailScreen(
                state: ShellUITestHarnessFixtures.detailState(for: selectedTile),
                onPrimaryAction: {},
                onBack: {
                    self.selectedTile = nil
                    requestTopContentFocus(for: primaryRoute)
                },
                onSecondaryAction: { _ in },
                showsAmbientBackground: false,
                showsHeroArtwork: true,
                usesOuterPadding: true,
                interceptExitCommand: false
            )
        } else {
            switch primaryRoute {
            case .home:
                CloudLibraryHomeScreen(
                    state: ShellUITestHarnessFixtures.homeState,
                    onSelectRailItem: handleHomeRailSelection,
                    onSelectCarouselPlay: { _ in
                        streamOverlayVisible = true
                    },
                    onSelectCarouselDetails: { item in
                        selectedTile = MediaTileViewState(
                            id: item.id,
                            titleID: item.titleID,
                            title: item.title,
                            subtitle: item.subtitle,
                            caption: nil,
                            artworkURL: item.artworkURL,
                            badgeText: nil,
                            aspect: .portrait
                        )
                    },
                    onRequestSideRailEntry: requestSideRailEntry,
                    tileLookup: ShellUITestHarnessFixtures.homeTileLookup
                )
                .accessibilityIdentifier("route_home_root")
            case .library:
                CloudLibraryLibraryScreen(
                    state: ShellUITestHarnessFixtures.libraryState,
                    tileLookup: ShellUITestHarnessFixtures.libraryTileLookup,
                    onSelectTile: { item in
                        selectedTile = item
                    },
                    onRequestSideRailEntry: requestSideRailEntry
                )
            case .search:
                CloudLibrarySearchScreen(
                    queryTextValue: searchQueryText,
                    totalLibraryCount: ShellUITestHarnessFixtures.cloudLibraryCount,
                    browseItems: [],
                    resultItems: [],
                    tileLookup: [:],
                    onSelectTile: { item in
                        selectedTile = item
                    },
                    onRequestSideRailEntry: requestSideRailEntry
                )
                .searchable(text: $searchQueryText, prompt: "Search cloud titles")
            case .consoles:
                ShellUITestConsolesRouteView(onRequestSideRailEntry: requestSideRailEntry)
            }
        }
    }

    private func handleHomeRailSelection(_ item: CloudLibraryHomeRailItemViewState) {
        if case .title(let titleItem) = item {
            selectedTile = titleItem.tile
        }
    }

    private func selectPrimaryRoute(_ route: SideRailNavID) {
        streamOverlayVisible = false
        selectedTile = nil
        utilityRoute = nil
        primaryRoute = route
        if route != .home {
            isSideRailExpanded = false
        }
        requestTopContentFocus(for: route)
    }

    private func handleSideRailAction(_ actionID: String) {
        switch actionID {
        case "profile-menu":
            openUtilityRoute(.profile)
        case "settings":
            openUtilityRoute(.settings)
        default:
            break
        }
    }

    private func handleMoveFromSideRailToContent() {
        if let utilityRoute {
            requestUtilityFocus(for: utilityRoute)
        } else {
            requestTopContentFocus(for: primaryRoute)
        }
    }

    private func requestSideRailEntry() {
        guard !isSideRailExpanded else { return }
        isSideRailExpanded = true
    }

    private func handleLocalBack() {
        if streamOverlayVisible {
            streamOverlayVisible = false
            requestTopContentFocus(for: .home)
            return
        }

        if utilityRoute != nil {
            utilityRoute = nil
            isSideRailExpanded = false
            requestTopContentFocus(for: primaryRoute)
            return
        }

        if selectedTile != nil {
            selectedTile = nil
            requestTopContentFocus(for: primaryRoute)
            return
        }

        if primaryRoute != .home {
            primaryRoute = .home
            isSideRailExpanded = false
            requestTopContentFocus(for: .home)
            return
        }

        guard !isSideRailExpanded else { return }
        isSideRailExpanded = true
    }

    private func handleSettingsShortcut() {
        guard selectedTile == nil, !streamOverlayVisible else { return }
        if utilityRoute == .settings {
            utilityRoute = nil
            isSideRailExpanded = false
            requestTopContentFocus(for: primaryRoute)
        } else {
            openUtilityRoute(.settings)
        }
    }

    private func openUtilityRoute(_ route: ShellUtilityRoute) {
        guard selectedTile == nil, !streamOverlayVisible else { return }
        utilityRoute = route
        isSideRailExpanded = false
        requestUtilityFocus(for: route)
    }

    private func requestTopContentFocus(for route: SideRailNavID) {
        Task { @MainActor in
            await Task.yield()
            _ = route
        }
    }

    private func requestUtilityFocus(for route: ShellUtilityRoute) {
        _ = route
    }
}

private struct ShellUITestConsolesRouteView: View {
    let onRequestSideRailEntry: () -> Void

    @FocusState private var isPrimaryActionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Remote Consoles")
                .font(StratixTypography.rounded(38, weight: .bold, dynamicTypeSize: .large))
                .foregroundStyle(StratixTheme.Colors.textPrimary)

            Text("Deterministic console route used for shell UI smoke coverage.")
                .font(StratixTypography.rounded(18, weight: .medium, dynamicTypeSize: .large))
                .foregroundStyle(StratixTheme.Colors.textSecondary)

            Button("Connect Console") {}
                .focused($isPrimaryActionFocused)
                .defaultFocus($isPrimaryActionFocused, true)
                .buttonStyle(CloudLibraryTVButtonStyle())
                .onMoveCommand { direction in
                    if direction == .left {
                        onRequestSideRailEntry()
                    }
                }
        }
        .padding(.top, StratixTheme.Shell.contentTopPadding)
        .padding(.horizontal, StratixTheme.Layout.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("route_consoles_root")
    }
}

private struct ShellUITestStreamOverlay: View {
    let onStop: () -> Void

    @FocusState private var isStopFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Streaming Preview")
                    .font(StratixTypography.rounded(30, weight: .bold, dynamicTypeSize: .large))
                    .foregroundStyle(.white)

                Text("Synthetic stream overlay for deterministic shell round-trip coverage.")
                    .font(StratixTypography.rounded(18, weight: .medium, dynamicTypeSize: .large))
                    .foregroundStyle(.white.opacity(0.75))

                Button("Stop Streaming", action: onStop)
                    .buttonStyle(CloudLibraryTVButtonStyle())
                    .accessibilityIdentifier("stop_streaming")
                    .focused($isStopFocused)
            }
            .padding(40)
        }
        .accessibilityIdentifier("stream_overlay")
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                isStopFocused = true
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func applyExitCommandIfNeeded(_ enabled: Bool, perform action: @escaping () -> Void) -> some View {
        if enabled {
            onExitCommand(perform: action)
        } else {
            self
        }
    }
}
