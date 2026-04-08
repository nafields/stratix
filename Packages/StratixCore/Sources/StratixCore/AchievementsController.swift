// AchievementsController.swift
// Defines the achievements controller.
//

import Foundation
import Observation
import DiagnosticsKit
import StratixModels
import XCloudAPI

// MARK: - AchievementsController

/// Owns title achievement state, disk cache, and fetch/refresh lifecycle.
/// Extracted to provide a dedicated domain boundary for achievements.
/// Attached to controller dependencies during app startup.
@Observable
@MainActor
public final class AchievementsController {
    private struct AchievementLoadContext: Sendable {
        let titleID: TitleID
        let credentials: XboxWebCredentials
        let session: URLSession
        let cachedProfileXUID: String?
        let cachedPresenceXUID: String?
    }

    private struct AchievementLoadResult: Sendable {
        let snapshot: TitleAchievementSnapshot?
        let resolvedProfile: XboxCurrentUserProfile?
        let resolvedPresence: XboxCurrentUserPresence?
    }

    public private(set) var titleAchievementSnapshots: [TitleID: TitleAchievementSnapshot] = [:]
    public private(set) var lastTitleAchievementsErrorByTitleID: [TitleID: String] = [:]

    private enum TaskGroupID {
        static let titleAchievements = "titleAchievements"
    }

    @ObservationIgnored let taskRegistry = TaskRegistry()
    @ObservationIgnored private weak var dependencies: (any AchievementsControllerDependencies)?
    @ObservationIgnored private let logger = GLogger(category: .api)
    @ObservationIgnored private var hasLoadedCache = false
    @ObservationIgnored private var isSuspendedForStreaming = false

    /// Injected load workflow — used in tests to avoid real network calls.
    @ObservationIgnored private let loadWorkflow: (@MainActor (AchievementsController, TitleID, Bool) async -> Void)?

    public init(loadWorkflow: (@MainActor (AchievementsController, TitleID, Bool) async -> Void)? = nil) {
        self.loadWorkflow = loadWorkflow
    }

    func attach(_ dependencies: any AchievementsControllerDependencies) {
        self.dependencies = dependencies
    }

    private static let currentCacheVersion = 1

    // MARK: - Reset

    public func resetForSignOut() async {
        isSuspendedForStreaming = false
        titleAchievementSnapshots = [:]
        lastTitleAchievementsErrorByTitleID = [:]
        hasLoadedCache = false
        await taskRegistry.cancelAll()
    }

    public func clearPersistedAchievementCache() {
        try? FileManager.default.removeItem(at: Self.titleAchievementsCacheURL)
    }

    // MARK: - Cache restore

    public func restoreDiskCachesIfNeeded(isAuthenticated: Bool) async {
        guard isAuthenticated else { return }
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        guard let snapshot = await Self.loadTitleAchievementsCacheSnapshot() else { return }
        guard snapshot.cacheVersion == Self.currentCacheVersion else {
            logger.debug("Achievement cache version mismatch (got \(snapshot.cacheVersion), expected \(Self.currentCacheVersion)) — discarding")
            return
        }
        applyTitleAchievementsCache(snapshot)
    }

    // MARK: - Public accessors

    public func titleAchievementSnapshot(titleID: TitleID) -> TitleAchievementSnapshot? {
        guard let normalizedTitleID = normalizedTitleID(titleID) else { return nil }
        return titleAchievementSnapshots[normalizedTitleID]
    }

    public func lastTitleAchievementsError(titleID: TitleID) -> String? {
        guard let normalizedTitleID = normalizedTitleID(titleID) else { return nil }
        return lastTitleAchievementsErrorByTitleID[normalizedTitleID]
    }

    public func setTitleAchievementSnapshots(_ value: [TitleID: TitleAchievementSnapshot]) {
        guard titleAchievementSnapshots != value else { return }
        titleAchievementSnapshots = value
    }

    public func setLastTitleAchievementsErrorByTitleID(_ value: [TitleID: String]) {
        guard lastTitleAchievementsErrorByTitleID != value else { return }
        lastTitleAchievementsErrorByTitleID = value
    }

    // MARK: - Fetch

