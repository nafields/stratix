// WebRTCClientImplTVOSAudio.swift
// Defines web rtc client impl tvos audio for the Integration / WebRTC surface.
//

import Foundation
import StratixCore

#if WEBRTC_AVAILABLE

extension WebRTCClientImpl {
    // Runtime toggle for noisy audio diagnostics.
    // Keep audio logs independent from generic network diagnostics.
    // Enabled only with explicit audio debug key: debug.webrtc_audio_logs=true.
    var verboseAudioLogsEnabled: Bool {
        let defaults = UserDefaults.standard
        let explicitAudioDiagnostics = defaults.object(forKey: "debug.webrtc_audio_logs") as? Bool ?? false
        return explicitAudioDiagnostics
    }

    func logAudio(_ message: @autoclosure () -> String, force: Bool = false) {
        guard force || verboseAudioLogsEnabled else { return }
        print("[WebRTC][Audio] \(message())")
    }

    private func logAudioResync(_ message: @autoclosure () -> String, force: Bool = false) {
        guard force || verboseAudioLogsEnabled else { return }
        print("[WebRTC][AudioResync] \(message())")
    }

    func logAudioStats(_ message: @autoclosure () -> String) {
        guard verboseAudioLogsEnabled else { return }
        print("[WebRTC][AudioStats:v3] \(message())")
    }

    func maybeTriggerAudioResyncWatchdog(
        audioJitterBufferDelayMs: Double?,
        audioJitterBufferWindowDelayMs: Double?,
        audioJitterBufferWindowTargetMs: Double?,
        audioJitterMs: Double?,
        audioPacketsLost: Int?,
        audioJitterBufferEmittedCount: Double?,
        audioVideoPlayoutDeltaMs: Double?
    ) {
#if os(tvOS)
        let now = Date.timeIntervalSinceReferenceDate
        let policy = TVOSAudioResyncPolicy()
        let decision = policy.evaluate(
            input: TVOSAudioResyncEvaluationInput(
                watchdogEnabled: SettingsStore.snapshotDiagnostics().audioResyncWatchdogEnabled,
                drainInProgress: audioResyncDrainInProgress,
                jitterBufferDelayMs: audioJitterBufferDelayMs,
                jitterBufferWindowDelayMs: audioJitterBufferWindowDelayMs,
                jitterBufferWindowTargetMs: audioJitterBufferWindowTargetMs,
                jitterMs: audioJitterMs,
                packetsLost: audioPacketsLost,
                jitterBufferEmittedCount: audioJitterBufferEmittedCount,
                audioVideoPlayoutDeltaMs: audioVideoPlayoutDeltaMs,
                gateOpenedAtTimestamp: audioGateOpenedAtTimestamp,
                nowTimestamp: now
            ),
            state: TVOSAudioResyncPolicyState(
                highAudioDelayStrikeCount: highAudioDelayStrikeCount,
                lastTriggerTimestamp: lastAudioResyncTriggerTimestamp,
                triggerCount: audioResyncTriggerCount
            )
        )
        highAudioDelayStrikeCount = decision.updatedState.highAudioDelayStrikeCount
        lastAudioResyncTriggerTimestamp = decision.updatedState.lastTriggerTimestamp
        audioResyncTriggerCount = decision.updatedState.triggerCount
        guard let mode = decision.mode else { return }

        statsStateBox.resetAudioWindow()

        let jb = audioJitterBufferDelayMs.map { String(format: "%.1f", $0) } ?? "n/a"
        let jbWin = audioJitterBufferWindowDelayMs.map { String(format: "%.1f", $0) } ?? "n/a"
        let jbTarget = audioJitterBufferWindowTargetMs.map { String(format: "%.1f", $0) } ?? "n/a"
        let drift = audioVideoPlayoutDeltaMs.map { String(format: "%.1f", $0) } ?? "n/a"
        logAudioResync("trigger reason=highAudioDelay strikes=3 mode=\(mode.rawValue) jbAvgMs=\(jb) jbWinMs=\(jbWin) jbTargetWinMs=\(jbTarget) avSyncDeltaMs=\(drift)", force: true)
        performAudioResyncNudge(
            decision: policy.executionDecision(
                mode: mode,
                hasRemoteAudioTrack: remoteAudioTrack != nil,
                isAudioGateOpen: isTVOSAudioGateOpen()
            )
        )
#else
        _ = audioJitterBufferDelayMs
        _ = audioJitterBufferWindowDelayMs
        _ = audioJitterBufferWindowTargetMs
        _ = audioJitterMs
        _ = audioPacketsLost
        _ = audioJitterBufferEmittedCount
        _ = audioVideoPlayoutDeltaMs
#endif
    }

#if os(tvOS)
    func resetTVOSAudioStartGate(reason: String) {
        audioGateQueue.sync {
            audioGateHasRemoteTrack = false
            audioGatePeerConnected = false
            audioGateOpened = false
        }
        audioGateOpenedAtTimestamp = nil
        highAudioDelayStrikeCount = 0
        lastAudioResyncTriggerTimestamp = 0
        audioResyncTriggerCount = 0
        audioResyncDrainInProgress = false
        statsStateBox.resetAudioWindow()
        setTVOSAudioEnabled(false, reason: "\(reason).gateReset")
    }

