// StreamOverlayVisibilityCoordinatorTests.swift
// Exercises stream overlay visibility coordinator behavior.
//

import Foundation
import Testing
import DiagnosticsKit
import os
@testable import StratixCore
import StratixModels

@MainActor
@Suite(.serialized)
struct StreamOverlayVisibilityCoordinatorTests {
    @Test
    func setVisibility_visibleLoadsHeroAndAchievementsThroughCollaborators() async {
        let coordinator = StreamOverlayVisibilityCoordinator()
        let titleId = makeTitleID()
        let heroURL = URL(string: "https://example.com/hero.jpg")
        let achievementSnapshot = TitleAchievementSnapshot(
            titleId: titleId.rawValue,
            summary: TitleAchievementSummary(
                titleId: titleId.rawValue,
                titleName: "Halo Infinite",
                totalAchievements: 10,
                unlockedAchievements: 2,
                totalGamerscore: 1000,
                unlockedGamerscore: 200
            ),
            achievements: []
        )
        var inputEvents: [String] = []
        let state = StreamReducer.reduce(
            state: StreamReducer.reduce(
                state: StreamState.empty,
                action: .activeLaunchTargetSet(.cloud(titleId))
            ),
            action: .streamingSessionSet(makeStreamingSession())
        )

        let actions = await coordinator.setVisibility(
            true,
            trigger: .automatic,
            state: state,
            environment: StreamOverlayEnvironment(
                heroArtworkEnvironment: makeHeroArtworkEnvironment(
                    cachedItem: { _ in
                        CloudLibraryItem(
                            titleId: titleId.rawValue,
                            productId: "product-1",
                            name: "Halo Infinite",
                            shortDescription: nil,
                            artURL: nil,
                            posterImageURL: nil,
                            heroImageURL: heroURL,
                            supportedInputTypes: [],
                            isInMRU: false
                        )
                    }
                ),
                achievementEnvironment: StreamAchievementLoadEnvironment(
                    activeTitleId: { titleId },
                    loadSnapshot: { _, _ in achievementSnapshot },
                    loadError: { _ in nil }
                ),
                shouldContinuePresentationRefresh: { false },
                publishRefreshResult: { _ in },
                injectNeutralFrame: { inputEvents.append("neutral") },
                injectPauseMenuTap: { inputEvents.append("pause") }
            )
        )
        await coordinator.stopPresentationRefresh()

        #expect(actions.contains(.overlayVisibilityChanged(true, trigger: .automatic)))
        #expect(actions.contains(.launchHeroURLSet(heroURL)))
        #expect(actions.contains(.achievementSnapshotSet(achievementSnapshot)))
        #expect(actions.contains(.achievementErrorSet(nil)))
        #expect(inputEvents == ["neutral", "pause"])
    }

    @Test
    func setVisibility_hiddenClearsAchievementStateAndStopsPresentationRefresh() async {
        let coordinator = StreamOverlayVisibilityCoordinator()
        var inputEvents: [String] = []
        let state = StreamReducer.reduce(
            state: StreamReducer.reduce(
                state: StreamState.empty,
                action: .overlayVisibilityChanged(true, trigger: .automatic)
            ),
            action: .streamingSessionSet(makeStreamingSession())
        )

        let actions = await coordinator.setVisibility(
            false,
            trigger: .automatic,
            state: state,
            environment: StreamOverlayEnvironment(
                heroArtworkEnvironment: nil,
                achievementEnvironment: nil,
                shouldContinuePresentationRefresh: { false },
                publishRefreshResult: { _ in },
                injectNeutralFrame: { inputEvents.append("neutral") },
                injectPauseMenuTap: { inputEvents.append("pause") }
            )
        )
        await coordinator.stopPresentationRefresh()

        #expect(actions.contains(.overlayVisibilityChanged(false, trigger: .automatic)))
        #expect(actions.contains(.achievementSnapshotSet(nil)))
        #expect(actions.contains(.achievementErrorSet(nil)))
        #expect(inputEvents == ["neutral"])
    }

    @Test
    func setVisibility_visibleRecordsOverlayLatencyMilestone() async {
        let coordinator = StreamOverlayVisibilityCoordinator()
        let titleId = makeTitleID()
        let state = StreamReducer.reduce(
            state: StreamReducer.reduce(
                state: StreamReducer.reduce(
                    state: StreamState.empty,
                    action: .activeLaunchTargetSet(.cloud(titleId))
                ),
                action: .streamingSessionSet(makeStreamingSession())
            ),
            action: .overlayVisibilityChanged(false, trigger: .automatic)
        )
        let records = OSAllocatedUnfairLock(initialState: [StreamMetricsRecord]())
        let token = StreamMetricsPipeline.shared.registerSink(
            StreamMetricsSink(name: #function) { record in
                records.withLock { $0.append(record) }
            }
        )
        defer { StreamMetricsPipeline.shared.unregisterSink(token) }
        StreamMetricsPipeline.shared.recordMilestone(
            .launchRequested,
            context: .cloud,
            targetID: titleId.rawValue,
            timestamp: Date(timeIntervalSince1970: 10)
        )

        _ = await coordinator.setVisibility(
            true,
            trigger: .userToggle,
            state: state,
            environment: StreamOverlayEnvironment(
                heroArtworkEnvironment: nil,
                achievementEnvironment: nil,
                shouldContinuePresentationRefresh: { false },
                publishRefreshResult: { _ in },
                injectNeutralFrame: {},
                injectPauseMenuTap: {}
            )
        )

        let overlayRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone.milestone == .overlayOpened && milestone.targetID == titleId.rawValue ? milestone : nil
            }
        }
        #expect(overlayRecords.contains { $0.context == StreamMetricsLaunchContext.cloud })
        #expect(overlayRecords.contains { $0.overlayTrigger == "userToggle" })
        #expect(overlayRecords.contains { $0.latencyMs != nil })
    }
}
