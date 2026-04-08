// CloudLibraryShellPresentation.swift
// Defines cloud library shell presentation for the Features / CloudLibrary surface.
//

import Foundation
import StratixCore
import StratixModels

struct CloudLibrarySideRailShellProjection: Equatable, Hashable, Sendable {
    let accountName: String
    let accountStatus: String
    let accountDetail: String
    let profileImageURL: URL?
    let profileInitials: String
    let libraryCount: Int
    let consoleCount: Int

    static let empty = CloudLibrarySideRailShellProjection(
        accountName: "",
        accountStatus: "",
        accountDetail: "",
        profileImageURL: nil,
        profileInitials: "",
        libraryCount: 0,
        consoleCount: 0
    )

    var sideRailState: SideRailNavigationViewState {
        SideRailNavigationViewState(
            accountName: accountName,
            accountStatus: accountStatus,
            accountDetail: accountDetail.isEmpty ? nil : accountDetail,
            profileImageURL: profileImageURL,
            profileInitials: profileInitials,
            navItems: [
                .init(id: .search, title: "Search", systemImage: "magnifyingglass"),
                .init(id: .home, title: "Home", systemImage: "house.fill"),
                .init(id: .library, title: "Library", systemImage: "square.grid.2x2.fill", badgeText: libraryCount > 0 ? "\(libraryCount)" : nil),
                .init(id: .consoles, title: "Consoles", systemImage: "tv.fill", badgeText: consoleCount > 0 ? "\(consoleCount)" : nil)
            ],
            trailingActions: []
        )
    }
}

struct CloudLibraryShellChromeProjection: Equatable, Hashable {
    let profileName: String
    let profileStatus: String
    let profileStatusDetail: String
    let profileDetail: String
    let profileImageURL: URL?
    let profileInitials: String

    static let empty = CloudLibraryShellChromeProjection(
        profileName: "",
        profileStatus: "",
        profileStatusDetail: "",
        profileDetail: "",
        profileImageURL: nil,
        profileInitials: ""
    )
}

struct CloudLibraryShellPresentationProjection: Equatable, Hashable {
    let shellChrome: CloudLibraryShellChromeProjection
    let sideRail: CloudLibrarySideRailShellProjection

    static let empty = CloudLibraryShellPresentationProjection(
        shellChrome: .empty,
        sideRail: .empty
    )
}

@MainActor
struct CloudLibraryShellPresentationBuilder {
    func makeShellChrome(
        profileSnapshot: ProfileShellSnapshot,
        libraryStatus: LibraryShellStatusSnapshot,
        settingsStore: SettingsStore
    ) -> CloudLibraryShellChromeProjection {
        let profileName = authenticatedShellEffectiveProfileName(
            profileSnapshot: profileSnapshot,
            settingsStore: settingsStore
        )
        return CloudLibraryShellChromeProjection(
            profileName: profileName,
            profileStatus: authenticatedShellProfilePresenceStatus(
                profileSnapshot: profileSnapshot,
                libraryStatus: libraryStatus,
                settingsStore: settingsStore
            ),
            profileStatusDetail: authenticatedShellProfilePresenceDetailText(profileSnapshot: profileSnapshot),
            profileDetail: authenticatedShellSettingsSummary(settingsStore: settingsStore),
            profileImageURL: authenticatedShellEffectiveProfileImageURL(
                profileSnapshot: profileSnapshot,
                settingsStore: settingsStore
            ),
            profileInitials: authenticatedShellInitials(from: profileName)
        )
    }

    func makeSideRailProjection(
        shellChrome: CloudLibraryShellChromeProjection,
        libraryCount: Int,
        consoleCount: Int
    ) -> CloudLibrarySideRailShellProjection {
        CloudLibrarySideRailShellProjection(
            accountName: shellChrome.profileName,
            accountStatus: shellChrome.profileStatus,
            accountDetail: shellChrome.profileDetail,
            profileImageURL: shellChrome.profileImageURL,
            profileInitials: shellChrome.profileInitials,
            libraryCount: libraryCount,
            consoleCount: consoleCount
        )
    }

    func makeShellPresentation(
        profileSnapshot: ProfileShellSnapshot,
        libraryStatus: LibraryShellStatusSnapshot,
        settingsStore: SettingsStore,
        libraryCount: Int,
        consoleCount: Int
    ) -> CloudLibraryShellPresentationProjection {
        let shellChrome = makeShellChrome(
            profileSnapshot: profileSnapshot,
            libraryStatus: libraryStatus,
            settingsStore: settingsStore
        )
        let sideRail = makeSideRailProjection(
            shellChrome: shellChrome,
            libraryCount: libraryCount,
            consoleCount: consoleCount
        )
        return CloudLibraryShellPresentationProjection(
            shellChrome: shellChrome,
            sideRail: sideRail
        )
    }
}