    public func loadTitleAchievements(
        titleID: TitleID,
        forceRefresh: Bool = false
    ) async {
        guard !isSuspendedForStreaming else { return }
        guard let normalizedTitleID = normalizedTitleID(titleID) else { return }
        let taskKey = normalizedTitleID.rawValue

        if !forceRefresh, let cachedSnapshot = titleAchievementSnapshots[normalizedTitleID] {
            let ageSeconds = Date().timeIntervalSince(cachedSnapshot.fetchedAt)
            let isMissingAchievements = cachedSnapshot.summary.totalAchievements == 0
                && cachedSnapshot.summary.unlockedAchievements == 0
                && cachedSnapshot.achievements.isEmpty
            guard ageSeconds < 0 || ageSeconds >= 300 || isMissingAchievements else { return }
        }

        let (task, inserted) = await taskRegistry.taskOrRegister(
            group: TaskGroupID.titleAchievements,
            key: taskKey,
            makeTask: {
                Task { [weak self] in
                    guard let self else { return }
                    guard await self.isSuspendedForStreaming == false else { return }

                    if let loadWorkflow = self.loadWorkflow {
                        await loadWorkflow(self, titleID, forceRefresh)
                        return
                    }

                    guard let context = await self.makeAchievementLoadContext(titleID: titleID) else { return }
                    guard await self.isSuspendedForStreaming == false else { return }

                    do {
                        let loadResult = try await Self.loadAchievements(context: context)
                        await self.applyAchievementLoadResult(loadResult, key: normalizedTitleID)
                    } catch is CancellationError {
                        return
                    } catch {
                        await self.handleAchievementLoadFailure(error, titleID: titleID, key: normalizedTitleID)
                    }
                }
            }
        )
        let action = inserted ? "starting" : "join existing"
        logger.info("Title achievements \(action) request: \(taskKey)")
        await task.value
        if inserted {
            await taskRegistry.remove(group: TaskGroupID.titleAchievements, key: taskKey)
        }
    }

    func suspendForStreaming() async {
        isSuspendedForStreaming = true
        await taskRegistry.cancelAll()
    }

    func resumeAfterStreaming() {
        isSuspendedForStreaming = false
    }

    // MARK: - Private helpers

    private func makeAchievementLoadContext(titleID: TitleID) async -> AchievementLoadContext? {
        guard let credentials = await dependencies?.xboxWebCredentials(logContext: "achievements fetch") else {
            return nil
        }
        return AchievementLoadContext(
            titleID: titleID,
            credentials: credentials,
            session: dependencies?.apiSession() ?? .shared,
            cachedProfileXUID: dependencies?.currentUserProfileXUID(),
            cachedPresenceXUID: dependencies?.currentUserPresenceXUID()
        )
    }

    private func applyAchievementLoadResult(_ loadResult: AchievementLoadResult, key: TitleID) {
        guard !isSuspendedForStreaming else { return }
        if let resolvedProfile = loadResult.resolvedProfile {
            dependencies?.cacheCurrentUserProfile(resolvedProfile)
        }
        if let resolvedPresence = loadResult.resolvedPresence {
            dependencies?.cacheCurrentUserPresence(resolvedPresence)
        }
        guard let snapshot = loadResult.snapshot else {
            lastTitleAchievementsErrorByTitleID[key] = "Achievements data is unavailable for this title."
            return
        }

        titleAchievementSnapshots[key] = snapshot
        lastTitleAchievementsErrorByTitleID[key] = nil
        dependencies?.upsertAchievementSummary(snapshot.summary)
        saveTitleAchievementsCache()
    }

    private func handleAchievementLoadFailure(_ error: Error, titleID: TitleID, key: TitleID) {
        let message = logString(for: error)
        logger.warning("Failed to load achievements for \(titleID.rawValue): \(message)")
        lastTitleAchievementsErrorByTitleID[key] = "Couldn't load achievements right now."
    }

    private func applyTitleAchievementsCache(_ snapshot: TitleAchievementsCacheSnapshot) {
        var mergedSnapshots = titleAchievementSnapshots
        for cachedSnapshot in snapshot.snapshots {
            guard let key = normalizedTitleID(cachedSnapshot.titleId) else { continue }
            guard mergedSnapshots[key] == nil else { continue }
            mergedSnapshots[key] = cachedSnapshot
        }
        titleAchievementSnapshots = mergedSnapshots
        logger.info("Loaded \(snapshot.snapshots.count) title achievement snapshot(s) from disk cache")
    }

