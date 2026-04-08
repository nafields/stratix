// CloudLibraryPresentationStore.swift
// Defines the cloud library presentation store.
//

import Observation
import StratixCore

@Observable
@MainActor
/// Caches shell, browse, and utility presentation projections so route hosts read pre-shaped view state.
final class CloudLibraryPresentationStore {
    let shellBuilder: CloudLibraryShellPresentationBuilder
    let browseBuilder: CloudLibraryBrowseRoutePresentationBuilder
    let utilityBuilder: CloudLibraryUtilityRoutePresentationBuilder

    var shellChromeProjection = CloudLibraryShellChromeProjection.empty
    var sideRailProjection = CloudLibrarySideRailShellProjection.empty
    var sideRailState = SideRailNavigationViewState(
        accountName: "",
        accountStatus: "",
        accountDetail: nil,
        profileImageURL: nil,
        profileInitials: "",
        navItems: [],
        trailingActions: []
    )
    var shellPresentationProjection = CloudLibraryShellPresentationProjection.empty
    var utilityRoutePresentation = CloudLibraryUtilityRoutePresentation.empty
    var browseRoutePresentation = CloudLibraryBrowseRoutePresentation.empty

    init(
        shellBuilder: CloudLibraryShellPresentationBuilder = .init(),
        browseBuilder: CloudLibraryBrowseRoutePresentationBuilder = .init(),
        utilityBuilder: CloudLibraryUtilityRoutePresentationBuilder = .init()
    ) {
        self.shellBuilder = shellBuilder
        self.browseBuilder = browseBuilder
        self.utilityBuilder = utilityBuilder
    }

    /// Rebuilds shell-wide chrome and utility projections from the latest profile, shell, and library snapshots.
    func rebuildShellPresentation(
        settingsStore: SettingsStore,
        profileSnapshot: ProfileShellSnapshot,
        libraryStatus: LibraryShellStatusSnapshot,
        consoleCount: Int,
        isLoadingCloudLibrary: Bool,
        regionOverrideDiagnostics: String?,
        viewModel: CloudLibraryViewModel
    ) {
        let shellProjection = shellBuilder.makeShellPresentation(
            profileSnapshot: profileSnapshot,
            libraryStatus: libraryStatus,
            settingsStore: settingsStore,
            libraryCount: viewModel.cachedLibraryCount,
            consoleCount: consoleCount
        )
        let utilityProjection = utilityBuilder.makeUtilityRoutePresentation(
            shellPresentation: shellProjection,
            profileSnapshot: profileSnapshot,
            isLoadingCloudLibrary: isLoadingCloudLibrary,
            regionOverrideDiagnostics: regionOverrideDiagnostics
        )

        if shellChromeProjection != shellProjection.shellChrome {
            shellChromeProjection = shellProjection.shellChrome
        }
        if sideRailProjection != shellProjection.sideRail {
            sideRailProjection = shellProjection.sideRail
            sideRailState = shellProjection.sideRail.sideRailState
        }
        if shellPresentationProjection != shellProjection {
            shellPresentationProjection = shellProjection
        }
        if utilityRoutePresentation != utilityProjection {
            utilityRoutePresentation = utilityProjection
        }
    }

    /// Rebuilds the browse-route presentation cache from route, load, focus, and view-model projection state.
    func rebuildBrowsePresentation(
        loadState: CloudLibraryLoadState,
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        viewModel: CloudLibraryViewModel
    ) {
        let nextPresentation = browseBuilder.makeBrowseRoutePresentation(
            loadState: loadState,
            routeState: routeState,
            focusState: focusState,
            homeState: viewModel.cachedHomeState,
            libraryState: viewModel.cachedLibraryState,
            totalLibraryCount: viewModel.cachedLibraryCount,
            searchBrowseItems: viewModel.cachedSearchBrowseItems,
            searchResultItems: viewModel.cachedSearchResultItems
        )
        if browseRoutePresentation != nextPresentation {
            browseRoutePresentation = nextPresentation
        }
    }

    /// Produces a stable task token for shell and utility presentation rebuild work.
    func shellPresentationTaskID(
        settingsStore: SettingsStore,
        profileSnapshot: ProfileShellSnapshot,
        libraryStatus: LibraryShellStatusSnapshot,
        consoleCount: Int,
        isLoadingCloudLibrary: Bool,
        regionOverrideDiagnostics: String?,
        viewModel: CloudLibraryViewModel
    ) -> Int {
        let shellProjection = shellBuilder.makeShellPresentation(
            profileSnapshot: profileSnapshot,
            libraryStatus: libraryStatus,
            settingsStore: settingsStore,
            libraryCount: viewModel.cachedLibraryCount,
            consoleCount: consoleCount
        )
        let utilityProjection = utilityBuilder.makeUtilityRoutePresentation(
            shellPresentation: shellProjection,
            profileSnapshot: profileSnapshot,
            isLoadingCloudLibrary: isLoadingCloudLibrary,
            regionOverrideDiagnostics: regionOverrideDiagnostics
        )
        var hasher = Hasher()
        hasher.combine(shellProjection)
        hasher.combine(utilityProjection)
        return hasher.finalize()
    }

    /// Produces a stable task token for browse presentation rebuild work.
    func browsePresentationTaskID(
        loadState: CloudLibraryLoadState,
        routeState: CloudLibraryRouteState,
        focusState: CloudLibraryFocusState,
        viewModel: CloudLibraryViewModel
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(
            browseBuilder.makeBrowseRoutePresentation(
                loadState: loadState,
                routeState: routeState,
                focusState: focusState,
                homeState: viewModel.cachedHomeState,
                libraryState: viewModel.cachedLibraryState,
                totalLibraryCount: viewModel.cachedLibraryCount,
                searchBrowseItems: viewModel.cachedSearchBrowseItems,
                searchResultItems: viewModel.cachedSearchResultItems
            )
        )
        return hasher.finalize()
    }

    /// Clears every cached presentation surface so sign-out cannot leak shell UI from the prior session.
    func resetForSignOut() {
        shellChromeProjection = .empty
        sideRailProjection = .empty
        sideRailState = SideRailNavigationViewState(
            accountName: "",
            accountStatus: "",
            accountDetail: nil,
            profileImageURL: nil,
            profileInitials: "",
            navItems: [],
            trailingActions: []
        )
        shellPresentationProjection = .empty
        utilityRoutePresentation = .empty
        browseRoutePresentation = .empty
    }
}
