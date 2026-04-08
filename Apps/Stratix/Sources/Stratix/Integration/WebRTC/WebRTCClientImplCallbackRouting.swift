// WebRTCClientImplCallbackRouting.swift
// Defines web rtc client impl callback routing for the Integration / WebRTC surface.
//

import Foundation
import StratixCore
import StratixModels
import StreamingCore

#if WEBRTC_AVAILABLE
import WebRTC

extension WebRTCClientImpl {
    func peerConnectionGeneration(for peerConnection: RTCPeerConnection) -> UInt64? {
        callbackStateBox.activePeerConnectionGeneration(for: peerConnection)
    }

    func appendLocalCandidate(_ payload: IceCandidatePayload) {
        stateBox.appendLocalCandidate(payload)
    }

    func handlePeerConnectionConnected(generation: UInt64) {
#if os(tvOS)
        markAudioGatePeerConnected()
        maybeOpenTVOSAudioStartGate(reason: "peerConnected")
#endif
        logDataChannelStates(reason: "pc connected")
        publishOpenDataChannelsIfNeeded(reason: "pc connected")
        publishKnownRemoteTracks(reason: "pc connected")
    }

    func handlePeerConnectionTrackStart(
        _ track: RTCMediaStreamTrack,
        reason: String,
        generation: UInt64
    ) {
        publishRemoteTrackIfNeeded(track, reason: reason, generation: generation)
    }

    func publishKnownRemoteTracks(reason: String) {
        let generation = callbackStateBox.currentGeneration()
        guard let peerConnection else { return }

        for transceiver in peerConnection.transceivers {
            if let track = transceiver.receiver.track {
                publishRemoteTrackIfNeeded(track, reason: "\(reason) via transceiver", generation: generation)
            }
        }

        for receiver in peerConnection.receivers {
            if let track = receiver.track {
                publishRemoteTrackIfNeeded(track, reason: "\(reason) via receiver", generation: generation)
            }
        }
    }

    func publishRemoteTrackIfNeeded(
        _ track: RTCMediaStreamTrack,
        reason: String,
        generation: UInt64
    ) {
        guard callbackStateBox.isCurrentGeneration(generation) else { return }
        let trackID = track.trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trackIdentity = ObjectIdentifier(track)
        guard stateBox.markRemoteTrackIfNeeded(trackID: trackID, identity: trackIdentity) else { return }

        print("[WebRTC] discovered remote track kind=\(track.kind) id=\(track.trackId) (\(reason))")

        if track.kind == kRTCMediaStreamTrackKindVideo, let videoTrack = track as? RTCVideoTrack {
            callbackStateBox.delegate(for: generation)?.webRTC(self, didReceiveVideoTrack: videoTrack)
        } else if track.kind == kRTCMediaStreamTrackKindAudio, let audioTrack = track as? RTCAudioTrack {
#if os(tvOS)
            markAudioGateRemoteTrackDiscovered()
            let gateOpen = isTVOSAudioGateOpen()
            audioTrack.isEnabled = gateOpen
#else
            audioTrack.isEnabled = true
#endif

            let audioBoostDB = SettingsStore.snapshotStream().audioBoost
            let gainLinear = min(pow(10.0, audioBoostDB / 20.0), 10.0)
            audioTrack.source.volume = gainLinear
            logAudio("Boost: +\(String(format: "%.1f", audioBoostDB))dB → source.volume=\(String(format: "%.3f", gainLinear))")

            remoteAudioTrack = audioTrack

#if os(tvOS)
            maybeOpenTVOSAudioStartGate(reason: "remoteAudioTrackDiscovered")
            let rtcAudioSession = RTCAudioSession.sharedInstance()
            let outputs = rtcAudioSession.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
            let av = AVAudioSession.sharedInstance()
            if verboseAudioLogsEnabled {
                print("[WebRTC] remote audio track enabled=\(audioTrack.isEnabled) id=\(audioTrack.trackId) (RTCAudioSession active=\(rtcAudioSession.isActive), isAudioEnabled=\(rtcAudioSession.isAudioEnabled), manualAudio=\(rtcAudioSession.useManualAudio), category=\(rtcAudioSession.category), mode=\(rtcAudioSession.mode), outputs=\(outputs), outputChannels=\(rtcAudioSession.outputNumberOfChannels), av.sampleRate=\(Int(av.sampleRate)), av.ioBufferMs=\(Int(av.ioBufferDuration * 1000.0)))")
            }
#else
            print("[WebRTC] remote audio track enabled=\(audioTrack.isEnabled) id=\(audioTrack.trackId)")
#endif

            callbackStateBox.delegate(for: generation)?.webRTC(self, didReceiveAudioTrack: audioTrack)
        }
    }
}
#endif