    private func saveTitleAchievementsCache() {
        let snapshot = TitleAchievementsCacheSnapshot(
            savedAt: Date(),
            snapshots: Array(titleAchievementSnapshots.values)
        )
        let url = Self.titleAchievementsCacheURL
        Task.detached(priority: .background) {
            guard let encodedSnapshot = try? JSONEncoder().encode(snapshot) else { return }
            try? encodedSnapshot.write(to: url, options: .atomic)
        }
    }

    private func normalizedTitleID(_ titleId: String) -> TitleID? {
        let normalized = titleId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return TitleID(normalized)
    }

    private func normalizedTitleID(_ titleID: TitleID) -> TitleID? {
        normalizedTitleID(titleID.rawValue)
    }

    private func logString(for error: Error) -> String {
        if case let APIError.httpError(code, body) = error {
            return "HTTP \(code): \(truncateForLog(body))"
        }
        if case let APIError.decodingError(message) = error {
            return "Decode: \(message)"
        }
        return error.localizedDescription
    }

    private func truncateForLog(_ text: String, maxBytes: Int = 2048) -> String {
        if text.utf8.count <= maxBytes { return text }
        let prefix = String(text.prefix(maxBytes))
        return "\(prefix)…"
    }

    private nonisolated static func loadAchievements(
        context: AchievementLoadContext
    ) async throws -> AchievementLoadResult {
        let xuidResult = try await resolveAchievementsXuid(context: context)
        let client = XboxAchievementsClient(
            credentials: context.credentials,
            xuid: xuidResult.xuid,
            session: context.session
        )
        let snapshot = try await client.getTitleAchievementSnapshot(titleId: context.titleID.rawValue)
        return AchievementLoadResult(
            snapshot: snapshot,
            resolvedProfile: xuidResult.profile,
            resolvedPresence: xuidResult.presence
        )
    }

    private nonisolated static func resolveAchievementsXuid(
        context: AchievementLoadContext
    ) async throws -> (xuid: String?, profile: XboxCurrentUserProfile?, presence: XboxCurrentUserPresence?) {
        if let xuid = normalizedXUID(context.cachedProfileXUID) {
            return (xuid, nil, nil)
        }
        if let xuid = normalizedXUID(context.cachedPresenceXUID) {
            return (xuid, nil, nil)
        }

        if let profile = try? await XboxWebProfileClient(
            credentials: context.credentials,
            session: context.session
        ).getCurrentUserProfile(),
           let xuid = normalizedXUID(profile.xuid) {
            return (xuid, profile, nil)
        }
        if let presence = try? await XboxWebPresenceClient(
            credentials: context.credentials,
            session: context.session
        ).getCurrentUserPresence(level: "all"),
           let xuid = normalizedXUID(presence.xuid) {
            return (xuid, nil, presence)
        }
        return (nil, nil, nil)
    }

    private nonisolated static func normalizedXUID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Cache persistence

private extension AchievementsController {
    nonisolated static var titleAchievementsCacheURL: URL {
        MetadataCacheStore.url(for: "stratix.titleAchievements.json")
    }

    nonisolated static func loadTitleAchievementsCacheSnapshot() async -> TitleAchievementsCacheSnapshot? {
        await Task.detached(priority: .background) {
            guard let cacheData = try? Data(contentsOf: Self.titleAchievementsCacheURL, options: .mappedIfSafe) else {
                return nil
            }
            return try? JSONDecoder().decode(TitleAchievementsCacheSnapshot.self, from: cacheData)
        }.value
    }
}

private struct TitleAchievementsCacheSnapshot: Codable, Sendable {
    let savedAt: Date
    let snapshots: [TitleAchievementSnapshot]
    let cacheVersion: Int

    private enum CodingKeys: String, CodingKey {
        case savedAt, snapshots, cacheVersion
    }

    init(savedAt: Date, snapshots: [TitleAchievementSnapshot], cacheVersion: Int = 1) {
        self.savedAt = savedAt
        self.snapshots = snapshots
        self.cacheVersion = cacheVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        snapshots = try container.decode([TitleAchievementSnapshot].self, forKey: .snapshots)
        cacheVersion = (try? container.decode(Int.self, forKey: .cacheVersion)) ?? 0
    }
}
