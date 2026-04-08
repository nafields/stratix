// AchievementsControllerTests.swift
// Exercises achievements controller behavior.
//

import Foundation
import Testing
import StratixModels
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct AchievementsControllerTests {
    @Test
    func suspendForStreaming_blocksAchievementLoadsUntilResumed() async {
        let counter = CounterBox()
        let controller = AchievementsController(loadWorkflow: { _, _, _ in
            counter.value += 1
        })

        await controller.suspendForStreaming()
        await controller.loadTitleAchievements(titleID: TitleID("title-1"), forceRefresh: true)

        #expect(counter.value == 0)

        controller.resumeAfterStreaming()
        await controller.loadTitleAchievements(titleID: TitleID("title-1"), forceRefresh: true)

        #expect(counter.value == 1)
    }

    @Test
    func typedTitleIDCachesRemainAuthoritative() async {
        let controller = AchievementsController()
        let titleID = TitleID("halo-title")
        let snapshot = TitleAchievementSnapshot(
            titleId: "HALO-TITLE",
            summary: TitleAchievementSummary(
                titleId: "HALO-TITLE",
                titleName: "Halo Infinite",
                totalAchievements: 10,
                unlockedAchievements: 5,
                totalGamerscore: 1000,
                unlockedGamerscore: 500
            ),
            achievements: []
        )

        controller.setTitleAchievementSnapshots([TitleID("halo-title"): snapshot])
        controller.setLastTitleAchievementsErrorByTitleID([TitleID("halo-title"): "offline"])

        #expect(controller.titleAchievementSnapshot(titleID: titleID)?.summary.titleName == "Halo Infinite")
        #expect(controller.lastTitleAchievementsError(titleID: titleID) == "offline")
    }
}

@MainActor
private final class CounterBox {
    var value = 0
}
