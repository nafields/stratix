// StreamSurfaceModel.swift
// Defines the stream surface model.
//

import Foundation
import Observation

@Observable
@MainActor
/// Holds the active video track plus renderer telemetry for the stream surface and diagnostics HUD.
final class StreamSurfaceModel {
    /// Immutable telemetry snapshot mirrored from the renderer and diagnostics pipeline.
    struct RendererTelemetrySnapshot: Equatable, Sendable {
        let framesReceived: Int?
        let framesDrawn: Int?
        let framesDroppedByCoalescing: Int?
        let drawQueueDepthMax: Int?
        let framesFailed: Int?
        let processingStatus: String?
        let processingInputWidth: Int?
        let processingInputHeight: Int?
        let processingOutputWidth: Int?
        let processingOutputHeight: Int?
        let renderLatencyMs: Double?
        let outputFamily: String?
        let eligibleRungs: [String]
        let deadRungs: [String]
        let lastError: String?

        /// Baseline snapshot used when the renderer has no live telemetry to publish.
        static let cleared = RendererTelemetrySnapshot(
            framesReceived: nil,
            framesDrawn: nil,
            framesDroppedByCoalescing: nil,
            drawQueueDepthMax: nil,
            framesFailed: nil,
            processingStatus: nil,
            processingInputWidth: nil,
            processingInputHeight: nil,
            processingOutputWidth: nil,
            processingOutputHeight: nil,
            renderLatencyMs: nil,
            outputFamily: nil,
            eligibleRungs: [],
            deadRungs: [],
            lastError: nil
        )
    }

    /// Mutable stream-surface diagnostics, including first-frame state and active renderer mode.
    struct DiagnosticsSnapshot: Equatable {
        var activeRendererMode = "sampleBuffer"
        var telemetry: RendererTelemetrySnapshot = .cleared
        var hasRenderedFirstFrame = false
    }

    /// The currently attached WebRTC video track, if one is active.
    private(set) var videoTrack: AnyObject?
    private(set) var diagnostics = DiagnosticsSnapshot()

    /// Returns the active renderer mode string used by diagnostics and UI overlays.
    var activeRendererMode: String { diagnostics.activeRendererMode }
    var framesReceived: Int? { diagnostics.telemetry.framesReceived }
    var framesDrawn: Int? { diagnostics.telemetry.framesDrawn }
    var framesDroppedByCoalescing: Int? { diagnostics.telemetry.framesDroppedByCoalescing }
    var drawQueueDepthMax: Int? { diagnostics.telemetry.drawQueueDepthMax }
    var framesFailed: Int? { diagnostics.telemetry.framesFailed }
    var processingStatus: String? { diagnostics.telemetry.processingStatus }
    var processingInputWidth: Int? { diagnostics.telemetry.processingInputWidth }
    var processingInputHeight: Int? { diagnostics.telemetry.processingInputHeight }
    var processingOutputWidth: Int? { diagnostics.telemetry.processingOutputWidth }
    var processingOutputHeight: Int? { diagnostics.telemetry.processingOutputHeight }
    var renderLatencyMs: Double? { diagnostics.telemetry.renderLatencyMs }
    var outputFamily: String? { diagnostics.telemetry.outputFamily }
    var eligibleRungs: [String] { diagnostics.telemetry.eligibleRungs }
    var deadRungs: [String] { diagnostics.telemetry.deadRungs }
    var lastError: String? { diagnostics.telemetry.lastError }
    var hasRenderedFirstFrame: Bool { diagnostics.hasRenderedFirstFrame }

    /// Updates the currently attached video track.
    func setVideoTrack(_ track: AnyObject?) {
        videoTrack = track
    }

    /// Updates the renderer mode when the runtime switches output paths.
    func updateRendererMode(_ mode: String) {
        guard diagnostics.activeRendererMode != mode else { return }
        diagnostics.activeRendererMode = mode
    }

    /// Replaces the current telemetry snapshot and marks the first frame when appropriate.
    func updateTelemetry(_ snapshot: RendererTelemetrySnapshot) {
        guard diagnostics.telemetry != snapshot || (!diagnostics.hasRenderedFirstFrame && (snapshot.framesDrawn ?? 0) > 0) else {
            return
        }
        diagnostics.telemetry = snapshot
        if snapshot.framesDrawn ?? 0 > 0 {
            diagnostics.hasRenderedFirstFrame = true
        }
    }

    /// Stores the latest decode failure details for overlay and diagnostics display.
    func reportDecodeFailure(_ details: String) {
        guard diagnostics.telemetry.lastError != details else { return }
        diagnostics.telemetry = RendererTelemetrySnapshot(
            framesReceived: diagnostics.telemetry.framesReceived,
            framesDrawn: diagnostics.telemetry.framesDrawn,
            framesDroppedByCoalescing: diagnostics.telemetry.framesDroppedByCoalescing,
            drawQueueDepthMax: diagnostics.telemetry.drawQueueDepthMax,
            framesFailed: diagnostics.telemetry.framesFailed,
            processingStatus: diagnostics.telemetry.processingStatus,
            processingInputWidth: diagnostics.telemetry.processingInputWidth,
            processingInputHeight: diagnostics.telemetry.processingInputHeight,
            processingOutputWidth: diagnostics.telemetry.processingOutputWidth,
            processingOutputHeight: diagnostics.telemetry.processingOutputHeight,
            renderLatencyMs: diagnostics.telemetry.renderLatencyMs,
            outputFamily: diagnostics.telemetry.outputFamily,
            eligibleRungs: diagnostics.telemetry.eligibleRungs,
            deadRungs: diagnostics.telemetry.deadRungs,
            lastError: details
        )
    }

    /// Marks that the stream surface has rendered at least one frame.
    func markRenderedFirstFrame() {
        guard !diagnostics.hasRenderedFirstFrame else { return }
        diagnostics.hasRenderedFirstFrame = true
    }

    /// Clears all surface state when the stream session is torn down.
    func reset() {
        guard videoTrack != nil || diagnostics != DiagnosticsSnapshot() else { return }
        videoTrack = nil
        diagnostics = DiagnosticsSnapshot()
    }
}
