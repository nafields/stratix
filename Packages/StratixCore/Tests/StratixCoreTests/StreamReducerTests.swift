// StreamReducerTests.swift
// Exercises stream reducer behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

@MainActor
@Suite(.serialized)
struct StreamReducerTests {
    @Test
    func reduce_streamingSessionSet_updatesSession() {
        let session = makeStreamingSession()
        let state = StreamReducer.reduce(state: .empty, action: .streamingSessionSet(session))
        #expect(state.streamingSession === session)
    }

    @Test
    func reduce_overlayVisibilityChanged_updatesOverlayState() {
        let state = StreamReducer.reduce(
            state: .empty,
            action: .overlayVisibilityChanged(true, trigger: .userToggle)
        )
        #expect(state.isStreamOverlayVisible == true)
    }

    @Test
    func reduce_runtimePhaseSet_updatesPhase() {
        let state = StreamReducer.reduce(state: .empty, action: .runtimePhaseSet(.preparingStream))
        #expect(state.runtimePhase == .preparingStream)
    }

    @Test
    func reduce_runtimeContextSet_updatesContext() {
        let titleID = TitleID("1234")
        let state = StreamReducer.reduce(state: .empty, action: .runtimeContextSet(.cloud(titleId: titleID)))
        #expect(state.activeRuntimeContext == .cloud(titleId: titleID))
    }

    @Test
    func reduce_achievementSnapshotSet_updatesSnapshot() {
        let snapshot = TitleAchievementSnapshot(
            titleId: "1234",
            summary: TitleAchievementSummary(
                titleId: "1234",
                titleName: "Halo Infinite",
                totalAchievements: 0,
                unlockedAchievements: 0,
                totalGamerscore: 0,
                unlockedGamerscore: 0
            ),
            achievements: []
        )
        let state = StreamReducer.reduce(state: .empty, action: .achievementSnapshotSet(snapshot))
        #expect(state.currentStreamAchievementSnapshot == snapshot)
    }

    @Test
    func reduce_launchHeroURLSet_updatesHeroURL() {
        let url = URL(string: "https://example.com/hero.jpg")
        let state = StreamReducer.reduce(state: .empty, action: .launchHeroURLSet(url))
        #expect(state.launchHeroURL == url)
    }

    @Test
    func reduce_cloudLaunchRequested_updatesLaunchTarget() {
        let titleId = makeTitleID()
        let state = StreamReducer.reduce(state: .empty, action: .cloudLaunchRequested(titleId))
        #expect(state.activeLaunchTarget == .cloud(titleId))
        #expect(state.lastDisconnectIntent == nil)
        #expect(state.lastStreamStartFailure == nil)
    }

    @Test
    func reduce_reconnectScheduled_updatesReconnectState() {
        let state = StreamReducer.reduce(
            state: .empty,
            action: .reconnectScheduled(attempt: 2, trigger: .failed)
        )
        #expect(state.isReconnecting == true)
        #expect(state.reconnectAttemptCount == 2)
        #expect(state.lastReconnectTrigger == .failed)
    }

    @Test
    func reduce_reconnectStateReset_clearsReconnectDiagnostics() {
        let scheduled = StreamReducer.reduce(
            state: .empty,
            action: .reconnectScheduled(attempt: 2, trigger: .failed)
        )
        let disconnected = StreamReducer.reduce(
            state: scheduled,
            action: .streamDisconnected(.reconnectable)
        )
        let suppressed = StreamReducer.reduce(
            state: disconnected,
            action: .reconnectSuppressed(.attemptsExhausted)
        )

        let reset = StreamReducer.reduce(state: suppressed, action: .reconnectStateReset)

        #expect(reset.isReconnecting == false)
        #expect(reset.reconnectAttemptCount == 0)
        #expect(reset.lastDisconnectIntent == nil)
        #expect(reset.lastReconnectTrigger == nil)
        #expect(reset.lastReconnectSuppressionReason == nil)
    }

