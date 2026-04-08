// CloudLibraryContentRouteHost.swift
// Defines the route host that switches between browse, utility, and title-detail content.
//

import SwiftUI
import StratixCore
import StratixModels

/// Owns the shell content switch between browse, utility, and detail destinations.
struct CloudLibraryContentRouteHost: View {
    let utilityRoute: ShellUtilityRoute?
    let utilityPresentation: CloudLibraryUtilityRoutePresentation
    let selectedSettingsPane: Binding<CloudLibrarySettingsPane>
    let utilityActions: CloudLibraryUtilityRouteActions
    let browsePresentation: CloudLibraryBrowseRoutePresentation
    let searchText: Binding<String>
    let browseActions: CloudLibraryBrowseRouteActions
    let detailPath: Binding<[TitleID]>
    let detailOriginRoute: AppRoute
    let viewModel: CloudLibraryViewModel
    let detailActions: CloudLibraryDetailRouteActions

    /// Hosts the detail navigation stack and routes utility or browse content into it.
    var body: some View {
        NavigationStack(path: detailPath) {
            routeContent
                .navigationDestination(for: TitleID.self) { titleID in
                    CloudLibraryDetailHydrationView(
                        titleID: titleID,
                        originRoute: detailOriginRoute,
                        viewModel: viewModel,
                        onLaunchStream: detailActions.launchStream,
                        onSecondaryAction: detailActions.secondaryAction
                    )
                }
        }
    }

    @ViewBuilder
    /// Chooses the current browse or utility destination for the CloudLibrary shell.
    private var routeContent: some View {
        if let utilityRoute {
            utilityRouteContent(utilityRoute)
        } else {
            CloudLibraryBrowseRouteHost(
                presentation: browsePresentation,
                searchText: searchText,
                actions: browseActions
            )
        }
    }

    @ViewBuilder
    /// Renders the active utility route into the correct profile or settings surface.
    private func utilityRouteContent(_ route: ShellUtilityRoute) -> some View {
        switch route {
        case .profile:
            let profile = utilityPresentation.profile
            CloudLibraryProfileView(
                profileName: profile.profileName,
                profileStatus: profile.profileStatus,
                profileStatusDetail: profile.profileStatusDetail,
                profileDetail: profile.profileDetail,
                profileImageURL: profile.profileImageURL,
                profileInitials: profile.profileInitials,
                gameDisplayName: profile.gameDisplayName,
                gamertag: profile.gamertag,
                gamerscore: profile.gamerscore,
                cloudLibraryCount: profile.cloudLibraryCount,
                consoleCount: profile.consoleCount,
                friendsCount: profile.friendsCount,
                friendsLastUpdatedAt: profile.friendsLastUpdatedAt,
                friendsErrorText: profile.friendsErrorText,
                onOpenConsoles: utilityActions.openConsoles,
                onOpenSettings: utilityActions.openSettings,
                onRefreshProfileData: utilityActions.refreshProfileData,
                onRefreshFriends: utilityActions.refreshFriends,
                onSignOut: utilityActions.signOut,
                onRequestSideRailEntry: utilityActions.requestSideRailEntry
            )
        case .settings:
            let settings = utilityPresentation.settings
            CloudLibrarySettingsView(
                selectedPane: selectedSettingsPane,
                profileName: settings.profileName,
                profileInitials: settings.profileInitials,
                profileImageURL: settings.profileImageURL,
                profileStatusText: settings.profileStatusText,
                profileStatusDetail: settings.profileStatusDetail,
                cloudLibraryCount: settings.cloudLibraryCount,
                consoleCount: settings.consoleCount,
                isLoadingCloudLibrary: settings.isLoadingCloudLibrary,
                regionOverrideDiagnostics: settings.regionOverrideDiagnostics,
                onRefreshCloudLibrary: utilityActions.refreshCloudLibrary,
                onRefreshConsoles: utilityActions.refreshConsoles,
                onSignOut: utilityActions.signOut,
                onRequestSideRailEntry: utilityActions.requestSideRailEntry,
                onExportPreviewDump: utilityActions.exportPreviewDump
            )
        }
    }
}
