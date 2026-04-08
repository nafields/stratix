// WebRTCClientImplRTCPeerConnectionDelegate.swift
// Defines web rtc client impl rtc peer connection delegate for the Integration / WebRTC surface.
//

#if WEBRTC_AVAILABLE
import Foundation
import StratixModels
import StreamingCore

extension WebRTCClientImpl: RTCPeerConnectionDelegate {
    public func peerConnection(_ pc: RTCPeerConnection,
                               didChange state: RTCSignalingState) {
        print("[WebRTC] signaling state: \(String(describing: state))")
    }

    public func peerConnection(_ pc: RTCPeerConnection,
                               didAdd stream: RTCMediaStream) {}

    public func peerConnection(_ pc: RTCPeerConnection,
                               didRemove stream: RTCMediaStream) {}

    public func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}

    public func peerConnection(_ pc: RTCPeerConnection,
                               didChange state: RTCIceConnectionState) {
        print("[WebRTC] ICE connection state: \(String(describing: state))")
    }

    public func peerConnection(_ pc: RTCPeerConnection,
                               didChange state: RTCIceGatheringState) {
        print("[WebRTC] ICE gathering state: \(String(describing: state))")
    }

    public func peerConnection(_ pc: RTCPeerConnection,
                               didGenerate candidate: RTCIceCandidate) {
        guard let generation = peerConnectionGeneration(for: pc) else { return }
        let payload = IceCandidatePayload(
            candidate: "a=\(candidate.sdp)",
            sdpMLineIndex: Int(candidate.sdpMLineIndex),
            sdpMid: candidate.sdpMid ?? "0"
        )
        appendLocalCandidate(payload)
        callbackDelegate(for: generation)?.webRTC(self, didGatherCandidate: payload)
    }

    public func peerConnection(_ pc: RTCPeerConnection,
                               didRemove candidates: [RTCIceCandidate]) {}

    public func peerConnection(_ pc: RTCPeerConnection,
                               didOpen dataChannel: RTCDataChannel) {
        print("[WebRTC] remote-opened data channel label=\(dataChannel.label) protocol=\(dataChannel.`protocol`)")
    }

    public func peerConnection(_ pc: RTCPeerConnection,
                               didChange newState: RTCPeerConnectionState) {
        guard let generation = peerConnectionGeneration(for: pc) else { return }
        print("[WebRTC] peer connection state: \(String(describing: newState))")
        let mapped: PeerConnectionState
        switch newState {
        case .new:          mapped = .new
        case .connecting:   mapped = .connecting
        case .connected:    mapped = .connected
        case .disconnected: mapped = .disconnected
        case .failed:       mapped = .failed
        case .closed:       mapped = .closed
        @unknown default:   mapped = .new
        }
        if newState == .connected {
            handlePeerConnectionConnected(generation: generation)
        }
        callbackDelegate(for: generation)?.webRTC(self, didChangeConnectionState: mapped)
    }

    public func peerConnection(_ pc: RTCPeerConnection,
                               didStartReceivingOn transceiver: RTCRtpTransceiver) {
        guard let generation = peerConnectionGeneration(for: pc) else { return }
        print("[WebRTC] didStartReceivingOnTransceiver mid=\(transceiver.mid) mediaType=\(transceiver.mediaType.rawValue)")
        if let track = transceiver.receiver.track {
            handlePeerConnectionTrackStart(
                track,
                reason: "didStartReceivingOnTransceiver",
                generation: generation
            )
        }
    }

    public func peerConnection(_ pc: RTCPeerConnection,
                               didAdd rtpReceiver: RTCRtpReceiver,
                               streams mediaStreams: [RTCMediaStream]) {
        guard let generation = peerConnectionGeneration(for: pc) else { return }
        guard let track = rtpReceiver.track else { return }
        handlePeerConnectionTrackStart(
            track,
            reason: "didAddReceiver",
            generation: generation
        )
    }
}
#endif
