// ServiceProtocols.swift
// Defines service protocols.
//

import Foundation
import StratixModels
import StreamingCore
import XCloudAPI

// MARK: - Snapshot DTOs

public struct SessionServiceSnapshot: Sendable {
    public let authState: SessionAuthState
    public let lastAuthError: String?
    public let xcloudRegions: [LoginRegion]
}

public struct LibraryServiceSnapshot: Sendable {
    public let sections: [CloudLibrarySection]
    public let productDetails: [ProductID: CloudLibraryProductDetail]
    public let isLoading: Bool
    public let homeMerchandising: HomeMerchandisingSnapshot?
    public let isHomeMerchandisingLoading: Bool
    public let hasCompletedInitialHomeMerchandising: Bool
    public let lastError: String?
    public let needsReauth: Bool
}

public struct ProfileServiceSnapshot: Sendable {
    public let currentUserProfile: XboxCurrentUserProfile?
    public let currentUserPresence: XboxCurrentUserPresence?
    public let socialPeople: [XboxSocialPerson]
    public let isLoadingSocialPeople: Bool
    public let lastSocialPeopleError: String?
}

public struct ConsoleServiceSnapshot: Sendable {
    public let consoles: [RemoteConsole]
    public let isLoading: Bool
    public let lastError: String?
}

public struct StreamServiceSnapshot: Sendable {
    public let isStreaming: Bool
    public let lifecycleDescription: String?
    public let isStreamOverlayVisible: Bool
}

public struct LibraryShellStatusSnapshot: Sendable, Equatable {
    public let needsReauth: Bool
    public let isLoading: Bool
    public let hasSections: Bool
    public let lastErrorText: String?
}

public struct ProfileShellSnapshot: Sendable, Equatable {
    public let preferredScreenName: String?
    public let profileImageURL: URL?
    public let gameDisplayName: String?
    public let gamertag: String?
    public let gamerscore: String?
    public let presenceState: String?
    public let activeTitleName: String?
    public let lastSeenTitleName: String?
    public let onlineDeviceType: String?
    public let isOnline: Bool
    public let isLoadingCurrentUserPresence: Bool
    public let lastCurrentUserPresenceError: String?
    public let friendsCount: Int
    public let friendsLastUpdatedAt: Date?
    public let friendsErrorText: String?
}

public struct ConsoleInventorySnapshot: Sendable, Equatable {
    public let count: Int
}

// MARK: - Session

public protocol SessionStateReading: AnyObject {
    func sessionSnapshot() async -> SessionServiceSnapshot
}

@MainActor
public protocol SessionCommanding: AnyObject {
    func onAppear() async
    func beginSignIn() async
    func signOut() async
}

public typealias SessionServicing = SessionStateReading & SessionCommanding

// MARK: - Library

public protocol LibraryStateReading: AnyObject {
    func librarySnapshot() async -> LibraryServiceSnapshot
}

@MainActor
public protocol LibraryShellStatusReading: AnyObject {
    func libraryShellStatusSnapshot() -> LibraryShellStatusSnapshot
}

@MainActor
public protocol LibraryItemReading: AnyObject {
    func item(titleID: TitleID) -> CloudLibraryItem?
    func item(productID: ProductID) -> CloudLibraryItem?
}

@MainActor
public protocol LibraryDetailReading: AnyObject {
    func productDetail(productID: ProductID) -> CloudLibraryProductDetail?
}

@MainActor
public protocol LibraryCommanding: AnyObject {
    func refresh(forceRefresh: Bool, reason: CloudLibraryRefreshReason) async
    func loadDetail(productID: ProductID, locale: String, forceRefresh: Bool) async
}

// MARK: - Profile

public protocol ProfileStateReading: AnyObject {
    func profileSnapshot() async -> ProfileServiceSnapshot
}

@MainActor
public protocol ProfileShellReading: AnyObject {
    func profileShellSnapshot() -> ProfileShellSnapshot
}

@MainActor
public protocol ProfileCommanding: AnyObject {
    func refresh(force: Bool) async
    func loadCurrentUserProfile(force: Bool) async
    func loadCurrentUserPresence(force: Bool) async
    @discardableResult
    func setCurrentUserPresence(isOnline: Bool) async -> Bool
    func loadSocialPeople(force: Bool, maxItems: Int) async
}

// MARK: - Console

public protocol ConsoleStateReading: AnyObject {
    func consoleSnapshot() async -> ConsoleServiceSnapshot
}

@MainActor
public protocol ConsoleInventoryReading: AnyObject {
    func consoleInventorySnapshot() -> ConsoleInventorySnapshot
}

@MainActor
public protocol ConsoleCommanding: AnyObject {
    func refresh() async
}

// MARK: - Stream

