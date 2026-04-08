// AppSignOutWorkflowTests.swift
// Exercises app sign out workflow behavior.
//

import Testing
@testable import StratixCore

@MainActor
@Suite
struct AppSignOutWorkflowTests {
    @Test
    func run_executesEveryResetStepInOrder() async {
        let workflow = AppSignOutWorkflow()
        var events: [String] = []

        await workflow.run(
            environment: AppSignOutEnvironment(
                resetConsole: { events.append("console") },
                resetLibrary: { events.append("library") },
                clearLibraryCaches: { events.append("libraryCaches") },
                resetShellBootstrap: { events.append("shellBootstrap") },
                resetAchievements: { events.append("achievements") },
                clearAchievementCaches: { events.append("achievementCaches") },
                clearProfileCaches: { events.append("profileCaches") },
                resetStream: { events.append("stream") },
                resetInput: { events.append("input") },
                resetProfile: { events.append("profile") }
            )
        )

        #expect(events == [
            "console",
            "library",
            "libraryCaches",
            "shellBootstrap",
            "achievements",
            "achievementCaches",
            "profileCaches",
            "stream",
            "input",
            "profile",
        ])
    }
}
