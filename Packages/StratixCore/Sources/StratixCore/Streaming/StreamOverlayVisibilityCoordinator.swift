// StreamOverlayVisibilityCoordinator.swift
// Defines the stream overlay visibility coordinator for the Streaming surface.
//

import Foundation
import DiagnosticsKit
import StratixModels

struct StreamAchievementLoadEnvironment: Sendable {
    let activeTitleId: @Sendable () async -> TitleID?
    let loadSnapshot: @Sendable (TitleID, Bool) async -> TitleAchievementSnapshot?
    let loadError: @Sendable (TitleID) async -> String?
}

struct StreamOverlayEnvironment: Sendable {
    let heroArtworkEnvironment: StreamHeroArtworkEnvironment?
    let achievementEnvironment: StreamAchievementLoadEnvironment?
    let shouldContinuePresentationRefresh: @Sendable () async -> Bool
    let publishRefreshResult: @Sendable @MainActor ([StreamAction]) -> Void
    let injectNeutralFrame: @Sendable @MainActor () -> Void
    let injectPauseMenuTap: @Sendable @MainActor () -> Void
}

actor StreamOverlayVisibilityCoordinator {
    private let overlayInputPolicy: StreamOverlayInputPolicy
    private let achievementRefreshCoordinator: StreamAchievementRefreshCoordinator
    private let heroArtworkService: StreamHeroArtworkService

    init(
        overlayInputPolicy: StreamOverlayInputPolicy = StreamOverlayInputPolicy(),
        achievementRefreshCoordinator: StreamAchievementRefreshCoordinator = StreamAchievementRefreshCoordinator(),
        heroArtworkService: StreamHeroArtworkService = StreamHeroArtworkService()
    ) {
        self.overlayInputPolicy = overlayInputPolicy
        self.achievementRefreshCoordinator = achievementRefreshCoordinator
        self.heroArtworkService = heroArtworkService
    }

    func setVisibility(
        _ visible: Bool,
        trigger: StreamOverlayTrigger,
        state: StreamState,
        environment: StreamOverlayEnvironment
    ) async -> [StreamAction] {
        guard state.isStreamOverlayVisible != visible else { return [] }

        var actions: [StreamAction] = [
            .overlayVisibilityChanged(visible, trigger: trigger)
        ]

        let overlayContext = StreamOverlayVisibilityChangeContext(
            oldVisible: state.isStreamOverlayVisible,
            newVisible: visible,
            hasStreamingSession: state.streamingSession != nil,
            disconnectArmed: state.isStreamOverlayVisible && state.streamingSession != nil,
            trigger: trigger
        )
        let inputDecision = overlayInputPolicy.inputDecision(for: overlayContext)

        if visible,
           let titleId = state.activeLaunchTarget?.titleId,
           let heroArtworkEnvironment = environment.heroArtworkEnvironment,
           let achievementEnvironment = environment.achievementEnvironment {
            let heroURL = await heroArtworkService.resolveLaunchHeroURL(
                titleId: titleId,
                currentHeroURL: state.launchHeroURL,
                environment: heroArtworkEnvironment
            )
            actions.append(.launchHeroURLSet(heroURL))

            let achievementResult = await achievementRefreshCoordinator.loadAchievements(
                titleId: titleId,
                activeTitleProvider: achievementEnvironment.activeTitleId,
                load: { requestedTitleId in
                    await achievementEnvironment.loadSnapshot(requestedTitleId, false)
                },
                loadError: achievementEnvironment.loadError
            )
            actions.append(contentsOf: [
                .achievementSnapshotSet(achievementResult.snapshot),
                .achievementErrorSet(achievementResult.error)
            ])

            await achievementRefreshCoordinator.startPeriodicRefresh(
                titleId: titleId,
                activeTitleProvider: achievementEnvironment.activeTitleId,
                shouldContinue: environment.shouldContinuePresentationRefresh,
                refresh: {
                    let result = await self.achievementRefreshCoordinator.loadAchievements(
                        titleId: titleId,
                        activeTitleProvider: achievementEnvironment.activeTitleId,
                        load: { requestedTitleId in
                            await achievementEnvironment.loadSnapshot(requestedTitleId, true)
                        },
                        loadError: achievementEnvironment.loadError
                    )
                    await environment.publishRefreshResult([
                        .achievementSnapshotSet(result.snapshot),
                        .achievementErrorSet(result.error)
                    ])
                }
            )
        } else {
            await achievementRefreshCoordinator.stopPeriodicRefresh()
            actions.append(contentsOf: [
                .achievementSnapshotSet(nil),
                .achievementErrorSet(nil)
            ])
        }

        if inputDecision.injectNeutralFrame {
            await environment.injectNeutralFrame()
        }
        if inputDecision.injectPauseMenuTap {
            await environment.injectPauseMenuTap()
        }

        if visible {
            let context: StreamMetricsLaunchContext?
            switch state.activeLaunchTarget {
            case .cloud:
                context = .cloud
            case .home:
                context = .home
            case nil:
                context = nil
            }
            StreamMetricsPipeline.shared.recordMilestone(
                .overlayOpened,
                context: context,
                targetID: state.activeLaunchTarget?.targetId,
                overlayTrigger: String(describing: trigger)
            )
        }

        return actions
    }

    func stopPresentationRefresh() async {
        await achievementRefreshCoordinator.stopPeriodicRefresh()
    }
}
