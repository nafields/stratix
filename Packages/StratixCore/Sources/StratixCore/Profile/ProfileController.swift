// ProfileController.swift
// Defines the profile controller that coordinates the Profile surface.
//

import DiagnosticsKit
import Foundation
import StratixModels
import Observation
import StreamingCore
import XCloudAPI

@MainActor
@Observable
public final class ProfileController {
    public private(set) var currentUserProfile: XboxCurrentUserProfile?
    public private(set) var currentUserPresence: XboxCurrentUserPresence?
    public private(set) var isLoadingCurrentUserPresence = false
    public private(set) var lastCurrentUserPresenceError: String?
    public private(set) var currentUserPresenceWriteSupported: Bool?
    public private(set) var lastCurrentUserPresenceWriteError: String?
    public private(set) var socialPeople: [XboxSocialPerson] = []
    public private(set) var socialPeopleTotalCount = 0
    public private(set) var socialPeopleLastUpdatedAt: Date?
    public private(set) var isLoadingSocialPeople = false
    public private(set) var lastSocialPeopleError: String?

    private enum DefaultsKey {
        static let presenceWriteSupported = "stratix.presence.write_supported"
    }

    private enum TaskID {
        static let profile = "profile"
        static let presence = "presence"
        static let social = "social"
    }

    let taskRegistry = TaskRegistry()
    private weak var dependencies: (any ProfileControllerDependencies)?
    private let defaults: UserDefaults
    private let logger = GLogger(category: .auth)
    private let profileLoadWorkflow: (@MainActor (ProfileController, Bool) async -> Void)?
    private let presenceLoadWorkflow: (@MainActor (ProfileController, Bool) async -> Void)?
    private let socialLoadWorkflow: (@MainActor (ProfileController, Bool, Int) async -> Void)?
    private let presenceSetWorkflow: (@MainActor (ProfileController, Bool) async -> Bool)?
    private var isSuspendedForStreaming = false
    @ObservationIgnored private var hasLoadedSocialCache = false

