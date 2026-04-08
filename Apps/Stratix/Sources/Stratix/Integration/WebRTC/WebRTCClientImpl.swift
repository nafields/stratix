// WebRTCClientImpl.swift
// Defines the app-owned WebRTC bridge, including the mock bridge and the concrete framework-backed implementation.
//

import Foundation
import os
#if canImport(AVFoundation)
import AVFoundation
#endif
import StratixCore
import StratixModels
import StreamingCore

// MARK: - WebRTC Client Implementation
//
// Two implementations live here:
//   1. MockWebRTCBridge  — no-op, always compiled, used for UI dev and unit tests
//   2. WebRTCClientImpl  — real RTCPeerConnection, compiled when WEBRTC_AVAILABLE flag is set
//
// To activate the real implementation:
//   1. Build WebRTC.xcframework:  Tools/webrtc-build/build_webrtc_tvos.sh
//   2. Run packaging:             Tools/webrtc-build/package_xcframework.sh
//   3. In Xcode → app target → Frameworks: drag in ThirdParty/WebRTC/WebRTC.xcframework
//      Set embed to "Embed & Sign"
//   4. Build Settings → Swift Compiler - Custom Flags → OTHER_SWIFT_FLAGS: add -DWEBRTC_AVAILABLE
//   5. Build Settings → Swift Compiler - Code Generation → SWIFT_OBJC_BRIDGING_HEADER:
//      Set to Stratix/Stratix-Bridging-Header.h

// ============================================================
// MARK: - Mock Bridge (always compiled — no framework needed)
// ============================================================

/// Provides a no-op bridge that keeps previews and tests off the vendored WebRTC framework.
public final class MockWebRTCBridge: WebRTCBridge {
    private let stateBox = MockWebRTCBridgeStateBox()

    public var delegate: (any WebRTCBridgeDelegate)? {
        get { stateBox.delegate }
        set { stateBox.delegate = newValue }
    }

    public init() {}

    public func applyH264CodecPreferences() {}

    /// Returns a synthetic SDP offer so higher layers can exercise the happy-path startup flow.
    public func createOffer() async throws -> SessionDescription {
        let sdp = """
        v=0\r
        o=- 0 0 IN IP4 127.0.0.1\r
        s=-\r
        t=0 0\r
        m=audio 9 UDP/TLS/RTP/SAVPF 111\r
        c=IN IP4 0.0.0.0\r
        a=rtpmap:111 opus/48000/2\r
        m=video 9 UDP/TLS/RTP/SAVPF 96\r
        c=IN IP4 0.0.0.0\r
        a=rtpmap:96 H264/90000\r
        """
        return SessionDescription(type: .offer, sdp: sdp)
    }

    public func setLocalDescription(_ sdp: SessionDescription) async throws {}

    /// Simulates a connected peer and opened data channels once the remote description is applied.
    public func setRemoteDescription(_ sdp: SessionDescription) async throws {
        stateBox.setConnectionState(.connected)
        delegate?.webRTC(self, didChangeConnectionState: .connected)
        for kind in DataChannelKind.allCases {
            delegate?.webRTC(self, channelDidOpen: kind)
        }
    }

    public func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async throws {}

    public var localIceCandidates: [IceCandidatePayload] {
        get async { stateBox.localCandidates() }
    }

    public var connectionState: PeerConnectionState {
        get async { stateBox.connectionState() }
    }

    public func send(channelKind: DataChannelKind, data: Data) async throws {}
    public func sendString(channelKind: DataChannelKind, text: String) async throws {}

    /// Transitions the mock connection state to closed and notifies the delegate.
    public func close() async {
        stateBox.setConnectionState(.closed)
        delegate?.webRTC(self, didChangeConnectionState: .closed)
    }
}

// ============================================================
// MARK: - Real WebRTC Bridge (requires WebRTC.xcframework)
// ============================================================

#if WEBRTC_AVAILABLE

