// WebRTCClientImplBridge.swift
// Defines web rtc client impl bridge for the Integration / WebRTC surface.
//

import Foundation
import StratixModels
import StreamingCore

#if WEBRTC_AVAILABLE
import WebRTC

extension WebRTCClientImpl {
    /// Add transceivers and data channels before `createOffer()`.
    /// Mirrors the active XCloud player setup: recvonly audio/video on tvOS plus
    /// the ordered control/input/message/chat data-channel bundle.
    public func applyH264CodecPreferences() {
        guard let peerConnection else { return }
#if os(tvOS)
        resetTVOSAudioStartGate(reason: "applyH264CodecPreferences")
#endif

        let audioInit = RTCRtpTransceiverInit()
#if os(tvOS)
        audioInit.direction = .recvOnly
#else
        audioInit.direction = .sendRecv
#endif
        peerConnection.addTransceiver(of: .audio, init: audioInit)

        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .recvOnly
        _ = peerConnection.addTransceiver(of: .video, init: videoInit)

        configureDataChannels(for: peerConnection)
    }

    public func createOffer() async throws -> SessionDescription {
        guard let peerConnection else { throw WebRTCError.noConnection }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { sdp, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sdp else {
                    continuation.resume(throwing: WebRTCError.noSDP)
                    return
                }
                continuation.resume(
                    returning: SessionDescription(
                        type: sdp.type == .offer ? .offer : .answer,
                        sdp: sdp.sdp
                    )
                )
            }
        }
    }

    public func setLocalDescription(_ description: SessionDescription) async throws {
        guard let peerConnection else { throw WebRTCError.noConnection }
        let rtcType: RTCSdpType = description.type == .offer ? .offer : .answer
        let rtcDescription = RTCSessionDescription(type: rtcType, sdp: description.sdp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(rtcDescription) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func setRemoteDescription(_ description: SessionDescription) async throws {
        guard let peerConnection else { throw WebRTCError.noConnection }
        let rtcType: RTCSdpType = description.type == .offer ? .offer : .answer
        let rtcDescription = RTCSessionDescription(type: rtcType, sdp: description.sdp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(rtcDescription) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        for candidate in stateBox.drainPendingCandidates() {
            try? await addRemoteIceCandidate(candidate)
        }
        publishKnownRemoteTracks(reason: "after setRemoteDescription")
    }

    public func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async throws {
        guard let peerConnection else { return }
        guard peerConnection.remoteDescription != nil else {
            stateBox.appendPendingCandidate(candidate)
            return
        }

        let rawCandidate = candidate.candidate.hasPrefix("a=")
            ? String(candidate.candidate.dropFirst(2))
            : candidate.candidate
        let rtcCandidate = RTCIceCandidate(
            sdp: rawCandidate,
            sdpMLineIndex: Int32(candidate.sdpMLineIndex),
            sdpMid: candidate.sdpMid
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(rtcCandidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public var localIceCandidates: [IceCandidatePayload] {
        get async { stateBox.localCandidates() }
    }

    public var connectionState: PeerConnectionState {
        get async {
            switch peerConnection?.connectionState {
            case .connected:
                return .connected
            case .disconnected:
                return .disconnected
            case .failed:
                return .failed
            case .closed:
                return .closed
            case .connecting:
                return .connecting
            default:
                return .new
            }
        }
    }

    public func close() async {
        let activePeerConnection = peerConnection
        let activeDataChannels = dataChannels
        callbackStateBox.invalidateRuntime()
        peerConnection = nil
        dataChannels = [:]
        dataChannelDelegateProxies = [:]

        activePeerConnection?.delegate = nil
        for channel in activeDataChannels.values {
            channel.delegate = nil
        }
        activePeerConnection?.close()
        stateBox.reset()
        statsStateBox.reset()
        remoteAudioTrack = nil
        highAudioDelayStrikeCount = 0
        lastAudioResyncTriggerTimestamp = 0
        audioResyncTriggerCount = 0
#if os(tvOS)
        resetTVOSAudioStartGate(reason: "close")
        RTCAudioSession.sharedInstance().remove(self)
#endif
    }
}

#endif
