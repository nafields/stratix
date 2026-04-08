// TVOSAudioResyncPolicyTests.swift
// Exercises tvos audio resync policy behavior.
//

import Foundation
import Testing
@testable import StratixCore

@Suite
struct TVOSAudioResyncPolicyTests {
    private let policy = TVOSAudioResyncPolicy()

    @Test
    func evaluate_returnsSuppressedWhenWatchdogDisabled() {
        let decision = policy.evaluate(
            input: makeInput(watchdogEnabled: false),
            state: .init(highAudioDelayStrikeCount: 2, lastTriggerTimestamp: 10, triggerCount: 1)
        )

        #expect(decision.shouldTrigger == false)
        #expect(decision.suppressionReason == .watchdogDisabled)
        #expect(decision.updatedState == .init(highAudioDelayStrikeCount: 2, lastTriggerTimestamp: 10, triggerCount: 1))
    }

    @Test
    func evaluate_resetsStrikesWhenEmittedFramesAreInsufficient() {
        let decision = policy.evaluate(
            input: makeInput(jitterBufferEmittedCount: 12_000),
            state: .init(highAudioDelayStrikeCount: 2)
        )

        #expect(decision.shouldTrigger == false)
        #expect(decision.suppressionReason == .insufficientEmittedFrames)
        #expect(decision.updatedState.highAudioDelayStrikeCount == 0)
    }

    @Test
    func evaluate_resetsStrikesDuringStartupGracePeriod() {
        let decision = policy.evaluate(
            input: makeInput(gateOpenedAtTimestamp: 97, nowTimestamp: 100),
            state: .init(highAudioDelayStrikeCount: 2)
        )

        #expect(decision.shouldTrigger == false)
        #expect(decision.suppressionReason == .startupGracePeriod)
        #expect(decision.updatedState.highAudioDelayStrikeCount == 0)
    }

    @Test
    func evaluate_incrementsStrikesForCleanNetworkDelay() {
        let decision = policy.evaluate(
            input: makeInput(),
            state: .init(highAudioDelayStrikeCount: 1)
        )

        #expect(decision.shouldTrigger == false)
        #expect(decision.suppressionReason == .insufficientStrikes)
        #expect(decision.updatedState.highAudioDelayStrikeCount == 2)
    }

    @Test
    func evaluate_triggersSoftTrackToggleAfterThreeQualifyingStrikes() {
        let decision = policy.evaluate(
            input: makeInput(),
            state: .init(highAudioDelayStrikeCount: 2, lastTriggerTimestamp: 0, triggerCount: 0)
        )

        #expect(decision.shouldTrigger == true)
        #expect(decision.mode == .softTrackToggle)
        #expect(decision.suppressionReason == nil)
        #expect(decision.updatedState.highAudioDelayStrikeCount == 0)
        #expect(decision.updatedState.triggerCount == 1)
        #expect(decision.updatedState.lastTriggerTimestamp == 100)
        #expect(decision.cooldownSeconds == 8)
    }

    @Test
    func evaluate_triggersHardEngineCycleForSevereDelay() {
        let decision = policy.evaluate(
            input: makeInput(
                jitterBufferDelayMs: 980,
                jitterBufferWindowDelayMs: 980
            ),
            state: .init(highAudioDelayStrikeCount: 2, triggerCount: 0)
        )

        #expect(decision.shouldTrigger == true)
        #expect(decision.mode == TVOSAudioResyncMode.hardEngineCycle)
        #expect(decision.cooldownSeconds == 5)
    }

    @Test
    func evaluate_triggersHardEngineCycleAfterPreviousResync() {
        let decision = policy.evaluate(
            input: makeInput(),
            state: .init(highAudioDelayStrikeCount: 2, triggerCount: 1)
        )

        #expect(decision.shouldTrigger == true)
        #expect(decision.mode == .hardEngineCycle)
        #expect(decision.cooldownSeconds == 5)
    }

    @Test
    func evaluate_suppressesDuringCooldown() {
        let decision = policy.evaluate(
            input: makeInput(nowTimestamp: 103),
            state: .init(highAudioDelayStrikeCount: 2, lastTriggerTimestamp: 100, triggerCount: 1)
        )

        #expect(decision.shouldTrigger == false)
        #expect(decision.suppressionReason == .cooldownActive)
        #expect(decision.updatedState.highAudioDelayStrikeCount == 3)
    }

    @Test
    func evaluate_resetsStrikesWhenNetworkConditionDoesNotQualify() {
        let decision = policy.evaluate(
            input: makeInput(jitterMs: 40, packetsLost: 2),
            state: .init(highAudioDelayStrikeCount: 2)
        )

        #expect(decision.shouldTrigger == false)
        #expect(decision.suppressionReason == .conditionNotMet)
        #expect(decision.updatedState.highAudioDelayStrikeCount == 0)
    }

    @Test
    func executionDecision_suppressesWhenRemoteTrackIsMissing() {
        let decision = policy.executionDecision(
            mode: .softTrackToggle,
            hasRemoteAudioTrack: false,
            isAudioGateOpen: true
        )

        #expect(decision.shouldDrain == false)
        #expect(decision.suppressionReason == .missingRemoteTrack)
    }

    @Test
    func executionDecision_suppressesHardResetWhenGateIsClosed() {
        let decision = policy.executionDecision(
            mode: .hardEngineCycle,
            hasRemoteAudioTrack: true,
            isAudioGateOpen: false
        )

        #expect(decision.shouldDrain == false)
        #expect(decision.suppressionReason == .gateClosedForHardReset)
    }

    @Test
    func executionDecision_returnsDrainPlanForSoftAndHardModes() {
        let soft = policy.executionDecision(
            mode: .softTrackToggle,
            hasRemoteAudioTrack: true,
            isAudioGateOpen: false
        )
        let hard = policy.executionDecision(
            mode: .hardEngineCycle,
            hasRemoteAudioTrack: true,
            isAudioGateOpen: true
        )

        #expect(soft.shouldDrain == true)
        #expect(soft.drainReason == "audioResyncWatchdogSoft")
        #expect(soft.drainDuration == 0.8)
        #expect(hard.shouldDrain == true)
        #expect(hard.drainReason == "audioResyncWatchdogHard")
        #expect(hard.drainDuration == 1.5)
    }

    private func makeInput(
        watchdogEnabled: Bool = true,
        jitterBufferDelayMs: Double? = 700,
        jitterBufferWindowDelayMs: Double? = 700,
        jitterBufferWindowTargetMs: Double? = 300,
        jitterMs: Double? = 10,
        packetsLost: Int? = 0,
        jitterBufferEmittedCount: Double? = 25_000,
        audioVideoPlayoutDeltaMs: Double? = 0,
        gateOpenedAtTimestamp: TimeInterval? = 90,
        nowTimestamp: TimeInterval = 100,
        drainInProgress: Bool = false
    ) -> TVOSAudioResyncEvaluationInput {
        TVOSAudioResyncEvaluationInput(
            watchdogEnabled: watchdogEnabled,
            drainInProgress: drainInProgress,
            jitterBufferDelayMs: jitterBufferDelayMs,
            jitterBufferWindowDelayMs: jitterBufferWindowDelayMs,
            jitterBufferWindowTargetMs: jitterBufferWindowTargetMs,
            jitterMs: jitterMs,
            packetsLost: packetsLost,
            jitterBufferEmittedCount: jitterBufferEmittedCount,
            audioVideoPlayoutDeltaMs: audioVideoPlayoutDeltaMs,
            gateOpenedAtTimestamp: gateOpenedAtTimestamp,
            nowTimestamp: nowTimestamp
        )
    }
}