/// Full RTCPeerConnection-backed implementation of WebRTCBridge.
/// Mirrors the setup in xbox-xcloud-player/src/player.ts.
public final class WebRTCClientImpl: NSObject, WebRTCBridge, @unchecked Sendable {

    public var delegate: (any WebRTCBridgeDelegate)? {
        get { callbackStateBox.delegate }
        set { callbackStateBox.delegate = newValue }
    }

    private let factory: RTCPeerConnectionFactory
    let callbackStateBox = WebRTCClientCallbackStateBox()
    let stateBox = WebRTCClientStateBox()
    let statsStateBox = WebRTCClientStatsStateBox()
    var peerConnection: RTCPeerConnection?
    var dataChannels: [DataChannelKind: RTCDataChannel] = [:]
    var dataChannelDelegateProxies: [DataChannelKind: DataChannelDelegateProxy] = [:]
    /// Retained so we can re-apply the boost gain when the slider changes during a stream.
    var remoteAudioTrack: RTCAudioTrack?
    var audioReconcileQueued = false
    var audioReconcileInProgress = false
    // Companion-file tvOS audio runtime state lives in WebRTCClientImplTVOSAudio.swift.
    var highAudioDelayStrikeCount = 0
    var lastAudioResyncTriggerTimestamp: TimeInterval = 0
    var audioResyncTriggerCount: Int = 0
    var audioResyncDrainInProgress = false
    var audioGateOpenedAtTimestamp: TimeInterval?
    let audioGateQueue = DispatchQueue(label: "com.stratix.app.webrtc.audioGate")
    var audioGateHasRemoteTrack = false
    var audioGatePeerConnected = false
    var audioGateOpened = false
    let dataChannelSendFailureQueue = DispatchQueue(label: "com.stratix.app.webrtc.sendFailure")
    var dataChannelSendFailureWindowStartMs: Double = 0
    var dataChannelSendFailureWindowCount: Int = 0
#if os(tvOS)
    private static let tvosAudioDefaultsGate = TVOSAudioDefaultsGate()
#endif

    /// Sends verbose renderer stats to the debug console without exposing a public logging API.
    func logVideoStats(_ message: @autoclosure () -> String) {
        print("[WebRTC][VideoStats] \(message())")
    }

    // MARK: - Init

    /// Builds the peer connection, default audio configuration, and data-channel callback wiring.
    public override init() {
        RTCInitializeSSL()
#if os(tvOS)
        Self.tvosAudioDefaultsGate.configureIfNeeded {
            Self.configureWebRTCDefaultAudioConfigurationForTVOSIfNeeded()
            Self.configureAudioSessionForTVOSPlaybackIfNeeded()
        }
#endif
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
        super.init()

        let config = RTCConfiguration()
        config.iceServers = []            // Xbox provides candidates via its own HTTP signalling
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        peerConnection = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )
        callbackStateBox.refreshRuntime(peerConnection: peerConnection, dataChannels: [:])
#if os(tvOS)
        RTCAudioSession.sharedInstance().add(self)
#endif
    }

    /// Removes tvOS audio-session observation when the bridge is released.
    deinit {
#if os(tvOS)
        RTCAudioSession.sharedInstance().remove(self)
#endif
    }
}

// MARK: - Internal error type

enum WebRTCError: Error, LocalizedError {
    case noConnection
    case noSDP
    case dataChannelUnavailable(channelKind: String)
    case dataChannelSendRejected(channelKind: String, readyStateRawValue: Int, bufferedAmount: String)

    var errorDescription: String? {
        switch self {
        case .noConnection: return "RTCPeerConnection is not initialized"
        case .noSDP: return "RTCPeerConnection returned nil SDP"
        case .dataChannelUnavailable(let channelKind):
            return "Data channel '\(channelKind)' is unavailable"
        case .dataChannelSendRejected(let channelKind, let readyStateRawValue, let bufferedAmount):
            return "Data channel '\(channelKind)' send rejected (readyState=\(readyStateRawValue), bufferedAmount=\(bufferedAmount))"
        }
    }
}

#endif // WEBRTC_AVAILABLE
