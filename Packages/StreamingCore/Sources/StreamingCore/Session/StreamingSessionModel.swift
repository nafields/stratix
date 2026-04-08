// StreamingSessionModel.swift
// Defines the streaming session model.
//

import Foundation
import StratixModels
import InputBridge
import XCloudAPI

@MainActor
final class StreamingSessionModel {
    let inputQueue = InputQueue()
    let metricsSupport: StreamingSessionMetricsSupport
    let streamingConfig: StreamingConfig
    let runtimeGenerationBox: StreamingRuntimeGenerationBox
    let runtime: StreamingRuntime
    let bridgeDelegate: StreamingSessionBridgeDelegate

    var runtimeSnapshot: StreamingRuntimeSnapshot
    var latestVideoTrack: AnyObject?
    var latestAudioTrack: AnyObject?
    var videoTrackReplayCount = 0
    var rendererTelemetry = StreamingSessionRendererTelemetry()

    init(
        apiClient: XCloudAPIClient,
        bridge: any WebRTCBridge,
        config: StreamingConfig,
        preferences: StreamPreferences,
        delegateBox: StreamingRuntimeDelegateBox
    ) {
        self.metricsSupport = StreamingSessionMetricsSupport(bridge: bridge)
        self.streamingConfig = config
        self.runtimeGenerationBox = StreamingRuntimeGenerationBox()
        self.runtimeSnapshot = Self.makeRuntimeSnapshot(config: config)
        self.runtime = StreamingRuntime(
            apiClient: apiClient,
            bridge: bridge,
            inputQueue: inputQueue,
            config: config,
            preferences: preferences,
            delegateBox: delegateBox,
            generationBox: runtimeGenerationBox
        )

        self.bridgeDelegate = StreamingSessionBridgeDelegate(
            runtime: runtime,
            generationBox: runtimeGenerationBox
        )
        bridge.delegate = bridgeDelegate
    }

    func resetForStreamStart() {
        runtimeSnapshot = Self.makeRuntimeSnapshot(config: streamingConfig)
        latestVideoTrack = nil
        latestAudioTrack = nil
        videoTrackReplayCount = 0
        rendererTelemetry = StreamingSessionRendererTelemetry()
    }

    func resetForStreamStop() {
        runtimeSnapshot.negotiatedDimensions = nil
        runtimeSnapshot.inputFlushHz = nil
        runtimeSnapshot.inputFlushJitterMs = nil
        rendererTelemetry.resetForStreamStop()
    }

    private static func makeRuntimeSnapshot(config: StreamingConfig) -> StreamingRuntimeSnapshot {
        StreamingRuntimeSnapshot(
            negotiatedDimensions: nil,
            controlPreferredDimensions: StreamDimensions(
                width: Int(config.videoDimensionsHint.width),
                height: Int(config.videoDimensionsHint.height)
            ),
            messagePreferredDimensions: config.messageChannelDimensions,
            inputFlushHz: nil,
            inputFlushJitterMs: nil
        )
    }
}
