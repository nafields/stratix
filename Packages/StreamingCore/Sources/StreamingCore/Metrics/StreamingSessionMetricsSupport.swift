// StreamingSessionMetricsSupport.swift
// Provides shared support for the Metrics surface.
//

import Foundation
import DiagnosticsKit
import StratixModels
import os

struct StreamingSessionStatsPollerState: Sendable {
    var pollingGeneration: UInt64 = 0
    var task: Task<Void, Never>?
}

final class StreamingSessionStatsPoller: Sendable {
    typealias Publisher = @Sendable @MainActor (StreamingStatsSnapshot) -> Void

    private let bridge: any WebRTCBridge
    private let state = OSAllocatedUnfairLock(initialState: StreamingSessionStatsPollerState())

    init(bridge: any WebRTCBridge) {
        self.bridge = bridge
    }

    func start(publish: @escaping Publisher) {
        let generation = state.withLock { currentState -> UInt64 in
            currentState.pollingGeneration &+= 1
            currentState.task?.cancel()
            currentState.task = nil
            return currentState.pollingGeneration
        }

        let task = Task { [bridge, self] in
            let initialSnapshot = await bridge.collectStats()
            guard !Task.isCancelled, isCurrent(generation) else { return }
            await publish(initialSnapshot)

            while !Task.isCancelled, isCurrent(generation) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, isCurrent(generation) else { break }
                let networkSnapshot = await bridge.collectStats()
                guard !Task.isCancelled, isCurrent(generation) else { break }
                await publish(networkSnapshot)
            }
        }

        let shouldStoreTask = state.withLock { currentState in
            guard currentState.pollingGeneration == generation else { return false }
            currentState.task = task
            return true
        }
        if !shouldStoreTask {
            task.cancel()
        }
    }

    func stop() {
        let activeTask = state.withLock { currentState -> Task<Void, Never>? in
            currentState.pollingGeneration &+= 1
            let task = currentState.task
            currentState.task = nil
            return task
        }
        activeTask?.cancel()
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        state.withLock { $0.pollingGeneration == generation }
    }
}

@MainActor
final class StreamingSessionMetricsSupport {
    let statsCollector = StatsCollector()
    private let statsPoller: StreamingSessionStatsPoller

    private(set) var diagnosticsPollingEnabled = false

    init(bridge: any WebRTCBridge) {
        self.statsPoller = StreamingSessionStatsPoller(bridge: bridge)
    }

    func setDiagnosticsPollingEnabled(_ enabled: Bool) -> Bool {
        guard diagnosticsPollingEnabled != enabled else { return false }
        diagnosticsPollingEnabled = enabled
        return true
    }

    func startStatsPolling(publish: @escaping StreamingSessionStatsPoller.Publisher) {
        statsPoller.start(publish: publish)
    }

    func stopStatsPolling() {
        statsPoller.stop()
    }
}

@MainActor
extension StreamingSession {
    public var statsCollector: StatsCollector { model.metricsSupport.statsCollector }

    public func setDiagnosticsPollingEnabled(_ enabled: Bool) {
        guard model.metricsSupport.setDiagnosticsPollingEnabled(enabled) else { return }
        if enabled {
            if lifecycle == .connected {
                startStatsPolling()
            }
        } else {
            stopStatsPolling()
        }
    }

    func startStatsPolling() {
        model.metricsSupport.startStatsPolling { [weak self] snapshot in
            guard let self else { return }
            guard self.model.metricsSupport.diagnosticsPollingEnabled, self.lifecycle == .connected else { return }
            self.publishStats(with: snapshot)
        }
    }

    func stopStatsPolling() {
        model.metricsSupport.stopStatsPolling()
    }

