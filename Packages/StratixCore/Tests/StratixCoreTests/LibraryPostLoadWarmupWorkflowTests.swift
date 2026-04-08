// LibraryPostLoadWarmupWorkflowTests.swift
// Exercises library post load warmup workflow behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing
import XCloudAPI

@MainActor
@Suite(.serialized)
struct LibraryPostLoadWarmupWorkflowTests {
    @Test
    func warmProfileAndSocialAfterLibraryLoad_requestsProfileAndSocialWarmup() async {
        let controller = LibraryController()
        let dependencies = TestLibraryControllerDependencies()
        controller.attach(dependencies)

        await controller.warmProfileAndSocialAfterLibraryLoad()
        for _ in 0..<10 {
            if await dependencies.profileLoads == 1 {
                break
            }
            await Task.yield()
        }

        #expect(await dependencies.profileLoads == 1)
        #expect(await dependencies.socialLoads == [48])
    }

    @Test
    func warmProfileAndSocialAfterLibraryLoad_skipsWhenSuspendedForStreaming() async {
        let controller = LibraryController()
        let dependencies = TestLibraryControllerDependencies()
        controller.attach(dependencies)

        await controller.suspendForStreaming()
        await controller.warmProfileAndSocialAfterLibraryLoad()

        #expect(await dependencies.profileLoads == 0)
        #expect(await dependencies.socialLoads.isEmpty)
    }
}

@MainActor
private final class TestLibraryControllerDependencies: LibraryControllerDependencies {
    private let recorder = WarmupRecorder()

    var profileLoads: Int {
        get async { await recorder.profileLoads }
    }

    var socialLoads: [Int] {
        get async { await recorder.socialLoads }
    }

    func authenticatedLibraryTokens() -> StreamTokens? {
        nil
    }

    func refreshStreamTokens(logContext: String) async throws -> StreamTokens {
        StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: "https://xcloud.example.com",
            xcloudF2PToken: nil,
            xcloudF2PHost: nil
        )
    }

    func xboxWebCredentials(logContext: String) async -> XboxWebCredentials? {
        nil
    }

    func achievementSnapshot(titleID: TitleID) -> TitleAchievementSnapshot? {
        nil
    }

    func loadCurrentUserProfile() async {
        await recorder.recordProfileLoad()
    }

    func loadSocialPeople(maxItems: Int) async {
        await recorder.recordSocialLoad(maxItems)
    }
}

private actor WarmupRecorder {
    private(set) var profileLoads = 0
    private(set) var socialLoads: [Int] = []

    func recordProfileLoad() {
        profileLoads += 1
    }

    func recordSocialLoad(_ maxItems: Int) {
        socialLoads.append(maxItems)
    }
}
