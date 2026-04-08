// CloudLibraryUtilityRoutePresentation.swift
// Defines cloud library utility route presentation for the Features / CloudLibrary surface.
//

import Foundation
import StratixCore

struct CloudLibraryUtilityProfileProjection: Equatable, Hashable {
    let profileName: String
    let profileStatus: String
    let profileStatusDetail: String
    let profileDetail: String
    let profileImageURL: URL?
    let profileInitials: String
    let gameDisplayName: String?
    let gamertag: String?
    let gamerscore: String?
    let cloudLibraryCount: Int
    let consoleCount: Int
    let friendsCount: Int
    let friendsLastUpdatedAt: Date?
    let friendsErrorText: String?

    static let empty = CloudLibraryUtilityProfileProjection(
        profileName: "",
        profileStatus: "",
        profileStatusDetail: "",
        profileDetail: "",
        profileImageURL: nil,
        profileInitials: "",
        gameDisplayName: nil,
        gamertag: nil,
        gamerscore: nil,
        cloudLibraryCount: 0,
        consoleCount: 0,
        friendsCount: 0,
        friendsLastUpdatedAt: nil,
        friendsErrorText: nil
    )
}

struct CloudLibrarySettingsPresentationProjection: Equatable, Hashable {
    let profileName: String
    let profileInitials: String
    let profileImageURL: URL?
    let profileStatusText: String
    let profileStatusDetail: String
    let cloudLibraryCount: Int
    let consoleCount: Int
    let isLoadingCloudLibrary: Bool
    let regionOverrideDiagnostics: String?

    static let empty = CloudLibrarySettingsPresentationProjection(
        profileName: "",
        profileInitials: "",
        profileImageURL: nil,
        profileStatusText: "",
        profileStatusDetail: "",
        cloudLibraryCount: 0,
        consoleCount: 0,
        isLoadingCloudLibrary: false,
        regionOverrideDiagnostics: nil
    )
}

struct CloudLibraryUtilityRoutePresentation: Equatable, Hashable {
    let profile: CloudLibraryUtilityProfileProjection
    let settings: CloudLibrarySettingsPresentationProjection

    static let empty = CloudLibraryUtilityRoutePresentation(
        profile: .empty,
        settings: .empty
    )
}

@MainActor
struct CloudLibraryUtilityRoutePresentationBuilder {
    func utilityProfileProjection(
        shellChrome: CloudLibraryShellChromeProjection,
        sideRailProjection: CloudLibrarySideRailShellProjection,
        profileSnapshot: ProfileShellSnapshot
    ) -> CloudLibraryUtilityProfileProjection {
        CloudLibraryUtilityProfileProjection(
            profileName: shellChrome.profileName,
            profileStatus: shellChrome.profileStatus,
            profileStatusDetail: shellChrome.profileStatusDetail,
            profileDetail: shellChrome.profileDetail,
            profileImageURL: shellChrome.profileImageURL,
            profileInitials: shellChrome.profileInitials,
            gameDisplayName: profileSnapshot.gameDisplayName,
            gamertag: profileSnapshot.gamertag,
            gamerscore: profileSnapshot.gamerscore,
            cloudLibraryCount: sideRailProjection.libraryCount,
            consoleCount: sideRailProjection.consoleCount,
            friendsCount: profileSnapshot.friendsCount,
            friendsLastUpdatedAt: profileSnapshot.friendsLastUpdatedAt,
            friendsErrorText: profileSnapshot.friendsErrorText
        )
    }

    func settingsPresentationProjection(
        shellChrome: CloudLibraryShellChromeProjection,
        sideRailProjection: CloudLibrarySideRailShellProjection,
        isLoadingCloudLibrary: Bool,
        regionOverrideDiagnostics: String?
    ) -> CloudLibrarySettingsPresentationProjection {
        CloudLibrarySettingsPresentationProjection(
            profileName: shellChrome.profileName,
            profileInitials: shellChrome.profileInitials,
            profileImageURL: shellChrome.profileImageURL,
            profileStatusText: shellChrome.profileStatus,
            profileStatusDetail: shellChrome.profileStatusDetail,
            cloudLibraryCount: sideRailProjection.libraryCount,
            consoleCount: sideRailProjection.consoleCount,
            isLoadingCloudLibrary: isLoadingCloudLibrary,
            regionOverrideDiagnostics: regionOverrideDiagnostics
        )
    }

    func makeUtilityRoutePresentation(
        shellPresentation: CloudLibraryShellPresentationProjection,
        profileSnapshot: ProfileShellSnapshot,
        isLoadingCloudLibrary: Bool,
        regionOverrideDiagnostics: String?
    ) -> CloudLibraryUtilityRoutePresentation {
        CloudLibraryUtilityRoutePresentation(
            profile: utilityProfileProjection(
                shellChrome: shellPresentation.shellChrome,
                sideRailProjection: shellPresentation.sideRail,
                profileSnapshot: profileSnapshot
            ),
            settings: settingsPresentationProjection(
                shellChrome: shellPresentation.shellChrome,
                sideRailProjection: shellPresentation.sideRail,
                isLoadingCloudLibrary: isLoadingCloudLibrary,
                regionOverrideDiagnostics: regionOverrideDiagnostics
            )
        )
    }
}
