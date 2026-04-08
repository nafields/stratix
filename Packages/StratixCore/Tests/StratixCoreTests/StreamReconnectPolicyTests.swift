// StreamReconnectPolicyTests.swift
// Exercises stream reconnect policy behavior.
//

import Testing
@testable import StratixCore

@Suite(.serialized)
struct StreamReconnectPolicyTests {
    @Test
    func shouldReconnect_returnsTrueForReconnectableIntentWhenAutoReconnectEnabledAndBelowMaxAttempts() {
        let policy = StreamReconnectPolicy(maxAttempts: 3, retryDelay: .zero)
        let decision = policy.decision(
            intent: .reconnectable,
            autoReconnectEnabled: true,
            currentAttemptCount: 0,
            hasLaunchContext: true
        )
        #expect(decision.shouldReconnect == true)
        #expect(decision.suppressionReason == nil)
    }

    @Test
    func shouldReconnect_returnsFalseForRejectedCases() {
        let policy = StreamReconnectPolicy(maxAttempts: 3, retryDelay: .zero)
        #expect(policy.decision(intent: .userInitiated, autoReconnectEnabled: true, currentAttemptCount: 0, hasLaunchContext: true) == .init(shouldReconnect: false, suppressionReason: .userInitiatedDisconnect))
        #expect(policy.decision(intent: .serverInitiated, autoReconnectEnabled: true, currentAttemptCount: 0, hasLaunchContext: true) == .init(shouldReconnect: false, suppressionReason: .serverInitiatedDisconnect))
        #expect(policy.decision(intent: .reconnectTransition, autoReconnectEnabled: true, currentAttemptCount: 0, hasLaunchContext: true) == .init(shouldReconnect: false, suppressionReason: .reconnectTransition))
        #expect(policy.decision(intent: .reconnectable, autoReconnectEnabled: false, currentAttemptCount: 0, hasLaunchContext: true) == .init(shouldReconnect: false, suppressionReason: .autoReconnectDisabled))
        #expect(policy.decision(intent: .reconnectable, autoReconnectEnabled: true, currentAttemptCount: 3, hasLaunchContext: true) == .init(shouldReconnect: false, suppressionReason: .attemptsExhausted))
        #expect(policy.decision(intent: .reconnectable, autoReconnectEnabled: true, currentAttemptCount: 0, hasLaunchContext: false) == .init(shouldReconnect: false, suppressionReason: .missingLaunchContext))
    }
}
