// WebRTCClientStateSupport.swift
// Provides shared support for the Integration / WebRTC surface.
//

import Foundation
import StratixModels
import os
import StreamingCore

struct MockWebRTCBridgeState: Sendable {
    weak var delegate: (any WebRTCBridgeDelegate)?
    var localCandidates: [IceCandidatePayload] = []
    var connectionState: PeerConnectionState = .new
}

final class MockWebRTCBridgeStateBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: MockWebRTCBridgeState())

    var delegate: (any WebRTCBridgeDelegate)? {
        get { state.withLock { $0.delegate } }
        set { state.withLock { $0.delegate = newValue } }
    }

    func setConnectionState(_ connectionState: PeerConnectionState) {
        state.withLock { $0.connectionState = connectionState }
    }

    func localCandidates() -> [IceCandidatePayload] {
        state.withLock { $0.localCandidates }
    }

    func connectionState() -> PeerConnectionState {
        state.withLock { $0.connectionState }
    }
}

#if WEBRTC_AVAILABLE

struct WebRTCClientCallbackState: Sendable {
    weak var delegate: (any WebRTCBridgeDelegate)?
    var callbackGeneration: UInt64 = 0
    var activePeerConnectionIdentity: ObjectIdentifier?
    var activeDataChannelKindsByIdentity: [ObjectIdentifier: DataChannelKind] = [:]
}

final class WebRTCClientCallbackStateBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: WebRTCClientCallbackState())

    var delegate: (any WebRTCBridgeDelegate)? {
        get { state.withLock { $0.delegate } }
        set { state.withLock { $0.delegate = newValue } }
    }

    func currentGeneration() -> UInt64 {
        state.withLock { $0.callbackGeneration }
    }

    @discardableResult
    func refreshRuntime(peerConnection: AnyObject?, dataChannels: [DataChannelKind: AnyObject]) -> UInt64 {
        let activePeerConnectionIdentity = peerConnection.map(ObjectIdentifier.init)
        let activeDataChannelKindsByIdentity = Dictionary(
            uniqueKeysWithValues: dataChannels.map { (ObjectIdentifier($0.value), $0.key) }
        )
        return state.withLock { state in
            state.callbackGeneration &+= 1
            state.activePeerConnectionIdentity = activePeerConnectionIdentity
            state.activeDataChannelKindsByIdentity = activeDataChannelKindsByIdentity
            return state.callbackGeneration
        }
    }

    @discardableResult
    func invalidateRuntime() -> UInt64 {
        refreshRuntime(peerConnection: nil, dataChannels: [:])
    }

    func isCurrentGeneration(_ generation: UInt64) -> Bool {
        state.withLock { $0.callbackGeneration == generation }
    }

    func delegate(for generation: UInt64) -> (any WebRTCBridgeDelegate)? {
        state.withLock { state -> (any WebRTCBridgeDelegate)? in
            guard state.callbackGeneration == generation else { return nil }
            return state.delegate
        }
    }

    func activePeerConnectionGeneration(for peerConnection: AnyObject) -> UInt64? {
        let identity = ObjectIdentifier(peerConnection)
        return state.withLock { state -> UInt64? in
            guard state.activePeerConnectionIdentity == identity else { return nil }
            return state.callbackGeneration
        }
    }

    func activeDataChannelContext(for dataChannel: AnyObject) -> (generation: UInt64, kind: DataChannelKind)? {
        let identity = ObjectIdentifier(dataChannel)
        return state.withLock { state -> (generation: UInt64, kind: DataChannelKind)? in
            guard let kind = state.activeDataChannelKindsByIdentity[identity] else { return nil }
            return (state.callbackGeneration, kind)
        }
    }
}

struct WebRTCClientState: Sendable {
    var pendingCandidates: [IceCandidatePayload] = []
    var surfacedOpenDataChannels = Set<DataChannelKind>()
    var surfacedRemoteTrackIDs = Set<ObjectIdentifier>()
    var surfacedRemoteTrackIDsByString = Set<String>()
    var localCandidateList: [IceCandidatePayload] = []
}

