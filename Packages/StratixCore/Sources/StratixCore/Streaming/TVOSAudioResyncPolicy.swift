// TVOSAudioResyncPolicy.swift
// Defines tvos audio resync policy for the Streaming surface.
//

import Foundation

public enum TVOSAudioResyncMode: String, Sendable, Equatable {
    case softTrackToggle
    case hardEngineCycle
}

public enum TVOSAudioResyncSuppressionReason: Sendable, Equatable {
    case watchdogDisabled
    case drainInProgress
    case insufficientEmittedFrames
    case startupGracePeriod
    case targetDelayHealthy
    case conditionNotMet
    case insufficientStrikes
    case cooldownActive
}

public enum TVOSAudioResyncExecutionSuppressionReason: Sendable, Equatable {
    case missingRemoteTrack
    case gateClosedForHardReset
}

public struct TVOSAudioResyncExecutionDecision: Sendable, Equatable {
    public let drainDuration: TimeInterval?
    public let drainReason: String?
    public let suppressionReason: TVOSAudioResyncExecutionSuppressionReason?

    public init(
        drainDuration: TimeInterval?,
        drainReason: String?,
        suppressionReason: TVOSAudioResyncExecutionSuppressionReason?
    ) {
        self.drainDuration = drainDuration
        self.drainReason = drainReason
        self.suppressionReason = suppressionReason
    }

    public var shouldDrain: Bool {
        drainDuration != nil && drainReason != nil
    }
}

public struct TVOSAudioResyncPolicyState: Sendable, Equatable {
    public var highAudioDelayStrikeCount: Int
    public var lastTriggerTimestamp: TimeInterval
    public var triggerCount: Int

    public init(
        highAudioDelayStrikeCount: Int = 0,
        lastTriggerTimestamp: TimeInterval = 0,
        triggerCount: Int = 0
    ) {
        self.highAudioDelayStrikeCount = highAudioDelayStrikeCount
        self.lastTriggerTimestamp = lastTriggerTimestamp
        self.triggerCount = triggerCount
    }
}

public struct TVOSAudioResyncEvaluationInput: Sendable, Equatable {
    public let watchdogEnabled: Bool
    public let drainInProgress: Bool
    public let jitterBufferDelayMs: Double?
    public let jitterBufferWindowDelayMs: Double?
    public let jitterBufferWindowTargetMs: Double?
    public let jitterMs: Double?
    public let packetsLost: Int?
    public let jitterBufferEmittedCount: Double?
    public let audioVideoPlayoutDeltaMs: Double?
    public let gateOpenedAtTimestamp: TimeInterval?
    public let nowTimestamp: TimeInterval

    public init(
        watchdogEnabled: Bool,
        drainInProgress: Bool,
        jitterBufferDelayMs: Double?,
        jitterBufferWindowDelayMs: Double?,
        jitterBufferWindowTargetMs: Double?,
        jitterMs: Double?,
        packetsLost: Int?,
        jitterBufferEmittedCount: Double?,
        audioVideoPlayoutDeltaMs: Double?,
        gateOpenedAtTimestamp: TimeInterval?,
        nowTimestamp: TimeInterval
    ) {
        self.watchdogEnabled = watchdogEnabled
        self.drainInProgress = drainInProgress
        self.jitterBufferDelayMs = jitterBufferDelayMs
        self.jitterBufferWindowDelayMs = jitterBufferWindowDelayMs
        self.jitterBufferWindowTargetMs = jitterBufferWindowTargetMs
        self.jitterMs = jitterMs
        self.packetsLost = packetsLost
        self.jitterBufferEmittedCount = jitterBufferEmittedCount
        self.audioVideoPlayoutDeltaMs = audioVideoPlayoutDeltaMs
        self.gateOpenedAtTimestamp = gateOpenedAtTimestamp
        self.nowTimestamp = nowTimestamp
    }
}

public struct TVOSAudioResyncDecision: Sendable, Equatable {
    public let updatedState: TVOSAudioResyncPolicyState
    public let mode: TVOSAudioResyncMode?
    public let suppressionReason: TVOSAudioResyncSuppressionReason?
    public let effectiveBufferDelayMs: Double
    public let cooldownSeconds: TimeInterval

    public init(
        updatedState: TVOSAudioResyncPolicyState,
        mode: TVOSAudioResyncMode?,
        suppressionReason: TVOSAudioResyncSuppressionReason?,
        effectiveBufferDelayMs: Double,
        cooldownSeconds: TimeInterval
    ) {
        self.updatedState = updatedState
        self.mode = mode
        self.suppressionReason = suppressionReason
        self.effectiveBufferDelayMs = effectiveBufferDelayMs
        self.cooldownSeconds = cooldownSeconds
    }

    public var shouldTrigger: Bool {
        mode != nil
    }
}

public struct TVOSAudioResyncPolicy: Sendable {
    public init() {}

