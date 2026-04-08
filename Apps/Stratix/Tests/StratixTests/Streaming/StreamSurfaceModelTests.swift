// StreamSurfaceModelTests.swift
// Exercises stream surface model behavior.
//

import Foundation
import Testing
@testable import Stratix

@MainActor
@Suite
struct StreamSurfaceModelTests {
    private func recordTelemetryAttachment(
        mode: String,
        snapshot: StreamSurfaceModel.RendererTelemetrySnapshot
    ) {
        let lines: [String] = [
            "mode=\(mode)",
            "framesReceived=\(snapshot.framesReceived?.description ?? "nil")",
            "framesDrawn=\(snapshot.framesDrawn?.description ?? "nil")",
            "framesDroppedByCoalescing=\(snapshot.framesDroppedByCoalescing?.description ?? "nil")",
            "drawQueueDepthMax=\(snapshot.drawQueueDepthMax?.description ?? "nil")",
            "framesFailed=\(snapshot.framesFailed?.description ?? "nil")",
            "processingStatus=\(snapshot.processingStatus ?? "nil")",
            "processingInput=\(snapshot.processingInputWidth?.description ?? "nil")x\(snapshot.processingInputHeight?.description ?? "nil")",
            "processingOutput=\(snapshot.processingOutputWidth?.description ?? "nil")x\(snapshot.processingOutputHeight?.description ?? "nil")",
            "renderLatencyMs=\(snapshot.renderLatencyMs?.description ?? "nil")",
            "outputFamily=\(snapshot.outputFamily ?? "nil")",
            "eligibleRungs=\(snapshot.eligibleRungs.joined(separator: ","))",
            "deadRungs=\(snapshot.deadRungs.joined(separator: ","))",
            "lastError=\(snapshot.lastError ?? "nil")"
        ]
        Attachment.record(
            lines.joined(separator: "\n"),
            named: "Renderer Telemetry Snapshot"
        )
    }

    @Test
    func telemetryUpdatesOwnRenderSurfaceState() {
        let model = StreamSurfaceModel()
        let snapshot = StreamSurfaceModel.RendererTelemetrySnapshot(
            framesReceived: 120,
            framesDrawn: 118,
            framesDroppedByCoalescing: 2,
            drawQueueDepthMax: 3,
            framesFailed: nil,
            processingStatus: "metal-ready",
            processingInputWidth: 1280,
            processingInputHeight: 720,
            processingOutputWidth: 1920,
            processingOutputHeight: 1080,
            renderLatencyMs: 6.4,
            outputFamily: "metal",
            eligibleRungs: ["sampleBuffer", "metalFXSpatial"],
            deadRungs: [],
            lastError: nil
        )

        model.updateRendererMode("metal")
        model.updateTelemetry(snapshot)
        recordTelemetryAttachment(mode: "metal", snapshot: snapshot)

        #expect(model.activeRendererMode == "metal")
        #expect(model.processingOutputWidth == 1920)
        #expect(model.framesDrawn == 118)
        #expect(model.hasRenderedFirstFrame == true)
    }

    @Test
    func resetClearsTrackAndDiagnostics() {
        let model = StreamSurfaceModel()
        let track = NSString(string: "track")

        model.setVideoTrack(track)
        model.reportDecodeFailure("decode failed")
        model.markRenderedFirstFrame()
        model.reset()

        #expect(model.videoTrack == nil)
        #expect(model.lastError == nil)
        #expect(model.hasRenderedFirstFrame == false)
        #expect(model.activeRendererMode == "sampleBuffer")
    }

    @Test
    func decodeFailurePreservesExistingTelemetryWhileUpdatingError() {
        let model = StreamSurfaceModel()
        model.updateRendererMode("metal")
        model.updateTelemetry(
            .init(
                framesReceived: 30,
                framesDrawn: 29,
                framesDroppedByCoalescing: 1,
                drawQueueDepthMax: 2,
                framesFailed: nil,
                processingStatus: "steady",
                processingInputWidth: 1280,
                processingInputHeight: 720,
                processingOutputWidth: 1920,
                processingOutputHeight: 1080,
                renderLatencyMs: 6.2,
                outputFamily: "metal",
                eligibleRungs: ["sampleBuffer", "metalFXSpatial"],
                deadRungs: [],
                lastError: nil
            )
        )

        model.reportDecodeFailure("decoder failed")

        #expect(model.activeRendererMode == "metal")
        #expect(model.framesDrawn == 29)
        #expect(model.lastError == "decoder failed")
    }
}
