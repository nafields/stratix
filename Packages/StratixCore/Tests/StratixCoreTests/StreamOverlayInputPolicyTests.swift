// StreamOverlayInputPolicyTests.swift
// Exercises stream overlay input policy behavior.
//

import Testing
@testable import StratixCore

@Suite(.serialized)
struct StreamOverlayInputPolicyTests {
    @Test
    func inputDecision_openWithSession_injectsNeutralFrameAndPauseMenuTap() {
        let policy = StreamOverlayInputPolicy()
        let decision = policy.inputDecision(
            for: StreamOverlayVisibilityChangeContext(
                oldVisible: false,
                newVisible: true,
                hasStreamingSession: true,
                disconnectArmed: false,
                trigger: .userToggle
            )
        )

        #expect(decision.injectNeutralFrame == true)
        #expect(decision.injectPauseMenuTap == true)
    }

    @Test
    func inputDecision_closeWhileDisconnectArmed_injectsNeutralFrameOnly() {
        let policy = StreamOverlayInputPolicy()
        let decision = policy.inputDecision(
            for: StreamOverlayVisibilityChangeContext(
                oldVisible: true,
                newVisible: false,
                hasStreamingSession: true,
                disconnectArmed: true,
                trigger: .explicitExit
            )
        )

        #expect(decision.injectNeutralFrame == true)
        #expect(decision.injectPauseMenuTap == false)
    }

    @Test
    func inputDecision_reconnectOpen_suppressesPauseMenuTap() {
        let policy = StreamOverlayInputPolicy()
        let decision = policy.inputDecision(
            for: StreamOverlayVisibilityChangeContext(
                oldVisible: false,
                newVisible: true,
                hasStreamingSession: true,
                disconnectArmed: false,
                trigger: .reconnect
            )
        )

        #expect(decision.injectNeutralFrame == true)
        #expect(decision.injectPauseMenuTap == false)
    }
}
