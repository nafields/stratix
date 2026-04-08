// WebRTCBridge.swift
// Defines web rtc bridge.
//

import Foundation
import StratixModels

public struct DataChannelRuntimeStats: Sendable, Equatable {
    public let readyStateRawValue: Int
    public let bufferedAmountBytes: UInt64?

    public init(readyStateRawValue: Int, bufferedAmountBytes: UInt64?) {
        self.readyStateRawValue = readyStateRawValue
        self.bufferedAmountBytes = bufferedAmountBytes
    }
}

// MARK: - WebRTC Bridge Protocol
//
// This protocol abstracts the WebRTC peer connection so that:
// 1. Production code uses the real WebRTC.xcframework implementation.
// 2. Tests can use a mock without a real WebRTC build.
//
// When WebRTC.xcframework is available (built from Google source for tvOS),
// WebRTCClientImpl in the app target conforms to this protocol.

public protocol WebRTCBridge: AnyObject, Sendable {
    /// Create an SDP offer including audio (sendrecv) and video (recvonly) transceivers.
    func createOffer() async throws -> SessionDescription

    /// Apply codec preferences for H.264 (High > Main > Baseline) before creating offer.
    func applyH264CodecPreferences()

    /// Set our local description (the processed offer).
    func setLocalDescription(_ sdp: SessionDescription) async throws

    /// Set the remote description (the server's SDP answer).
    func setRemoteDescription(_ sdp: SessionDescription) async throws

    /// Add a remote ICE candidate.
    func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async throws

    /// Return all locally gathered ICE candidates.
    var localIceCandidates: [IceCandidatePayload] { get async }

    /// Current connection state.
    var connectionState: PeerConnectionState { get async }

    /// Send data over a named data channel.
    func send(channelKind: DataChannelKind, data: Data) async throws

    /// Send a string over a named data channel.
    func sendString(channelKind: DataChannelKind, text: String) async throws

    /// Lightweight runtime stats for a data channel (if available).
    func dataChannelRuntimeStats(channelKind: DataChannelKind) -> DataChannelRuntimeStats?

    /// Delegate for events from the peer connection.
    var delegate: WebRTCBridgeDelegate? { get set }

    /// Tear down the peer connection.
    func close() async

    /// Collect a stats snapshot from the peer connection.
    func collectStats() async -> StreamingStatsSnapshot
}

extension WebRTCBridge {
    public func collectStats() async -> StreamingStatsSnapshot { StreamingStatsSnapshot() }
    public func dataChannelRuntimeStats(channelKind: DataChannelKind) -> DataChannelRuntimeStats? { nil }
}

// MARK: - WebRTC Bridge Delegate

public protocol WebRTCBridgeDelegate: AnyObject, Sendable {
    /// Called when the peer connection state changes.
    func webRTC(_ bridge: any WebRTCBridge, didChangeConnectionState state: PeerConnectionState)

    /// Called when a new ICE candidate is gathered locally.
    func webRTC(_ bridge: any WebRTCBridge, didGatherCandidate candidate: IceCandidatePayload)

    /// Called when a data channel receives a binary message.
    func webRTC(_ bridge: any WebRTCBridge, channel: DataChannelKind, didReceiveData data: Data)

    /// Called when a data channel receives a text message.
    func webRTC(_ bridge: any WebRTCBridge, channel: DataChannelKind, didReceiveText text: String)

    /// Called when a data channel opens.
    func webRTC(_ bridge: any WebRTCBridge, channelDidOpen channel: DataChannelKind)

    /// Called when a video track is received. The opaque videoTrack object is platform-specific.
    func webRTC(_ bridge: any WebRTCBridge, didReceiveVideoTrack videoTrack: AnyObject)

    /// Called when an audio track is received.
    func webRTC(_ bridge: any WebRTCBridge, didReceiveAudioTrack audioTrack: AnyObject)
}
