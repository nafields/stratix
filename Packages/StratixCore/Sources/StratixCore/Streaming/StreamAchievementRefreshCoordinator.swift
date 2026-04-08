// StreamAchievementRefreshCoordinator.swift
// Defines the stream achievement refresh coordinator for the Streaming surface.
//

import Foundation
import StratixModels

actor StreamAchievementRefreshCoordinator {
    private let taskRegistry = TaskRegistry()

    private enum TaskID {
        static let periodicRefresh = "stream.achievementsRefresh"
    }

    func startPeriodicRefresh(
        titleId: TitleID,
        activeTitleProvider: @escaping @Sendable () async -> TitleID?,
        shouldContinue: @escaping @Sendable () async -> Bool,
        refresh: @escaping @Sendable () async -> Void
    ) async {
        await stopPeriodicRefresh()
        guard let expectedTitleID = normalizedTitleID(titleId) else { return }

        let registry = taskRegistry
        _ = await taskRegistry.register(Task { [registry] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                guard normalizedTitleID(await activeTitleProvider()) == expectedTitleID else { continue }
                guard await shouldContinue() else { continue }
                await refresh()
            }
            await registry.remove(id: TaskID.periodicRefresh)
        }, id: TaskID.periodicRefresh)
    }

    func stopPeriodicRefresh() async {
        await taskRegistry.cancel(id: TaskID.periodicRefresh)
    }

    func loadAchievements(
        titleId: TitleID,
        activeTitleProvider: @escaping @Sendable () async -> TitleID?,
        load: @escaping @Sendable (TitleID) async -> TitleAchievementSnapshot?,
        loadError: @escaping @Sendable (TitleID) async -> String?
    ) async -> (snapshot: TitleAchievementSnapshot?, error: String?) {
        guard let expectedTitleID = normalizedTitleID(titleId) else {
            return (nil, nil)
        }

        let snapshot = await load(titleId)
        let error = await loadError(titleId)

        guard normalizedTitleID(await activeTitleProvider()) == expectedTitleID else {
            return (nil, nil)
        }

        return (snapshot, error)
    }

    private func normalizedTitleID(_ titleId: String) -> TitleID? {
        let normalized = titleId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return TitleID(normalized)
    }

    private func normalizedTitleID(_ titleId: TitleID?) -> TitleID? {
        guard let titleId else { return nil }
        return normalizedTitleID(titleId.rawValue)
    }
}
