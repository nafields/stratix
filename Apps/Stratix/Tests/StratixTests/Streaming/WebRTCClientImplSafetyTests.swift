// WebRTCClientImplSafetyTests.swift
// Exercises web rtc client impl safety behavior.
//

import XCTest
import StratixModels
import StreamingCore

#if canImport(Stratix) && WEBRTC_AVAILABLE
@testable import Stratix

final class WebRTCClientImplSafetyTests: XCTestCase {
    func testCallbackStateBoxInvalidationDropsLateContexts() {
        let stateBox = WebRTCClientCallbackStateBox()
        let delegate = DelegateSpy()
        stateBox.delegate = delegate

        let peerConnection = NSObject()
        let inputChannel = NSObject()
        let generation = stateBox.refreshRuntime(
            peerConnection: peerConnection,
            dataChannels: [.input: inputChannel]
        )

        XCTAssertEqual(stateBox.activePeerConnectionGeneration(for: peerConnection), generation)
        XCTAssertEqual(stateBox.activeDataChannelContext(for: inputChannel)?.generation, generation)
        XCTAssertEqual(stateBox.activeDataChannelContext(for: inputChannel)?.kind, .input)
        XCTAssertNotNil(stateBox.delegate(for: generation))

        stateBox.invalidateRuntime()

        XCTAssertNil(stateBox.activePeerConnectionGeneration(for: peerConnection))
        XCTAssertNil(stateBox.activeDataChannelContext(for: inputChannel))
        XCTAssertNil(stateBox.delegate(for: generation))
        XCTAssertFalse(stateBox.isCurrentGeneration(generation))
    }

    func testCallbackStateBoxRefreshReplacesStaleDataChannelIdentity() {
        let stateBox = WebRTCClientCallbackStateBox()

        let firstPeerConnection = NSObject()
        let firstInputChannel = NSObject()
        let firstGeneration = stateBox.refreshRuntime(
            peerConnection: firstPeerConnection,
            dataChannels: [.input: firstInputChannel]
        )

        let secondPeerConnection = NSObject()
        let secondInputChannel = NSObject()
        let secondGeneration = stateBox.refreshRuntime(
            peerConnection: secondPeerConnection,
            dataChannels: [.input: secondInputChannel]
        )

        XCTAssertNotEqual(firstGeneration, secondGeneration)
        XCTAssertNil(stateBox.activePeerConnectionGeneration(for: firstPeerConnection))
        XCTAssertNil(stateBox.activeDataChannelContext(for: firstInputChannel))
        XCTAssertEqual(stateBox.activePeerConnectionGeneration(for: secondPeerConnection), secondGeneration)
        XCTAssertEqual(stateBox.activeDataChannelContext(for: secondInputChannel)?.generation, secondGeneration)
        XCTAssertEqual(stateBox.activeDataChannelContext(for: secondInputChannel)?.kind, .input)
    }