    @Test
    func reduce_streamDisconnected_updatesDisconnectIntentAndAttachmentState() {
        let state = StreamReducer.reduce(
            state: .empty,
            action: .streamDisconnected(.userInitiated)
        )
        #expect(state.lastDisconnectIntent == .userInitiated)
        #expect(state.sessionAttachmentState == .detached)
    }

    @Test
    func reduce_streamStartFailed_updatesFailure() {
        let state = StreamReducer.reduce(state: .empty, action: .streamStartFailed("failed"))
        #expect(state.lastStreamStartFailure == "failed")
        #expect(state.sessionAttachmentState == .detached)
    }

    @Test
    func reduce_signedOutReset_returnsEmptyState() {
        let mutated = StreamReducer.reduce(
            state: .empty,
            action: .overlayVisibilityChanged(true, trigger: .automatic)
        )
        let reset = StreamReducer.reduce(state: mutated, action: .signedOutReset)
        #expect(reset == .empty)
    }

    @Test
    func reduce_explicitStopSequence_returnsShellBaselineState() {
        let snapshot = TitleAchievementSnapshot(
            titleId: "1234",
            summary: TitleAchievementSummary(
                titleId: "1234",
                titleName: "Halo Infinite",
                totalAchievements: 0,
                unlockedAchievements: 0,
                totalGamerscore: 0,
                unlockedGamerscore: 0
            ),
            achievements: []
        )
        let session = makeStreamingSession()
        let actions: [StreamAction] = [
            .cloudLaunchRequested(makeTitleID()),
            .streamingSessionSet(session),
            .sessionAttachmentStateSet(.attached),
            .overlayVisibilityChanged(true, trigger: .userToggle),
            .achievementSnapshotSet(snapshot),
            .achievementErrorSet("error"),
            .launchHeroURLSet(URL(string: "https://example.com/hero.jpg")),
            .runtimeContextSet(.cloud(titleId: TitleID("1234"))),
            .runtimePhaseSet(.streaming),
            .reconnectScheduled(attempt: 2, trigger: .failed),
            .streamDisconnected(.reconnectable),
            .reconnectStateReset,
            .overlayVisibilityChanged(false, trigger: .explicitExit),
            .achievementSnapshotSet(nil),
            .achievementErrorSet(nil),
            .launchHeroURLSet(nil),
            .activeLaunchTargetSet(nil),
            .streamingSessionSet(nil),
            .sessionAttachmentStateSet(.detached),
            .runtimeContextSet(nil),
            .runtimePhaseSet(.restoringShell),
            .runtimePhaseSet(.shellActive),
            .shellRestoredAfterExitSet(true)
        ]

        let finalState = actions.reduce(StreamState.empty) { state, action in
            StreamReducer.reduce(state: state, action: action)
        }

        #expect(finalState.isReconnecting == false)
        #expect(finalState.streamingSession == nil)
        #expect(finalState.sessionAttachmentState == .detached)
        #expect(finalState.isStreamOverlayVisible == false)
        #expect(finalState.currentStreamAchievementSnapshot == nil)
        #expect(finalState.lastStreamAchievementError == nil)
        #expect(finalState.launchHeroURL == nil)
        #expect(finalState.runtimePhase == .shellActive)
        #expect(finalState.shellRestoredAfterStreamExit == true)
        #expect(finalState.activeRuntimeContext == nil)
        #expect(finalState.activeLaunchTarget == nil)
        #expect(finalState.lastDisconnectIntent == nil)
        #expect(finalState.reconnectAttemptCount == 0)
        #expect(finalState.lastReconnectTrigger == nil)
        #expect(finalState.lastReconnectSuppressionReason == nil)
    }

    @Test
    func reduce_doesNotMutateInputSnapshot() {
        let original = StreamState.empty

        let next = StreamReducer.reduce(
            state: original,
            action: .runtimePhaseSet(.preparingStream)
        )

        #expect(original.runtimePhase == .shellActive)
        #expect(next.runtimePhase == .preparingStream)
        #expect(original != next)
    }
}