final class WebRTCClientStateBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: WebRTCClientState())

    func reset() {
        state.withLock { state in
            state.pendingCandidates.removeAll(keepingCapacity: true)
            state.surfacedOpenDataChannels.removeAll(keepingCapacity: true)
            state.surfacedRemoteTrackIDs.removeAll(keepingCapacity: true)
            state.surfacedRemoteTrackIDsByString.removeAll(keepingCapacity: true)
            state.localCandidateList.removeAll(keepingCapacity: true)
        }
    }

    func appendPendingCandidate(_ candidate: IceCandidatePayload) {
        state.withLock { $0.pendingCandidates.append(candidate) }
    }

    func drainPendingCandidates() -> [IceCandidatePayload] {
        state.withLock { state in
            let candidates = state.pendingCandidates
            state.pendingCandidates.removeAll(keepingCapacity: true)
            return candidates
        }
    }

    func appendLocalCandidate(_ candidate: IceCandidatePayload) {
        state.withLock { $0.localCandidateList.append(candidate) }
    }

    func localCandidates() -> [IceCandidatePayload] {
        state.withLock { $0.localCandidateList }
    }

    func markRemoteTrackIfNeeded(trackID: String, identity: ObjectIdentifier) -> Bool {
        state.withLock { state in
            if !trackID.isEmpty {
                return state.surfacedRemoteTrackIDsByString.insert(trackID).inserted
            }
            return state.surfacedRemoteTrackIDs.insert(identity).inserted
        }
    }

    func markOpenDataChannelIfNeeded(_ kind: DataChannelKind) -> Bool {
        state.withLock { $0.surfacedOpenDataChannels.insert(kind).inserted }
    }

    func markDataChannelOpened(_ kind: DataChannelKind) {
        _ = state.withLock { $0.surfacedOpenDataChannels.insert(kind) }
    }
}

struct WebRTCClientStatsState: Sendable {
    var lastVideoBytesReceived: UInt64 = 0
    var lastVideoStatsTimestamp: TimeInterval = 0
    var lastVideoStatsLogTimestamp: TimeInterval = 0
    var lastAudioBytesReceived: UInt64 = 0
    var lastAudioStatsTimestamp: TimeInterval = 0
    var lastAudioStatsLogTimestamp: TimeInterval = 0
    var lastAudioJitterBufferDelaySecondsTotal: Double?
    var lastAudioJitterBufferEmittedCountTotal: Double?
    var lastAudioJitterBufferTargetDelaySecondsTotal: Double?
    var lastAudioJitterBufferMinimumDelaySecondsTotal: Double?
    var lastAudioWebRTCTimestamp: TimeInterval?
}

struct WebRTCClientStatsWindow: Sendable {
    var videoBitrateKbps: Int?
    var audioBitrateKbps: Int?
    var audioJitterBufferWindowDelayMs: Double?
    var audioJitterBufferWindowTargetMs: Double?
    var audioJitterBufferWindowUncappedMs: Double?
    var audioPlayoutRatePct: Double?
    var shouldLogAudio = false
    var shouldLogVideo = false
}

final class WebRTCClientStatsStateBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: WebRTCClientStatsState())

    func reset() {
        state.withLock { $0 = WebRTCClientStatsState() }
    }

    func resetAudioWindow() {
        state.withLock { state in
            state.lastAudioBytesReceived = 0
            state.lastAudioStatsTimestamp = 0
            state.lastAudioStatsLogTimestamp = 0
            state.lastAudioJitterBufferDelaySecondsTotal = nil
            state.lastAudioJitterBufferEmittedCountTotal = nil
            state.lastAudioJitterBufferTargetDelaySecondsTotal = nil
            state.lastAudioJitterBufferMinimumDelaySecondsTotal = nil
            state.lastAudioWebRTCTimestamp = nil
        }
    }

    func snapshot() -> WebRTCClientStatsState {
        state.withLock { $0 }
    }

    func consumeMetricsWindow(
        videoBytesReceived: UInt64?,
        videoStatsTimestamp: TimeInterval?,
        audioBytesReceived: UInt64?,
        audioStatsTimestamp: TimeInterval?,
        audioJitterBufferDelaySeconds: Double?,
        audioJitterBufferTargetDelaySeconds: Double?,
        audioJitterBufferMinimumDelaySeconds: Double?,
        audioJitterBufferEmittedCount: Double?
    ) -> WebRTCClientStatsWindow {
        state.withLock { state in
            var window = WebRTCClientStatsWindow()

            if let bytes = videoBytesReceived, let timestamp = videoStatsTimestamp {
                if state.lastVideoStatsTimestamp > 0, timestamp > state.lastVideoStatsTimestamp {
                    let delta = bytes > state.lastVideoBytesReceived ? bytes - state.lastVideoBytesReceived : 0
                    let elapsed = timestamp - state.lastVideoStatsTimestamp
                    window.videoBitrateKbps = Int(Double(delta * 8) / elapsed / 1000)
                }
                state.lastVideoBytesReceived = bytes
                state.lastVideoStatsTimestamp = timestamp
            }

            if let bytes = audioBytesReceived, let timestamp = audioStatsTimestamp {
                if state.lastAudioStatsTimestamp > 0, timestamp > state.lastAudioStatsTimestamp {
                    let delta = bytes > state.lastAudioBytesReceived ? bytes - state.lastAudioBytesReceived : 0
                    let elapsed = timestamp - state.lastAudioStatsTimestamp
                    window.audioBitrateKbps = Int(Double(delta * 8) / elapsed / 1000)
                }
                state.lastAudioBytesReceived = bytes
                state.lastAudioStatsTimestamp = timestamp
            }

            let previousWindowEmitted = state.lastAudioJitterBufferEmittedCountTotal

            if let totalDelay = audioJitterBufferDelaySeconds,
               let totalEmitted = audioJitterBufferEmittedCount,
               totalEmitted > 0 {
                if let previousDelay = state.lastAudioJitterBufferDelaySecondsTotal,
                   let previousEmitted = previousWindowEmitted {
                    let deltaDelay = totalDelay - previousDelay
                    let deltaEmitted = totalEmitted - previousEmitted
                    if deltaDelay >= 0, deltaEmitted > 0 {
                        window.audioJitterBufferWindowDelayMs = (deltaDelay / deltaEmitted) * 1000.0
                    }
                }
                state.lastAudioJitterBufferDelaySecondsTotal = totalDelay
                state.lastAudioJitterBufferEmittedCountTotal = totalEmitted
            }

            if let totalTarget = audioJitterBufferTargetDelaySeconds,
               let totalEmitted = audioJitterBufferEmittedCount,
               totalEmitted > 0 {
                if let previousTarget = state.lastAudioJitterBufferTargetDelaySecondsTotal,
                   let previousEmitted = previousWindowEmitted {
                    let deltaTarget = totalTarget - previousTarget
                    let deltaEmitted = totalEmitted - previousEmitted
                    if deltaTarget >= 0, deltaEmitted > 0 {
                        window.audioJitterBufferWindowTargetMs = (deltaTarget / deltaEmitted) * 1000.0
                    }
                }
                state.lastAudioJitterBufferTargetDelaySecondsTotal = totalTarget
            }

            if let totalUncapped = audioJitterBufferMinimumDelaySeconds,
               let totalEmitted = audioJitterBufferEmittedCount,
               totalEmitted > 0 {
                if let previousUncapped = state.lastAudioJitterBufferMinimumDelaySecondsTotal,
                   let previousEmitted = previousWindowEmitted {
                    let deltaUncapped = totalUncapped - previousUncapped
                    let deltaEmitted = totalEmitted - previousEmitted
                    if deltaUncapped >= 0, deltaEmitted > 0 {
                        window.audioJitterBufferWindowUncappedMs = (deltaUncapped / deltaEmitted) * 1000.0
                    }
                }
                state.lastAudioJitterBufferMinimumDelaySecondsTotal = totalUncapped
            }

            if let timestamp = audioStatsTimestamp,
               let previousTimestamp = state.lastAudioWebRTCTimestamp,
               timestamp > previousTimestamp,
               let previousEmitted = previousWindowEmitted,
               let totalEmitted = audioJitterBufferEmittedCount,
               totalEmitted > previousEmitted {
                let deltaEmitted = totalEmitted - previousEmitted
                let deltaTimestamp = timestamp - previousTimestamp
                if deltaTimestamp > 0 {
                    window.audioPlayoutRatePct = (deltaEmitted / (deltaTimestamp * 48_000.0)) * 100.0
                }
            }
            state.lastAudioWebRTCTimestamp = audioStatsTimestamp

            if let now = audioStatsTimestamp ?? videoStatsTimestamp,
               now - state.lastAudioStatsLogTimestamp >= 1 {
                window.shouldLogAudio = true
                state.lastAudioStatsLogTimestamp = now
            }

            if let now = videoStatsTimestamp,
               now - state.lastVideoStatsLogTimestamp >= 1 {
                window.shouldLogVideo = true
                state.lastVideoStatsLogTimestamp = now
            }

            return window
        }
    }
}

#if os(tvOS)
final class TVOSAudioDefaultsGate: Sendable {
    private let didConfigureState = OSAllocatedUnfairLock(initialState: false)

    func configureIfNeeded(_ configure: () -> Void) {
        let shouldConfigure = didConfigureState.withLock { didConfigure in
            guard !didConfigure else { return false }
            didConfigure = true
            return true
        }
        guard shouldConfigure else { return }
        configure()
    }
}
#endif

#endif
