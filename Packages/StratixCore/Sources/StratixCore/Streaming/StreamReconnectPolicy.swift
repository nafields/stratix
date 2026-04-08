// StreamReconnectPolicy.swift
// Defines stream reconnect policy for the Streaming surface.
//

import Foundation
import StreamingCore

struct StreamReconnectDecision: Equatable {
    let shouldReconnect: Bool
    let suppressionReason: StreamReconnectSuppressionReason?
}

struct StreamReconnectPolicy {
    let maxAttempts: Int
    let retryDelay: Duration

    init(
        maxAttempts: Int = 3,
        retryDelay: Duration = .seconds(2)
    ) {
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
    }

    func decision(
        intent: StreamingDisconnectIntent,
        autoReconnectEnabled: Bool,
        currentAttemptCount: Int,
        hasLaunchContext: Bool
    ) -> StreamReconnectDecision {
        guard autoReconnectEnabled else {
            return .init(shouldReconnect: false, suppressionReason: .autoReconnectDisabled)
        }
        guard hasLaunchContext else {
            return .init(shouldReconnect: false, suppressionReason: .missingLaunchContext)
        }
        guard currentAttemptCount < maxAttempts else {
            return .init(shouldReconnect: false, suppressionReason: .attemptsExhausted)
        }

        switch intent {
        case .reconnectable:
            return .init(shouldReconnect: true, suppressionReason: nil)
        case .userInitiated, .serverInitiated, .reconnectTransition:
            return .init(
                shouldReconnect: false,
                suppressionReason: suppressionReason(for: intent)
            )
        }
    }

    func shouldReconnect(
        intent: StreamingDisconnectIntent,
        autoReconnectEnabled: Bool,
        currentAttemptCount: Int,
        hasLaunchContext: Bool
    ) -> Bool {
        decision(
            intent: intent,
            autoReconnectEnabled: autoReconnectEnabled,
            currentAttemptCount: currentAttemptCount,
            hasLaunchContext: hasLaunchContext
        ).shouldReconnect
    }

    func suppressionReason(
        for intent: StreamingDisconnectIntent
    ) -> StreamReconnectSuppressionReason {
        switch intent {
        case .userInitiated:
            return .userInitiatedDisconnect
        case .serverInitiated:
            return .serverInitiatedDisconnect
        case .reconnectTransition:
            return .reconnectTransition
        case .reconnectable:
            return .attemptsExhausted
        }
    }
}