    func markAudioGateRemoteTrackDiscovered() {
        audioGateQueue.sync { audioGateHasRemoteTrack = true }
    }

    func markAudioGatePeerConnected() {
        audioGateQueue.sync { audioGatePeerConnected = true }
    }

    func isTVOSAudioGateOpen() -> Bool {
        audioGateQueue.sync { audioGateOpened }
    }

    func maybeOpenTVOSAudioStartGate(reason: String) {
        let shouldOpen = audioGateQueue.sync { () -> Bool in
            guard audioGateHasRemoteTrack, audioGatePeerConnected, !audioGateOpened else { return false }
            audioGateOpened = true
            return true
        }
        guard shouldOpen else { return }
        let generation = callbackStateBox.currentGeneration()
        audioGateOpenedAtTimestamp = Date.timeIntervalSinceReferenceDate
        highAudioDelayStrikeCount = 0
        lastAudioResyncTriggerTimestamp = 0
        audioResyncTriggerCount = 0
        statsStateBox.resetAudioWindow()
        setTVOSAudioEnabled(true, reason: "\(reason).gateOpen")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.callbackStateBox.isCurrentGeneration(generation) else { return }
            self.remoteAudioTrack?.isEnabled = true
            self.scheduleTVOSAudioReconcile(reason: "\(reason).gateOpen")
        }
    }

    private func setTVOSAudioEnabled(_ enabled: Bool, reason: String) {
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()
        rtcSession.isAudioEnabled = enabled
        rtcSession.unlockForConfiguration()
        logAudio("\(reason): set RTCAudioSession.isAudioEnabled=\(enabled)")
    }

    private func performAudioResyncNudge(decision: TVOSAudioResyncExecutionDecision) {
        guard decision.shouldDrain,
              let drainReason = decision.drainReason,
              let drainDuration = decision.drainDuration else {
            switch decision.suppressionReason {
            case .missingRemoteTrack:
                logAudioResync("skipped (no remote audio track)")
            case .gateClosedForHardReset:
                logAudioResync("hard drain skipped (audio gate closed)")
            case nil:
                break
            }
            return
        }

        drainJitterBuffer(reason: drainReason, drainDuration: drainDuration)
    }

    private func drainJitterBuffer(reason: String, drainDuration: TimeInterval) {
        audioResyncDrainInProgress = true
        let generation = callbackStateBox.currentGeneration()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.callbackStateBox.isCurrentGeneration(generation) else { return }
            guard let track = self.remoteAudioTrack else {
                self.audioResyncDrainInProgress = false
                return
            }
            track.isEnabled = false
            self.logAudioResync("\(reason): track disabled, draining jitter buffer for \(drainDuration)s...", force: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + drainDuration) { [weak self] in
                guard let self else { return }
                guard self.callbackStateBox.isCurrentGeneration(generation) else { return }
                self.audioResyncDrainInProgress = false
                guard let track = self.remoteAudioTrack else { return }
                track.isEnabled = true
                self.scheduleTVOSAudioReconcile(reason: "\(reason).reEnable")
                self.logAudioResync("\(reason): track re-enabled after \(drainDuration)s drain", force: true)
            }
        }
    }
#endif

    /// Re-apply audio boost gain to the active remote audio track.
    /// Called live when the Guide slider changes during a stream.
    public func updateAudioBoost(dB: Double) {
        guard let audioTrack = remoteAudioTrack else { return }
        let gainLinear = min(pow(10.0, dB / 20.0), 10.0)
        audioTrack.source.volume = gainLinear
        logAudio("Live boost update: +\(String(format: "%.1f", dB))dB → volume=\(String(format: "%.3f", gainLinear))")
    }
}

#endif // WEBRTC_AVAILABLE
