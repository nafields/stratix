// StreamStateTests.swift
// Exercises stream state behavior.
//

import Foundation
import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct StreamStateTests {
    @Test
    func empty_providesExpectedInitialValues() {
        let state = StreamState.empty

        #expect(state.isReconnecting == false)
        #expect(state.streamingSession == nil)
        #expect(state.sessionAttachmentState == .detached)
        #expect(state.isStreamOverlayVisible == false)
        #expect(state.currentStreamAchievementSnapshot == nil)
        #expect(state.lastStreamAchievementError == nil)
        #expect(state.launchHeroURL == nil)
        #expect(state.runtimePhase == .shellActive)
        #expect(state.shellRestoredAfterStreamExit == false)
        #expect(state.activeRuntimeContext == nil)
        #expect(state.activeLaunchTarget == nil)
        #expect(state.lastDisconnectIntent == nil)
        #expect(state.reconnectAttemptCount == 0)
        #expect(state.lastReconnectTrigger == nil)
        #expect(state.lastReconnectSuppressionReason == nil)
        #expect(state.lastStreamStartFailure == nil)
    }

    @Test
    func equatable_changesWhenAnyRuntimeFieldChanges() {
        let session = makeStreamingSession()
        let base = StreamState.empty

        #expect(base != StreamReducer.reduce(state: base, action: .streamingSessionSet(session)))
        #expect(base != StreamReducer.reduce(state: base, action: .overlayVisibilityChanged(true, trigger: .userToggle)))
        #expect(base != StreamReducer.reduce(state: base, action: .runtimePhaseSet(.preparingStream)))
        #expect(base != StreamReducer.reduce(state: base, action: .cloudLaunchRequested(makeTitleID())))
    }
}
