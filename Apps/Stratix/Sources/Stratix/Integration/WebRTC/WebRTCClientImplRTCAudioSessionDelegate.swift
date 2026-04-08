// WebRTCClientImplRTCAudioSessionDelegate.swift
// Defines web rtc client impl rtc audio session delegate for the Integration / WebRTC surface.
//

#if WEBRTC_AVAILABLE && os(tvOS)
import AVFoundation
import Foundation

extension WebRTCClientImpl: RTCAudioSessionDelegate {
    func scheduleTVOSAudioReconcile(reason: String) {
        let generation = callbackStateBox.currentGeneration()
        guard !audioReconcileQueued else { return }
        audioReconcileQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.callbackStateBox.isCurrentGeneration(generation) else { return }
            self.reconcileTVOSAudioSession(reason: reason)
        }
    }

    func reconcileTVOSAudioSession(reason: String) {
        audioReconcileQueued = false
        guard !audioReconcileInProgress else { return }
        guard isTVOSAudioGateOpen() else {
            logAudio("\(reason): reconcile skipped (audio gate closed)")
            return
        }
        audioReconcileInProgress = true
        defer { audioReconcileInProgress = false }

        let avSession = AVAudioSession.sharedInstance()
        let hardwareRate = avSession.sampleRate > 0 ? avSession.sampleRate : 48_000

        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()
        defer { rtcSession.unlockForConfiguration() }

        do {
            let config = Self.makeTVOSPlaybackAudioConfiguration(sampleRate: hardwareRate)
            let effectiveBefore = AVAudioSession.sharedInstance()
            let targetBuffer = config.ioBufferDuration
            // Note: ioBufferDuration is excluded from needsReconfigure — the hardware picks the
            // actual buffer size regardless of what we request, so checking it would always
            // show a mismatch (e.g. requested 20ms, hardware gives 23.22ms for HDMI) and
            // cause constant reconfiguration that disrupts the audio unit.
            let needsReconfigure = !rtcSession.isActive
                || rtcSession.category != config.category
                || rtcSession.mode != config.mode
                || abs(effectiveBefore.sampleRate - hardwareRate) > 1

            if needsReconfigure {
                // Keep session active during stream startup/route stabilization.
                // Deactivation here can lead to playout restart, drift, and audible lag.
                _ = try rtcSession.setConfiguration(config, active: true)
            }
            rtcSession.isAudioEnabled = true

            let reconciled = AVAudioSession.sharedInstance()
            let effectiveRate = reconciled.sampleRate
            let effectiveBuffer = reconciled.ioBufferDuration
            if abs(effectiveRate - 48_000) > 1 {
                logAudio("\(reason): hardware rate \(Int(effectiveRate))Hz (non-48k). Aligning WebRTC to hardware to prevent pitch/sync drift.", force: true)
            }
            let action = needsReconfigure ? "reconfigured" : "kept"
            logAudio("\(reason): \(action) active=\(rtcSession.isActive) targetRate=\(Int(hardwareRate)) effectiveRate=\(Int(effectiveRate)) targetBufferMs=\(Int(targetBuffer * 1000.0)) ioBufferMs=\(Int(effectiveBuffer * 1000.0))")
        } catch {
            logAudio("\(reason): reconcile failed: \(error.localizedDescription)", force: true)
        }
    }

    public func audioSessionDidStartPlayOrRecord(_ session: RTCAudioSession) {
        // IMPORTANT: This delegate is called while RTCAudioSession's internal mutex is held.
        // Do NOT call lockForConfiguration() or setConfiguration() here.
        let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let av = AVAudioSession.sharedInstance()
        logAudio("didStartPlayOrRecord active=\(session.isActive) outputs=\(outputs) outputChannels=\(session.outputNumberOfChannels) av.sampleRate=\(Int(av.sampleRate)) av.ioBufferMs=\(Int(av.ioBufferDuration * 1000.0))")
        scheduleTVOSAudioReconcile(reason: "didStartPlayOrRecord")
    }

    public func audioSessionDidStopPlayOrRecord(_ session: RTCAudioSession) {
        logAudio("didStopPlayOrRecord active=\(session.isActive)")
    }

    public func audioSession(_ session: RTCAudioSession, didChangeCanPlayOrRecord canPlayOrRecord: Bool) {
        logAudio("canPlayOrRecord=\(canPlayOrRecord)")
    }

    public func audioSession(_ audioSession: RTCAudioSession, willSetActive active: Bool) {
        logAudio("willSetActive=\(active)")
    }

    public func audioSession(_ audioSession: RTCAudioSession, didSetActive active: Bool) {
        let outputs = audioSession.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let av = AVAudioSession.sharedInstance()
        logAudio("didSetActive=\(active) outputs=\(outputs) volume=\(audioSession.outputVolume) av.sampleRate=\(Int(av.sampleRate)) av.ioBufferMs=\(Int(av.ioBufferDuration * 1000.0))")
    }

    public func audioSession(_ audioSession: RTCAudioSession, failedToSetActive active: Bool, error: Error) {
        logAudio("failedToSetActive=\(active) error=\(error.localizedDescription)", force: true)
    }

    public func audioSession(_ audioSession: RTCAudioSession, audioUnitStartFailedWithError error: Error) {
        logAudio("audioUnitStartFailed error=\(error.localizedDescription)", force: true)
    }

    public func audioSessionDidChangeRoute(_ session: RTCAudioSession,
                                           reason: AVAudioSession.RouteChangeReason,
                                           previousRoute: AVAudioSessionRouteDescription) {
        let prev = previousRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let curr = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        logAudio("routeChange reason=\(reason.rawValue) prev=\(prev) curr=\(curr)")
        scheduleTVOSAudioReconcile(reason: "routeChange")
    }

    public func audioSession(_ audioSession: RTCAudioSession, didChangeOutputVolume outputVolume: Float) {
        logAudio("outputVolumeChanged=\(outputVolume)")
    }
}
#endif