    private func publishStats(with base: StreamingStatsSnapshot) {
        let runtimeSnapshot = model.runtimeSnapshot
        let merged = StreamingStatsSnapshot(
            timestamp: base.timestamp,
            bitrateKbps: base.bitrateKbps,
            framesPerSecond: base.framesPerSecond,
            roundTripTimeMs: base.roundTripTimeMs,
            jitterMs: base.jitterMs,
            decodeTimeMs: base.decodeTimeMs,
            packetsLost: base.packetsLost,
            framesLost: base.framesLost,
            audioJitterMs: base.audioJitterMs,
            audioPacketsLost: base.audioPacketsLost,
            audioBitrateKbps: base.audioBitrateKbps,
            audioJitterBufferDelayMs: base.audioJitterBufferDelayMs,
            audioConcealedSamples: base.audioConcealedSamples,
            audioTotalSamplesReceived: base.audioTotalSamplesReceived,
            activeRegion: base.activeRegion,
            negotiatedWidth: runtimeSnapshot.negotiatedDimensions?.width,
            negotiatedHeight: runtimeSnapshot.negotiatedDimensions?.height,
            controlPreferredWidth: runtimeSnapshot.controlPreferredDimensions.width,
            controlPreferredHeight: runtimeSnapshot.controlPreferredDimensions.height,
            messagePreferredWidth: runtimeSnapshot.messagePreferredDimensions.width,
            messagePreferredHeight: runtimeSnapshot.messagePreferredDimensions.height,
            inputFlushHz: runtimeSnapshot.inputFlushHz,
            inputFlushJitterMs: runtimeSnapshot.inputFlushJitterMs
        )
        model.metricsSupport.statsCollector.update(
            bitrateKbps: merged.bitrateKbps,
            framesPerSecond: merged.framesPerSecond,
            roundTripTimeMs: merged.roundTripTimeMs,
            jitterMs: merged.jitterMs,
            decodeTimeMs: merged.decodeTimeMs,
            packetsLost: merged.packetsLost,
            framesLost: merged.framesLost,
            audioJitterMs: merged.audioJitterMs,
            audioPacketsLost: merged.audioPacketsLost,
            audioBitrateKbps: merged.audioBitrateKbps,
            audioJitterBufferDelayMs: merged.audioJitterBufferDelayMs,
            audioConcealedSamples: merged.audioConcealedSamples,
            audioTotalSamplesReceived: merged.audioTotalSamplesReceived,
            activeRegion: merged.activeRegion,
            negotiatedWidth: merged.negotiatedWidth,
            negotiatedHeight: merged.negotiatedHeight,
            controlPreferredWidth: merged.controlPreferredWidth,
            controlPreferredHeight: merged.controlPreferredHeight,
            messagePreferredWidth: merged.messagePreferredWidth,
            messagePreferredHeight: merged.messagePreferredHeight,
            rendererMode: model.rendererTelemetry.mode,
            inputFlushHz: merged.inputFlushHz,
            inputFlushJitterMs: merged.inputFlushJitterMs,
            rendererFramesReceived: model.rendererTelemetry.framesReceived,
            rendererFramesDrawn: model.rendererTelemetry.framesDrawn,
            rendererFramesDroppedByCoalescing: model.rendererTelemetry.framesDroppedByCoalescing,
            rendererDrawQueueDepthMax: model.rendererTelemetry.drawQueueDepthMax,
            rendererFramesFailed: model.rendererTelemetry.framesFailed,
            rendererProcessingStatus: model.rendererTelemetry.processingStatus,
            rendererProcessingInputWidth: model.rendererTelemetry.processingInputWidth,
            rendererProcessingInputHeight: model.rendererTelemetry.processingInputHeight,
            rendererProcessingOutputWidth: model.rendererTelemetry.processingOutputWidth,
            rendererProcessingOutputHeight: model.rendererTelemetry.processingOutputHeight,
            renderLatencyMs: model.rendererTelemetry.renderLatencyMs,
            rendererOutputFamily: model.rendererTelemetry.outputFamily,
            rendererEligibleRungs: model.rendererTelemetry.eligibleRungs,
            rendererDeadRungs: model.rendererTelemetry.deadRungs,
            rendererLastError: model.rendererTelemetry.lastError
        )
        guard merged != stats else { return }
        stats = merged
    }

    func republishCurrentStats() {
        publishStats(with: stats)
    }
}
