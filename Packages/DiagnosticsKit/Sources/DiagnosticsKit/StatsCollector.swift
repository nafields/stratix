// StatsCollector.swift
// Defines stats collector.
//

import Foundation
import os
import StratixModels

// MARK: - Stats Collector
//
// Accumulates streaming performance metrics for the debug overlay.
// In production, this is fed by RTCStatisticsReport from the WebRTC framework.

public final class StatsCollector: Sendable {

    private let pipeline: StreamMetricsPipeline
    private let snapshotState = OSAllocatedUnfairLock(initialState: StreamingStatsSnapshot())

    public init(pipeline: StreamMetricsPipeline = .shared) {
        self.pipeline = pipeline
    }

    /// Update the latest stats snapshot.
    public func update(
        bitrateKbps: Int?,
        framesPerSecond: Double?,
        roundTripTimeMs: Double?,
        jitterMs: Double?,
        decodeTimeMs: Double?,
        packetsLost: Int?,
        framesLost: Int?,
        audioJitterMs: Double? = nil,
        audioPacketsLost: Int? = nil,
        audioBitrateKbps: Int? = nil,
        audioJitterBufferDelayMs: Double? = nil,
        audioConcealedSamples: Int? = nil,
        audioTotalSamplesReceived: Int? = nil,
        activeRegion: String?,
        negotiatedWidth: Int? = nil,
        negotiatedHeight: Int? = nil,
        controlPreferredWidth: Int? = nil,
        controlPreferredHeight: Int? = nil,
        messagePreferredWidth: Int? = nil,
        messagePreferredHeight: Int? = nil,
        rendererMode: String? = nil,
        inputFlushHz: Double? = nil,
        inputFlushJitterMs: Double? = nil,
        rendererFramesReceived: Int? = nil,
        rendererFramesDrawn: Int? = nil,
        rendererFramesDroppedByCoalescing: Int? = nil,
        rendererDrawQueueDepthMax: Int? = nil,
        rendererFramesFailed: Int? = nil,
        rendererProcessingStatus: String? = nil,
        rendererProcessingInputWidth: Int? = nil,
        rendererProcessingInputHeight: Int? = nil,
        rendererProcessingOutputWidth: Int? = nil,
        rendererProcessingOutputHeight: Int? = nil,
        renderLatencyMs: Double? = nil,
        rendererOutputFamily: String? = nil,
        rendererEligibleRungs: [String] = [],
        rendererDeadRungs: [String] = [],
        rendererLastError: String? = nil
    ) {
        let nextSnapshot = StreamingStatsSnapshot(
            bitrateKbps: bitrateKbps,
            framesPerSecond: framesPerSecond,
            roundTripTimeMs: roundTripTimeMs,
            jitterMs: jitterMs,
            decodeTimeMs: decodeTimeMs,
            packetsLost: packetsLost,
            framesLost: framesLost,
            audioJitterMs: audioJitterMs,
            audioPacketsLost: audioPacketsLost,
            audioBitrateKbps: audioBitrateKbps,
            audioJitterBufferDelayMs: audioJitterBufferDelayMs,
            audioConcealedSamples: audioConcealedSamples,
            audioTotalSamplesReceived: audioTotalSamplesReceived,
            activeRegion: activeRegion,
            negotiatedWidth: negotiatedWidth,
            negotiatedHeight: negotiatedHeight,
            controlPreferredWidth: controlPreferredWidth,
            controlPreferredHeight: controlPreferredHeight,
            messagePreferredWidth: messagePreferredWidth,
            messagePreferredHeight: messagePreferredHeight,
            rendererMode: rendererMode,
            inputFlushHz: inputFlushHz,
            inputFlushJitterMs: inputFlushJitterMs,
            rendererFramesReceived: rendererFramesReceived,
            rendererFramesDrawn: rendererFramesDrawn,
            rendererFramesDroppedByCoalescing: rendererFramesDroppedByCoalescing,
            rendererDrawQueueDepthMax: rendererDrawQueueDepthMax,
            rendererFramesFailed: rendererFramesFailed,
            rendererProcessingStatus: rendererProcessingStatus,
            rendererProcessingInputWidth: rendererProcessingInputWidth,
            rendererProcessingInputHeight: rendererProcessingInputHeight,
            rendererProcessingOutputWidth: rendererProcessingOutputWidth,
            rendererProcessingOutputHeight: rendererProcessingOutputHeight,
            renderLatencyMs: renderLatencyMs,
            rendererOutputFamily: rendererOutputFamily,
            rendererEligibleRungs: rendererEligibleRungs,
            rendererDeadRungs: rendererDeadRungs,
            rendererLastError: rendererLastError
        )
        snapshotState.withLock { $0 = nextSnapshot }
        pipeline.recordStatsSnapshot(nextSnapshot)
    }

    /// Thread-safe read of the latest snapshot.
    public var snapshot: StreamingStatsSnapshot {
        snapshotState.withLock { $0 }
    }

    public var pipelineSnapshot: StreamMetricsPipelineSnapshot {
        pipeline.snapshot()
    }
}
