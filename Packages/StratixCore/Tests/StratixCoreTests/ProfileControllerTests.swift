// ProfileControllerTests.swift
// Exercises profile controller behavior.
//

import Foundation
import Testing
@testable import StratixCore
import XCloudAPI

@MainActor
@Suite(.serialized)
struct ProfileControllerTests {
    @Test
    func refresh_invokesAllProfileWorkflows() async {
        let profileLoadCount = CounterBox()
        let presenceLoadCount = CounterBox()
        let socialLoadCount = CounterBox()

        let controller = ProfileController(
            profileLoadWorkflow: { _, force in
                #expect(force == true)
                profileLoadCount.value += 1
            },
            presenceLoadWorkflow: { _, force in
                #expect(force == true)
                presenceLoadCount.value += 1
            },
            socialLoadWorkflow: { _, force, maxItems in
                #expect(force == true)
                #expect(maxItems == 96)
                socialLoadCount.value += 1
            }
        )

        await controller.refresh(force: true)

        #expect(profileLoadCount.value == 1)
        #expect(presenceLoadCount.value == 1)
        #expect(socialLoadCount.value == 1)
    }

    @Test
    func suspendForStreaming_blocksRefreshUntilResumed() async {
        let profileLoadCount = CounterBox()
        let presenceLoadCount = CounterBox()
        let socialLoadCount = CounterBox()

        let controller = ProfileController(
            profileLoadWorkflow: { _, _ in
                profileLoadCount.value += 1
            },
            presenceLoadWorkflow: { _, _ in
                presenceLoadCount.value += 1
            },
            socialLoadWorkflow: { _, _, _ in
                socialLoadCount.value += 1
            }
        )

        await controller.suspendForStreaming()
        await controller.refresh(force: true)

        #expect(profileLoadCount.value == 0)
        #expect(presenceLoadCount.value == 0)
        #expect(socialLoadCount.value == 0)

        controller.resumeAfterStreaming()
        await controller.refresh(force: true)

        #expect(profileLoadCount.value == 1)
        #expect(presenceLoadCount.value == 1)
        #expect(socialLoadCount.value == 1)
    }

    @Test
    func setCurrentUserPresence_usesInjectedWorkflowResult() async {
        let controller = ProfileController(
            presenceSetWorkflow: { _, isOnline in
                #expect(isOnline == false)
                return true
            }
        )

        let result = await controller.setCurrentUserPresence(isOnline: false)

        #expect(result == true)
    }

    @Test
    func sortPeopleForProfileScreen_prioritizesOnlineThenFavoritesThenName() {
        let controller = ProfileController()
        let people = [
            makePerson(xuid: "3", displayName: "Charlie", isOnline: false, isFavorite: false),
            makePerson(xuid: "2", displayName: "Bravo", isOnline: true, isFavorite: false),
            makePerson(xuid: "1", displayName: "Alpha", isOnline: true, isFavorite: true),
            makePerson(xuid: "4", displayName: "Delta", isOnline: false, isFavorite: true)
        ]

        let sorted = people.sorted(by: controller.sortPeopleForProfileScreen)

        #expect(sorted.map(\.xuid) == ["1", "2", "4", "3"])
    }

    @Test
    func resetForSignOut_clearsProfilePresenceAndSocialState() {
        let controller = ProfileController()
        controller.setCurrentUserProfile(
            XboxCurrentUserProfile(
                xuid: "xuid-1",
                gamertag: "gamertag",
                gameDisplayName: "display",
                gameDisplayPicRaw: URL(string: "https://example.com/pic.png"),
                gamerscore: "12345"
            )
        )
        controller.setCurrentUserPresence(
            XboxCurrentUserPresence(
                xuid: "xuid-1",
                state: "Online",
                devices: [],
                lastSeen: nil
            )
        )
        controller.setIsLoadingCurrentUserPresence(true)
        controller.setLastCurrentUserPresenceError("presence read error")
        controller.setCurrentUserPresenceWriteSupported(true)
        controller.setLastCurrentUserPresenceWriteError("presence write error")
        controller.setSocialPeople([makePerson(xuid: "1", displayName: "Alpha", isOnline: true, isFavorite: false)])
        controller.setSocialPeopleTotalCount(1)
        controller.setSocialPeopleLastUpdatedAt(Date())
        controller.setIsLoadingSocialPeople(true)
        controller.setLastSocialPeopleError("social error")

        controller.resetForSignOut()

        #expect(controller.currentUserProfile == nil)
        #expect(controller.currentUserPresence == nil)
        #expect(controller.isLoadingCurrentUserPresence == false)
        #expect(controller.lastCurrentUserPresenceError == nil)
        #expect(controller.currentUserPresenceWriteSupported == nil)
        #expect(controller.lastCurrentUserPresenceWriteError == nil)
        #expect(controller.socialPeople.isEmpty)
        #expect(controller.socialPeopleTotalCount == 0)
        #expect(controller.socialPeopleLastUpdatedAt == nil)
        #expect(controller.isLoadingSocialPeople == false)
        #expect(controller.lastSocialPeopleError == nil)
    }

    private func makePerson(
        xuid: String,
        displayName: String,
        isOnline: Bool,
        isFavorite: Bool
    ) -> XboxSocialPerson {
        XboxSocialPerson(
            xuid: xuid,
            gamertag: displayName,
            displayName: displayName,
            realName: nil,
            displayPicRaw: nil,
            gamerScore: nil,
            presenceState: isOnline ? "Online" : "Offline",
            presenceText: nil,
            isFavorite: isFavorite,
            isFollowingCaller: false,
            isFollowedByCaller: false
        )
    }
}

@MainActor
private final class CounterBox {
    var value = 0
}