    func testStatsStateBoxTracksRollingWindowAndReset() {
        let stateBox = WebRTCClientStatsStateBox()

        let firstWindow = stateBox.consumeMetricsWindow(
            videoBytesReceived: 1_000,
            videoStatsTimestamp: 1,
            audioBytesReceived: 2_000,
            audioStatsTimestamp: 1,
            audioJitterBufferDelaySeconds: 0.4,
            audioJitterBufferTargetDelaySeconds: 0.6,
            audioJitterBufferMinimumDelaySeconds: 0.8,
            audioJitterBufferEmittedCount: 48_000
        )
        XCTAssertNil(firstWindow.videoBitrateKbps)
        XCTAssertNil(firstWindow.audioBitrateKbps)

        let secondWindow = stateBox.consumeMetricsWindow(
            videoBytesReceived: 3_000,
            videoStatsTimestamp: 2,
            audioBytesReceived: 4_000,
            audioStatsTimestamp: 2,
            audioJitterBufferDelaySeconds: 0.8,
            audioJitterBufferTargetDelaySeconds: 1.2,
            audioJitterBufferMinimumDelaySeconds: 1.6,
            audioJitterBufferEmittedCount: 96_000
        )
        XCTAssertEqual(secondWindow.videoBitrateKbps, 16)
        XCTAssertEqual(secondWindow.audioBitrateKbps, 16)
        XCTAssertNotNil(secondWindow.audioJitterBufferWindowDelayMs)
        XCTAssertNotNil(secondWindow.audioJitterBufferWindowTargetMs)
        XCTAssertNotNil(secondWindow.audioJitterBufferWindowUncappedMs)
        XCTAssertNotNil(secondWindow.audioPlayoutRatePct)

        let populatedSnapshot = stateBox.snapshot()
        XCTAssertEqual(populatedSnapshot.lastVideoBytesReceived, 3_000)
        XCTAssertEqual(populatedSnapshot.lastAudioBytesReceived, 4_000)
        XCTAssertNotNil(populatedSnapshot.lastAudioJitterBufferDelaySecondsTotal)
        XCTAssertNotNil(populatedSnapshot.lastAudioWebRTCTimestamp)

        stateBox.reset()

        let resetSnapshot = stateBox.snapshot()
        XCTAssertEqual(resetSnapshot.lastVideoBytesReceived, 0)
        XCTAssertEqual(resetSnapshot.lastAudioBytesReceived, 0)
        XCTAssertEqual(resetSnapshot.lastVideoStatsTimestamp, 0)
        XCTAssertEqual(resetSnapshot.lastAudioStatsTimestamp, 0)
        XCTAssertNil(resetSnapshot.lastAudioJitterBufferDelaySecondsTotal)
        XCTAssertNil(resetSnapshot.lastAudioJitterBufferTargetDelaySecondsTotal)
        XCTAssertNil(resetSnapshot.lastAudioJitterBufferMinimumDelaySecondsTotal)
        XCTAssertNil(resetSnapshot.lastAudioWebRTCTimestamp)
    }

    func testStatsStateBoxResetAudioWindowPreservesVideoWindow() {
        let stateBox = WebRTCClientStatsStateBox()

        _ = stateBox.consumeMetricsWindow(
            videoBytesReceived: 1_000,
            videoStatsTimestamp: 1,
            audioBytesReceived: 2_000,
            audioStatsTimestamp: 1,
            audioJitterBufferDelaySeconds: 0.4,
            audioJitterBufferTargetDelaySeconds: 0.6,
            audioJitterBufferMinimumDelaySeconds: 0.8,
            audioJitterBufferEmittedCount: 48_000
        )
        _ = stateBox.consumeMetricsWindow(
            videoBytesReceived: 3_000,
            videoStatsTimestamp: 2,
            audioBytesReceived: 4_000,
            audioStatsTimestamp: 2,
            audioJitterBufferDelaySeconds: 0.8,
            audioJitterBufferTargetDelaySeconds: 1.2,
            audioJitterBufferMinimumDelaySeconds: 1.6,
            audioJitterBufferEmittedCount: 96_000
        )

        stateBox.resetAudioWindow()

        let snapshot = stateBox.snapshot()
        XCTAssertEqual(snapshot.lastVideoBytesReceived, 3_000)
        XCTAssertEqual(snapshot.lastVideoStatsTimestamp, 2)
        XCTAssertEqual(snapshot.lastAudioBytesReceived, 0)
        XCTAssertEqual(snapshot.lastAudioStatsTimestamp, 0)
        XCTAssertNil(snapshot.lastAudioJitterBufferDelaySecondsTotal)
        XCTAssertNil(snapshot.lastAudioJitterBufferTargetDelaySecondsTotal)
        XCTAssertNil(snapshot.lastAudioJitterBufferMinimumDelaySecondsTotal)
        XCTAssertNil(snapshot.lastAudioWebRTCTimestamp)
    }
}

private final class DelegateSpy: NSObject, WebRTCBridgeDelegate {
    func webRTC(_ bridge: any WebRTCBridge, didChangeConnectionState state: PeerConnectionState) {}
    func webRTC(_ bridge: any WebRTCBridge, didGatherCandidate candidate: IceCandidatePayload) {}
    func webRTC(_ bridge: any WebRTCBridge, channel: DataChannelKind, didReceiveData data: Data) {}
    func webRTC(_ bridge: any WebRTCBridge, channel: DataChannelKind, didReceiveText text: String) {}
    func webRTC(_ bridge: any WebRTCBridge, channelDidOpen channel: DataChannelKind) {}
    func webRTC(_ bridge: any WebRTCBridge, didReceiveVideoTrack videoTrack: AnyObject) {}
    func webRTC(_ bridge: any WebRTCBridge, didReceiveAudioTrack audioTrack: AnyObject) {}
}
#endif