    public func evaluate(
        input: TVOSAudioResyncEvaluationInput,
        state: TVOSAudioResyncPolicyState
    ) -> TVOSAudioResyncDecision {
        let effectiveBufferDelayMs = input.jitterBufferWindowDelayMs ?? input.jitterBufferDelayMs ?? 0

        guard input.watchdogEnabled else {
            return decision(
                state: state,
                suppressionReason: .watchdogDisabled,
                effectiveBufferDelayMs: effectiveBufferDelayMs
            )
        }

        guard !input.drainInProgress else {
            return decision(
                state: state,
                suppressionReason: .drainInProgress,
                effectiveBufferDelayMs: effectiveBufferDelayMs
            )
        }

        guard (input.jitterBufferEmittedCount ?? 0) >= 24_000 else {
            var next = state
            next.highAudioDelayStrikeCount = 0
            return decision(
                state: next,
                suppressionReason: .insufficientEmittedFrames,
                effectiveBufferDelayMs: effectiveBufferDelayMs
            )
        }

        if let gateOpenedAtTimestamp = input.gateOpenedAtTimestamp,
           (input.nowTimestamp - gateOpenedAtTimestamp) < 6 {
            var next = state
            next.highAudioDelayStrikeCount = 0
            return decision(
                state: next,
                suppressionReason: .startupGracePeriod,
                effectiveBufferDelayMs: effectiveBufferDelayMs
            )
        }

        if let targetMs = input.jitterBufferWindowTargetMs, targetMs <= 200 {
            var next = state
            next.highAudioDelayStrikeCount = 0
            return decision(
                state: next,
                suppressionReason: .targetDelayHealthy,
                effectiveBufferDelayMs: effectiveBufferDelayMs
            )
        }

        let highBufferDelay = effectiveBufferDelayMs >= 650
        let severeBufferDelay = effectiveBufferDelayMs >= 950
        let highAVDrift = abs(input.audioVideoPlayoutDeltaMs ?? 0) >= 600
        let cleanNetwork = (input.packetsLost ?? 0) == 0 && (input.jitterMs ?? 999) <= 25

        var next = state
        if cleanNetwork && (highBufferDelay || highAVDrift) {
            next.highAudioDelayStrikeCount += 1
        } else {
            next.highAudioDelayStrikeCount = 0
            return decision(
                state: next,
                suppressionReason: .conditionNotMet,
                effectiveBufferDelayMs: effectiveBufferDelayMs
            )
        }

        guard next.highAudioDelayStrikeCount >= 3 else {
            return decision(
                state: next,
                suppressionReason: .insufficientStrikes,
                effectiveBufferDelayMs: effectiveBufferDelayMs
            )
        }

        let shouldUseHardReset = severeBufferDelay || next.triggerCount >= 1
        let cooldownSeconds: TimeInterval = shouldUseHardReset ? 5.0 : 8.0
        guard (input.nowTimestamp - next.lastTriggerTimestamp) >= cooldownSeconds else {
            return decision(
                state: next,
                suppressionReason: .cooldownActive,
                effectiveBufferDelayMs: effectiveBufferDelayMs,
                cooldownSeconds: cooldownSeconds
            )
        }

        next.lastTriggerTimestamp = input.nowTimestamp
        next.highAudioDelayStrikeCount = 0
        next.triggerCount += 1

        return TVOSAudioResyncDecision(
            updatedState: next,
            mode: shouldUseHardReset ? .hardEngineCycle : .softTrackToggle,
            suppressionReason: nil,
            effectiveBufferDelayMs: effectiveBufferDelayMs,
            cooldownSeconds: cooldownSeconds
        )
    }

    private func decision(
        state: TVOSAudioResyncPolicyState,
        suppressionReason: TVOSAudioResyncSuppressionReason,
        effectiveBufferDelayMs: Double,
        cooldownSeconds: TimeInterval = 0
    ) -> TVOSAudioResyncDecision {
        TVOSAudioResyncDecision(
            updatedState: state,
            mode: nil,
            suppressionReason: suppressionReason,
            effectiveBufferDelayMs: effectiveBufferDelayMs,
            cooldownSeconds: cooldownSeconds
        )
    }

    public func executionDecision(
        mode: TVOSAudioResyncMode,
        hasRemoteAudioTrack: Bool,
        isAudioGateOpen: Bool
    ) -> TVOSAudioResyncExecutionDecision {
        guard hasRemoteAudioTrack else {
            return TVOSAudioResyncExecutionDecision(
                drainDuration: nil,
                drainReason: nil,
                suppressionReason: .missingRemoteTrack
            )
        }

        switch mode {
        case .hardEngineCycle:
            guard isAudioGateOpen else {
                return TVOSAudioResyncExecutionDecision(
                    drainDuration: nil,
                    drainReason: nil,
                    suppressionReason: .gateClosedForHardReset
                )
            }
            return TVOSAudioResyncExecutionDecision(
                drainDuration: 1.5,
                drainReason: "audioResyncWatchdogHard",
                suppressionReason: nil
            )
        case .softTrackToggle:
            return TVOSAudioResyncExecutionDecision(
                drainDuration: 0.8,
                drainReason: "audioResyncWatchdogSoft",
                suppressionReason: nil
            )
        }
    }
}