    init(
        defaults: UserDefaults = .standard,
        profileLoadWorkflow: (@MainActor (ProfileController, Bool) async -> Void)? = nil,
        presenceLoadWorkflow: (@MainActor (ProfileController, Bool) async -> Void)? = nil,
        socialLoadWorkflow: (@MainActor (ProfileController, Bool, Int) async -> Void)? = nil,
        presenceSetWorkflow: (@MainActor (ProfileController, Bool) async -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.profileLoadWorkflow = profileLoadWorkflow
        self.presenceLoadWorkflow = presenceLoadWorkflow
        self.socialLoadWorkflow = socialLoadWorkflow
        self.presenceSetWorkflow = presenceSetWorkflow
    }

    func attach(_ dependencies: any ProfileControllerDependencies) {
        self.dependencies = dependencies
        restorePresenceWriteCapabilityFromDefaults()
    }

    public func refresh(force: Bool = false) async {
        await loadCurrentUserProfile(force: force)
        await loadCurrentUserPresence(force: force)
        await loadSocialPeople(force: force)
    }

    public func loadCurrentUserProfile(force: Bool = false) async {
        guard !isSuspendedForStreaming else { return }

        let (task, inserted) = await taskRegistry.taskOrRegister(id: TaskID.profile) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performLoadCurrentUserProfile(force: force)
            }
        }
        await task.value
        if inserted {
            await taskRegistry.remove(id: TaskID.profile)
        }
    }

    public func loadCurrentUserPresence(force: Bool = false) async {
        guard !isSuspendedForStreaming else { return }

        let (task, inserted) = await taskRegistry.taskOrRegister(id: TaskID.presence) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performLoadCurrentUserPresence(force: force)
            }
        }
        await task.value
        if inserted {
            await taskRegistry.remove(id: TaskID.presence)
        }
    }

    @discardableResult
    public func setCurrentUserPresence(isOnline: Bool) async -> Bool {
        if let presenceSetWorkflow {
            return await presenceSetWorkflow(self, isOnline)
        }
        if currentUserPresenceWriteSupported == false {
            lastCurrentUserPresenceWriteError = "Xbox status sync is read-only in this environment. Using display status only."
            return false
        }
        lastCurrentUserPresenceWriteError = nil
        guard let credentials = await dependencies?.xboxWebCredentials(logContext: "presence update") else { return false }

        do {
            let session = dependencies?.apiSession() ?? .shared
            try await XboxWebPresenceClient(credentials: credentials, session: session).setCurrentUserPresence(isOnline: isOnline)
            currentUserPresenceWriteSupported = true
            defaults.set(true, forKey: DefaultsKey.presenceWriteSupported)
            await loadCurrentUserPresence(force: true)
            return true
        } catch {
            if case let APIError.httpError(code, body) = error {
                let lower = body.lowercased()
                if isPresenceWriteUnsupported(code: code, responseBody: lower) {
                    currentUserPresenceWriteSupported = false
                    defaults.set(false, forKey: DefaultsKey.presenceWriteSupported)
                    lastCurrentUserPresenceWriteError = "Xbox status sync is read-only in this environment. Using display status only."
                } else {
                    lastCurrentUserPresenceWriteError = "Couldn’t update Xbox status right now."
                }
            } else {
                lastCurrentUserPresenceWriteError = "Couldn’t update Xbox status right now."
            }
            logger.warning("Failed to update Xbox presence: \(error.localizedDescription)")
            return false
        }
    }

    public func loadSocialPeople(force: Bool = false, maxItems: Int = 96) async {
        guard !isSuspendedForStreaming else { return }

        let (task, inserted) = await taskRegistry.taskOrRegister(id: TaskID.social) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performLoadSocialPeople(force: force, maxItems: maxItems)
            }
        }
        await task.value
        if inserted {
            await taskRegistry.remove(id: TaskID.social)
        }
    }

    func suspendForStreaming() async {
        isSuspendedForStreaming = true
        isLoadingCurrentUserPresence = false
        isLoadingSocialPeople = false
        await taskRegistry.cancelAll()
    }

    func resumeAfterStreaming() {
        isSuspendedForStreaming = false
    }

    func resetForSignOut() {
        isSuspendedForStreaming = false
        currentUserProfile = nil
        currentUserPresence = nil
        isLoadingCurrentUserPresence = false
        lastCurrentUserPresenceError = nil
        currentUserPresenceWriteSupported = nil
        lastCurrentUserPresenceWriteError = nil
        socialPeople = []
        socialPeopleTotalCount = 0
        socialPeopleLastUpdatedAt = nil
        isLoadingSocialPeople = false
        lastSocialPeopleError = nil
    }

    func clearPersistedSocialCache() {
        hasLoadedSocialCache = false
        try? FileManager.default.removeItem(at: Self.socialPeopleCacheURL)
    }

    func setCurrentUserProfile(_ value: XboxCurrentUserProfile?) {
        guard currentUserProfile != value else { return }
        currentUserProfile = value
    }

    func setCurrentUserPresence(_ value: XboxCurrentUserPresence?) {
        guard currentUserPresence != value else { return }
        currentUserPresence = value
    }

    func setIsLoadingCurrentUserPresence(_ value: Bool) {
        guard isLoadingCurrentUserPresence != value else { return }
        isLoadingCurrentUserPresence = value
    }

    func setLastCurrentUserPresenceError(_ value: String?) {
        guard lastCurrentUserPresenceError != value else { return }
        lastCurrentUserPresenceError = value
    }

    func setCurrentUserPresenceWriteSupported(_ value: Bool?) {
        guard currentUserPresenceWriteSupported != value else { return }
        currentUserPresenceWriteSupported = value
    }

    func setLastCurrentUserPresenceWriteError(_ value: String?) {
        guard lastCurrentUserPresenceWriteError != value else { return }
        lastCurrentUserPresenceWriteError = value
    }

    func setSocialPeople(_ value: [XboxSocialPerson]) {
        guard socialPeople != value else { return }
        socialPeople = value
    }

    func setSocialPeopleTotalCount(_ value: Int) {
        guard socialPeopleTotalCount != value else { return }
        socialPeopleTotalCount = value
    }

    func setSocialPeopleLastUpdatedAt(_ value: Date?) {
        guard socialPeopleLastUpdatedAt != value else { return }
        socialPeopleLastUpdatedAt = value
    }

    func setIsLoadingSocialPeople(_ value: Bool) {
        guard isLoadingSocialPeople != value else { return }
        isLoadingSocialPeople = value
    }

    func setLastSocialPeopleError(_ value: String?) {
        guard lastSocialPeopleError != value else { return }
        lastSocialPeopleError = value
    }

    private func performLoadCurrentUserProfile(force: Bool) async {
        if let profileLoadWorkflow {
            await profileLoadWorkflow(self, force)
            return
        }
        if !force, currentUserProfile != nil { return }
        guard !isSuspendedForStreaming else { return }
        guard let credentials = await dependencies?.xboxWebCredentials(logContext: "profile fetch") else { return }
        guard !isSuspendedForStreaming else { return }

        do {
            let profile = try await XboxWebProfileClient(credentials: credentials).getCurrentUserProfile()
            guard !isSuspendedForStreaming else { return }
            currentUserProfile = profile
            dependencies?.updateProfileSettings(
                name: profile.preferredScreenName,
                imageURLString: profile.gameDisplayPicRaw?.absoluteString
            )
        } catch is CancellationError {
            return
        } catch {
            logger.warning("Failed to load Xbox profile: \(error.localizedDescription)")
        }
    }

    private func performLoadCurrentUserPresence(force: Bool) async {
        if let presenceLoadWorkflow {
            await presenceLoadWorkflow(self, force)
            return
        }
        if !force, currentUserPresence != nil { return }
        guard !isSuspendedForStreaming else { return }
        guard let credentials = await dependencies?.xboxWebCredentials(logContext: "presence fetch") else { return }
        guard !isSuspendedForStreaming else { return }

        isLoadingCurrentUserPresence = true
        defer { isLoadingCurrentUserPresence = false }

        do {
            let presence = try await XboxWebPresenceClient(credentials: credentials).getCurrentUserPresence(level: "all")
            guard !isSuspendedForStreaming else { return }
            currentUserPresence = presence
            lastCurrentUserPresenceError = nil

            if let xuid = presence.xuid,
               let profile = currentUserProfile,
               (profile.xuid?.isEmpty ?? true) {
                currentUserProfile = XboxCurrentUserProfile(
                    xuid: xuid,
                    gamertag: profile.gamertag,
                    gameDisplayName: profile.gameDisplayName,
                    gameDisplayPicRaw: profile.gameDisplayPicRaw,
                    gamerscore: profile.gamerscore
                )
            }
        } catch is CancellationError {
            return
        } catch {
            if case APIError.decodingError = error {
                lastCurrentUserPresenceError = "Xbox status sync unavailable right now."
            } else {
                lastCurrentUserPresenceError = error.localizedDescription
            }
            logger.warning("Failed to load Xbox presence: \(error.localizedDescription)")
        }
    }

    private func performLoadSocialPeople(force: Bool, maxItems: Int) async {
        if let socialLoadWorkflow {
            await socialLoadWorkflow(self, force, maxItems)
            return
        }
        if !force, isLoadingSocialPeople { return }
        if !force, !socialPeople.isEmpty, let lastUpdated = socialPeopleLastUpdatedAt {
            let age = Date().timeIntervalSince(lastUpdated)
            if age >= 0, age < 60 {
                return
            }
        }
        guard !isSuspendedForStreaming else { return }
        guard let credentials = await dependencies?.xboxWebCredentials(logContext: "social people fetch") else { return }
        guard !isSuspendedForStreaming else { return }

        isLoadingSocialPeople = true
        defer { isLoadingSocialPeople = false }

        do {
            let page = try await fetchSocialPeoplePage(credentials: credentials, maxItems: maxItems)
            guard !isSuspendedForStreaming else { return }
            let enrichedPeople = try? await enrichSocialPeople(page.people, credentials: credentials)
            guard !isSuspendedForStreaming else { return }
            socialPeopleTotalCount = page.totalCount
            socialPeople = (enrichedPeople ?? page.people).sorted(by: sortPeopleForProfileScreen)
            socialPeopleLastUpdatedAt = Date()
            lastSocialPeopleError = nil
            saveSocialCacheIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            logger.warning("Failed to load Xbox social people: \(error.localizedDescription)")
            if socialPeople.isEmpty {
                lastSocialPeopleError = error.localizedDescription
                socialPeopleTotalCount = 0
            } else {
                lastSocialPeopleError = "Showing cached friends while refresh failed."
            }
        }
    }

    func sortPeopleForProfileScreen(_ lhs: XboxSocialPerson, _ rhs: XboxSocialPerson) -> Bool {
        if lhs.isOnline != rhs.isOnline {
            return lhs.isOnline && !rhs.isOnline
        }
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }
        return lhs.preferredName.localizedCaseInsensitiveCompare(rhs.preferredName) == .orderedAscending
    }

    private func restorePresenceWriteCapabilityFromDefaults() {
        if defaults.object(forKey: DefaultsKey.presenceWriteSupported) != nil {
            currentUserPresenceWriteSupported = defaults.bool(forKey: DefaultsKey.presenceWriteSupported)
        }
    }

    private func isPresenceWriteUnsupported(code: Int, responseBody: String) -> Bool {
        if code == 405 || code == 501 {
            return true
        }
        if code == 400 || code == 403 || code == 404 {
            if responseBody.contains("valid methods are [get]")
                || responseBody.contains("method")
                || responseBody.contains("not allowed")
                || responseBody.contains("read-only")
                || responseBody.contains("titleid")
                || responseBody.contains("claim") {
                return true
            }
        }
        return false
    }

    private func fetchSocialPeoplePage(
        credentials: XboxWebCredentials,
        maxItems: Int
    ) async throws -> XboxSocialPeoplePage {
        let capped = max(1, min(maxItems, 96))
        let pageSize = 24
        let client = XboxSocialPeopleClient(credentials: credentials)

        var aggregated: [XboxSocialPerson] = []
        var totalCount = 0
        var startIndex = 0
        var seen = Set<String>()

        while aggregated.count < capped {
            let requested = min(pageSize, capped - aggregated.count)
            let page = try await client.getPeople(startIndex: startIndex, maxItems: requested)
            totalCount = max(totalCount, page.totalCount)
            if page.people.isEmpty {
                break
            }

            for person in page.people {
                if seen.insert(person.xuid).inserted {
                    aggregated.append(person)
                    if aggregated.count >= capped { break }
                }
            }

            startIndex += page.people.count
            if startIndex >= page.totalCount {
                break
            }
        }

        return XboxSocialPeoplePage(totalCount: max(totalCount, aggregated.count), people: aggregated)
    }

    // MARK: - Social cache

    func restoreSocialCacheFromDisk() async {
        guard !hasLoadedSocialCache else { return }
        hasLoadedSocialCache = true
        guard socialPeople.isEmpty else { return }
        guard let snapshot = await Self.loadSocialCacheSnapshot() else { return }
        guard snapshot.cacheVersion == Self.currentSocialCacheVersion else {
            logger.debug("Social cache version mismatch (got \(snapshot.cacheVersion), expected \(Self.currentSocialCacheVersion)) — discarding")
            return
        }
        applySocialCache(snapshot)
    }

    func saveSocialCacheIfNeeded() {
        let snapshot = SocialPeopleCacheSnapshot(
            lastUpdated: socialPeopleLastUpdatedAt ?? Date(),
            totalCount: socialPeopleTotalCount,
            people: socialPeople.map { person in
                SocialPersonCacheRecord(
                    xuid: person.xuid,
                    gamertag: person.gamertag,
                    displayName: person.displayName,
                    realName: person.realName,
                    displayPicRaw: person.displayPicRaw?.absoluteString,
                    gamerScore: person.gamerScore,
                    presenceState: person.presenceState,
                    presenceText: person.presenceText,
                    isFavorite: person.isFavorite,
                    isFollowingCaller: person.isFollowingCaller,
                    isFollowedByCaller: person.isFollowedByCaller
                )
            }
        )
        let url = Self.socialPeopleCacheURL
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func applySocialCache(_ snapshot: SocialPeopleCacheSnapshot) {
        guard socialPeople.isEmpty else { return }
        let restoredPeople = snapshot.people.map { person in
            XboxSocialPerson(
                xuid: person.xuid,
                gamertag: person.gamertag,
                displayName: person.displayName,
                realName: person.realName,
                displayPicRaw: person.displayPicRaw.flatMap(URL.init(string:)),
                gamerScore: person.gamerScore,
                presenceState: person.presenceState,
                presenceText: person.presenceText,
                isFavorite: person.isFavorite,
                isFollowingCaller: person.isFollowingCaller,
                isFollowedByCaller: person.isFollowedByCaller
            )
        }.sorted(by: sortPeopleForProfileScreen)
        setSocialPeople(restoredPeople)
        setSocialPeopleTotalCount(snapshot.totalCount)
        setSocialPeopleLastUpdatedAt(snapshot.lastUpdated)
        logger.info("Loaded \(restoredPeople.count) social person record(s) from disk cache")
    }

    nonisolated private static func loadSocialCacheSnapshot() async -> SocialPeopleCacheSnapshot? {
        await Task.detached(priority: .background) {
            guard let data = try? Data(contentsOf: Self.socialPeopleCacheURL, options: .mappedIfSafe) else {
                return nil
            }
            return try? JSONDecoder().decode(SocialPeopleCacheSnapshot.self, from: data)
        }.value
    }

    nonisolated private static var socialPeopleCacheURL: URL {
        MetadataCacheStore.url(for: "stratix.socialPeople.json")
    }

    private static let currentSocialCacheVersion = 1

    private func enrichSocialPeople(
        _ people: [XboxSocialPerson],
        credentials: XboxWebCredentials
    ) async throws -> [XboxSocialPerson] {
        let xuids = people.map(\.xuid)
        guard !xuids.isEmpty else { return people }

        let profileClient = XboxWebProfileClient(credentials: credentials)
        var profiles: [XboxCurrentUserProfile] = []
        for batch in xuids.chunked(into: 50) {
            let chunk = try await profileClient.getProfiles(userIds: batch)
            profiles.append(contentsOf: chunk)
        }
        var byXuid: [String: XboxCurrentUserProfile] = [:]
        for profile in profiles {
            guard let xuid = profile.xuid, !xuid.isEmpty else { continue }
            if byXuid[xuid] == nil {
                byXuid[xuid] = profile
            }
        }

        return people.map { person in
            guard let profile = byXuid[person.xuid] else { return person }
            return XboxSocialPerson(
                xuid: person.xuid,
                gamertag: person.gamertag ?? profile.gamertag,
                displayName: person.displayName ?? profile.gameDisplayName,
                realName: person.realName,
                displayPicRaw: person.displayPicRaw ?? profile.gameDisplayPicRaw,
                gamerScore: person.gamerScore ?? profile.gamerscore,
                presenceState: person.presenceState,
                presenceText: person.presenceText,
                isFavorite: person.isFavorite,
                isFollowingCaller: person.isFollowingCaller,
                isFollowedByCaller: person.isFollowedByCaller
            )
        }
    }
}

private struct SocialPeopleCacheSnapshot: Codable, Sendable {
    let lastUpdated: Date
    let totalCount: Int
    let people: [SocialPersonCacheRecord]
    let cacheVersion: Int

    private enum CodingKeys: String, CodingKey {
        case lastUpdated, totalCount, people, cacheVersion
    }

    init(lastUpdated: Date, totalCount: Int, people: [SocialPersonCacheRecord]) {
        self.lastUpdated = lastUpdated
        self.totalCount = totalCount
        self.people = people
        self.cacheVersion = 1
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        people = try container.decode([SocialPersonCacheRecord].self, forKey: .people)
        cacheVersion = (try? container.decode(Int.self, forKey: .cacheVersion)) ?? 0
    }
}

private struct SocialPersonCacheRecord: Codable, Sendable {
    let xuid: String
    let gamertag: String?
    let displayName: String?
    let realName: String?
    let displayPicRaw: String?
    let gamerScore: String?
    let presenceState: String?
    let presenceText: String?
    let isFavorite: Bool
    let isFollowingCaller: Bool
    let isFollowedByCaller: Bool
}
