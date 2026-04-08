// StreamingSessionBridgeDelegate.swift
// Defines streaming session bridge delegate.
//

import Foundation
import StratixModels
import os

final class StreamingSessionBridgeDelegate: WebRTCBridgeDelegate, Sendable {
    private let runtime: StreamingRuntime
    private let activeGenerationState: OSAllocatedUnfairLock<UInt64>

    init(runtime: StreamingRuntime, generationBox: StreamingRuntimeGenerationBox) {
        self.runtime = runtime
        self.activeGenerationState = OSAllocatedUnfairLock(initialState: generationBox.current())
    }

    func setActiveGeneration(_ generation: UInt64) {
        activeGenerationState.withLock { $0 = generation }
    }

    func invalidateActiveGeneration() {
        activeGenerationState.withLock { $0 = 0 }
    }

    private func currentGeneration() -> UInt64 {
        activeGenerationState.withLock { $0 }
    }

    func webRTC(_ bridge: any WebRTCBridge, didChangeConnectionState state: PeerConnectionState) {
        let generation = currentGeneration()
        Task {
            await runtime.handleConnectionStateChange(state, generation: generation)
        }
    }

    func webRTC(_ _: any WebRTCBridge, didGatherCandidate _: IceCandidatePayload) {}

    func webRTC(_ bridge: any WebRTCBridge, channel: DataChannelKind, didReceiveData data: Data) {
        let generation = currentGeneration()
        Task {
            await runtime.handleDataReceived(channel: channel, data: data, generation: generation)
        }
    }

    func webRTC(_ bridge: any WebRTCBridge, channel: DataChannelKind, didReceiveText text: String) {
        let generation = currentGeneration()
        Task {
            await runtime.handleTextReceived(channel: channel, text: text, generation: generation)
        }
    }

    func webRTC(_ bridge: any WebRTCBridge, channelDidOpen channel: DataChannelKind) {
        let generation = currentGeneration()
        Task {
            await runtime.handleChannelOpen(channel, generation: generation)
        }
    }

    func webRTC(_ bridge: any WebRTCBridge, didReceiveVideoTrack videoTrack: AnyObject) {
        streamLogger.info("WebRTC video track received")
        let token = makeRetainedTrackToken(videoTrack)
        let generation = currentGeneration()
        Task {
            await runtime.handleVideoTrack(token, generation: generation)
        }
    }

    func webRTC(_ bridge: any WebRTCBridge, didReceiveAudioTrack audioTrack: AnyObject) {
        streamLogger.info("WebRTC audio track received")
        let token = makeRetainedTrackToken(audioTrack)
        let generation = currentGeneration()
        Task {
            await runtime.handleAudioTrack(token, generation: generation)
        }
    }
}
