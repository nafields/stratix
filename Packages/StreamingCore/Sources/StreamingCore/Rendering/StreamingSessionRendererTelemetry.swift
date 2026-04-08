// StreamingSessionRendererTelemetry.swift
// Defines streaming session renderer telemetry.
//

import Foundation
import StratixModels

struct StreamingSessionRendererTelemetry: Sendable, Equatable {
    var mode = "sampleBuffer"
    var framesReceived: Int?
    var framesDrawn: Int?
    var framesDroppedByCoalescing: Int?
    var drawQueueDepthMax: Int?
    var framesFailed: Int?
    var processingStatus: String?
    var processingInputWidth: Int?
    var processingInputHeight: Int?
    var processingOutputWidth: Int?
    var processingOutputHeight: Int?
    var renderLatencyMs: Double?
    var outputFamily: String?
    var eligibleRungs: [String] = []
    var deadRungs: [String] = []
    var lastError: String?

    mutating func resetForStreamStop() {
        framesReceived = nil
        framesDrawn = nil
        framesDroppedByCoalescing = nil
        drawQueueDepthMax = nil
        framesFailed = nil
        processingStatus = nil
        processingInputWidth = nil
        processingInputHeight = nil
        processingOutputWidth = nil
        processingOutputHeight = nil
        renderLatencyMs = nil
        outputFamily = nil
        eligibleRungs = []
        deadRungs = []
        lastError = nil
    }

    mutating func setMode(_ mode: String) -> Bool {
        guard self.mode != mode else { return false }
        self.mode = mode
        return true
    }

    mutating func update(
        framesReceived: Int?,
        framesDrawn: Int?,
        framesDroppedByCoalescing: Int?,
        drawQueueDepthMax: Int?,
        framesFailed: Int?,
        processingStatus: String?,
        processingInputWidth: Int?,
        processingInputHeight: Int?,
        processingOutputWidth: Int?,
        processingOutputHeight: Int?,
        renderLatencyMs: Double?,
        outputFamily: String?,
        eligibleRungs: [String],
        deadRungs: [String],
        lastError: String?
    ) -> Bool {
        guard self.framesReceived != framesReceived ||
                self.framesDrawn != framesDrawn ||
                self.framesDroppedByCoalescing != framesDroppedByCoalescing ||
                self.drawQueueDepthMax != drawQueueDepthMax ||
                self.framesFailed != framesFailed ||
                self.processingStatus != processingStatus ||
                self.processingInputWidth != processingInputWidth ||
                self.processingInputHeight != processingInputHeight ||
                self.processingOutputWidth != processingOutputWidth ||
                self.processingOutputHeight != processingOutputHeight ||
                self.renderLatencyMs != renderLatencyMs ||
                self.outputFamily != outputFamily ||
                self.eligibleRungs != eligibleRungs ||
                self.deadRungs != deadRungs ||
                self.lastError != lastError else { return false }

        self.framesReceived = framesReceived
        self.framesDrawn = framesDrawn
        self.framesDroppedByCoalescing = framesDroppedByCoalescing
        self.drawQueueDepthMax = drawQueueDepthMax
        self.framesFailed = framesFailed
        self.processingStatus = processingStatus
        self.processingInputWidth = processingInputWidth
        self.processingInputHeight = processingInputHeight
        self.processingOutputWidth = processingOutputWidth
        self.processingOutputHeight = processingOutputHeight
        self.renderLatencyMs = renderLatencyMs
        self.outputFamily = outputFamily
        self.eligibleRungs = eligibleRungs
        self.deadRungs = deadRungs
        self.lastError = lastError
        return true
    }
}

@MainActor
extension StreamingSession {
    public func setRendererMode(_ mode: RendererModePreference) {
        setRendererMode(mode.rawValue)
    }

    public func setRendererMode(_ mode: String) {
        guard model.rendererTelemetry.setMode(mode) else { return }
        republishCurrentStats()
    }

    public func setRendererTelemetry(
        framesReceived: Int?,
        framesDrawn: Int?,
        framesDroppedByCoalescing: Int?,
        drawQueueDepthMax: Int?,
        framesFailed: Int?,
        processingStatus: String?,
        processingInputWidth: Int?,
        processingInputHeight: Int?,
        processingOutputWidth: Int?,
        processingOutputHeight: Int?,
        renderLatencyMs: Double? = nil,
        outputFamily: String? = nil,
        eligibleRungs: [String] = [],
        deadRungs: [String] = [],
        lastError: String?
    ) {
        guard model.rendererTelemetry.update(
            framesReceived: framesReceived,
            framesDrawn: framesDrawn,
            framesDroppedByCoalescing: framesDroppedByCoalescing,
            drawQueueDepthMax: drawQueueDepthMax,
            framesFailed: framesFailed,
            processingStatus: processingStatus,
            processingInputWidth: processingInputWidth,
            processingInputHeight: processingInputHeight,
            processingOutputWidth: processingOutputWidth,
            processingOutputHeight: processingOutputHeight,
            renderLatencyMs: renderLatencyMs,
            outputFamily: outputFamily,
            eligibleRungs: eligibleRungs,
            deadRungs: deadRungs,
            lastError: lastError
        ) else { return }
        republishCurrentStats()
    }

    public func reportRendererDecodeFailure(_ details: String) {
        streamLogger.error("Renderer decode failure reported: \(details, privacy: .public)")
        switch lifecycle {
        case .failed, .disconnecting, .disconnected:
            return
        default:
            lifecycle = .failed(StreamError(code: .webrtc, message: "Decode failed: \(details)"))
        }
    }
}