public protocol StreamStateReading: AnyObject {
    func streamSnapshot() async -> StreamServiceSnapshot
}

@MainActor
public protocol StreamRegionDiagnosticsReading: AnyObject {
    func regionOverrideDiagnostics(for rawValue: String) -> String?
}

@MainActor
public protocol StreamCommanding: AnyObject {
    func requestOverlayToggle()
    func startHomeStream(console: RemoteConsole, bridge: any WebRTCBridge) async
    func startCloudStream(titleId: TitleID, bridge: any WebRTCBridge) async
    func stopStreaming() async
    func setOverlayVisible(_ visible: Bool) async
    func requestDisconnect()
    func toggleStatsHUD()
}

// MARK: - Conformances

extension SessionController: SessionStateReading, SessionCommanding {
    nonisolated public func sessionSnapshot() async -> SessionServiceSnapshot {
        await MainActor.run {
            SessionServiceSnapshot(
                authState: authState,
                lastAuthError: lastAuthError,
                xcloudRegions: xcloudRegions
            )
        }
    }
}

extension LibraryController: LibraryStateReading, LibraryShellStatusReading, LibraryItemReading, LibraryDetailReading, LibraryCommanding {
    nonisolated public func librarySnapshot() async -> LibraryServiceSnapshot {
        await MainActor.run {
            let currentState = self.state
            return LibraryServiceSnapshot(
                sections: currentState.sections,
                productDetails: currentState.productDetails,
                isLoading: currentState.isLoading,
                homeMerchandising: currentState.homeMerchandising,
                isHomeMerchandisingLoading: currentState.isHomeMerchandisingLoading,
                hasCompletedInitialHomeMerchandising: currentState.hasCompletedInitialHomeMerchandising,
                lastError: currentState.lastError,
                needsReauth: currentState.needsReauth
            )
        }
    }

    public func libraryShellStatusSnapshot() -> LibraryShellStatusSnapshot {
        let currentState = state
        return LibraryShellStatusSnapshot(
            needsReauth: currentState.needsReauth,
            isLoading: currentState.isLoading,
            hasSections: !currentState.sections.isEmpty,
            lastErrorText: currentState.lastError
        )
    }
}

extension ProfileController: ProfileStateReading, ProfileShellReading, ProfileCommanding {
    nonisolated public func profileSnapshot() async -> ProfileServiceSnapshot {
        await MainActor.run {
            ProfileServiceSnapshot(
                currentUserProfile: currentUserProfile,
                currentUserPresence: currentUserPresence,
                socialPeople: socialPeople,
                isLoadingSocialPeople: isLoadingSocialPeople,
                lastSocialPeopleError: lastSocialPeopleError
            )
        }
    }

    public func profileShellSnapshot() -> ProfileShellSnapshot {
        let profile = currentUserProfile
        let presence = currentUserPresence
        return ProfileShellSnapshot(
            preferredScreenName: profile?.preferredScreenName,
            profileImageURL: profile?.gameDisplayPicRaw,
            gameDisplayName: profile?.gameDisplayName,
            gamertag: profile?.gamertag,
            gamerscore: profile?.gamerscore,
            presenceState: presence?.state,
            activeTitleName: presence?.activeTitleName,
            lastSeenTitleName: presence?.lastSeen?.titleName,
            onlineDeviceType: presence?.devices.first?.type,
            isOnline: presence?.isOnline ?? false,
            isLoadingCurrentUserPresence: isLoadingCurrentUserPresence,
            lastCurrentUserPresenceError: lastCurrentUserPresenceError,
            friendsCount: socialPeopleTotalCount,
            friendsLastUpdatedAt: socialPeopleLastUpdatedAt,
            friendsErrorText: lastSocialPeopleError
        )
    }
}

extension ConsoleController: ConsoleStateReading, ConsoleInventoryReading, ConsoleCommanding {
    nonisolated public func consoleSnapshot() async -> ConsoleServiceSnapshot {
        await MainActor.run {
            ConsoleServiceSnapshot(
                consoles: consoles,
                isLoading: isLoading,
                lastError: lastError
            )
        }
    }

    public func consoleInventorySnapshot() -> ConsoleInventorySnapshot {
        ConsoleInventorySnapshot(count: consoles.count)
    }
}

extension StreamController: StreamStateReading, StreamRegionDiagnosticsReading, StreamCommanding {
    nonisolated public func streamSnapshot() async -> StreamServiceSnapshot {
        await MainActor.run {
            let currentState = self.state
            return StreamServiceSnapshot(
                isStreaming: currentState.streamingSession != nil,
                lifecycleDescription: currentState.streamingSession.map { "\($0.lifecycle)" },
                isStreamOverlayVisible: currentState.isStreamOverlayVisible
            )
        }
    }
}
