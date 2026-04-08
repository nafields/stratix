// StreamAchievementRefreshCoordinatorTests.swift
// Exercises stream achievement refresh coordinator behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

@Suite(.serialized)
struct StreamAchievementRefreshCoordinatorTests {
    private let titleId = TitleID("1234")

    @Test
    func loadAchievements_returnsSnapshotOnlyWhenActiveTitleStillMatches() async {
        let coordinator = StreamAchievementRefreshCoordinator()
        let snapshot = TitleAchievementSnapshot(
            titleId: titleId.rawValue,
            summary: TitleAchievementSummary(
                titleId: titleId.rawValue,
                titleName: "Halo Infinite",
                totalAchievements: 0,
                unlockedAchievements: 0,
                totalGamerscore: 0,
                unlockedGamerscore: 0
            ),
            achievements: []
        )

        let matching = await coordinator.loadAchievements(
            titleId: titleId,
            activeTitleProvider: { titleId },
            load: { _ in snapshot },
            loadError: { _ in nil }
        )
        let mismatched = await coordinator.loadAchievements(
            titleId: titleId,
            activeTitleProvider: { TitleID("9999") },
            load: { _ in snapshot },
            loadError: { _ in "stale" }
        )

        #expect(matching.snapshot == snapshot)
        #expect(matching.error == nil)
        #expect(mismatched.snapshot == nil)
        #expect(mismatched.error == nil)
    }

    @Test
    func loadAchievements_returnsErrorTextFromLoader() async {
        let coordinator = StreamAchievementRefreshCoordinator()
        let result = await coordinator.loadAchievements(
            titleId: titleId,
            activeTitleProvider: { titleId },
            load: { _ in nil },
            loadError: { _ in "failed" }
        )

        #expect(result.snapshot == nil)
        #expect(result.error == "failed")
    }
}
