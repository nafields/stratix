//
//  SampleBufferDisplayRenderer.swift
//  Stratix
//
//  Standalone sample-buffer renderer extracted from StreamView so the rendering
//  boundary remains explicit without changing runtime behavior.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(AVFoundation)
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
#if canImport(VideoToolbox)
@preconcurrency import VideoToolbox
#endif
import StratixCore
import VideoRenderingKit
import UIKit

final class SampleBufferDisplayRenderer: NSObject, RTCVideoRenderer, @unchecked Sendable {
    weak var displayLayer: AVSampleBufferDisplayLayer?
    let pendingBufferLock = NSLock()
    let stateLock = NSLock()
    let rendererDebugID = String(UUID().uuidString.prefix(6))
    var pendingSampleBuffers: [CMSampleBuffer] = []
    var enqueueDrainScheduled = false
    var didLogUnsupportedBufferType = false
    var didLogCVPixelBufferPath = false
    var didLogIncomingCVPixelBufferDetails = false
    var didLogFirstEnqueue = false
    var didReportFirstDraw = false
    var frameIndex: Int64 = 0
    var consecutiveDisplayLayerFailures = 0
    var didReportDecodeFailure = false
    var framesReceived = 0
    var framesDrawn = 0
    var framesDroppedByCoalescing = 0
    var drawQueueDepthMax = 0
    var framesFailed = 0
    var processingStatus: String?
    var processingInputWidth: Int?
    var processingInputHeight: Int?
    var processingOutputWidth: Int?
    var processingOutputHeight: Int?
    var renderLatencyMs: Double?
    var lastError: String?
    var requestedRung: RenderLadderRung = .sampleBuffer
    var lastReadyRung: RenderLadderRung?
    var lastFailedRung: RenderLadderRung?
    var lastTelemetryEmitTime: TimeInterval = Date.timeIntervalSinceReferenceDate
    var displayTargetWidth: Int?
    var displayTargetHeight: Int?
    var latestFrameReceivedAt: TimeInterval?
    var previousLLFIPixelBuffer: CVPixelBuffer?
    var previousLLFIPresentationTimeStamp: CMTime?
    var pendingLLFIPixelBuffer: CVPixelBuffer?
    var pendingLLFIPresentationTimeStamp: CMTime?
    var lowLatencyProcessingInFlight = false
    var lowLatencyProcessingGeneration: UInt64 = 0
    var currentLowLatencyGeneration: UInt64 = 0
    var lowLatencyFallbackToPlainSampleBuffer = false
    var lowLatencyDisplayActivated = false
    var didLogFirstLLFIFrame = false
    var didLogLowLatencySessionReuse = false
    var didLogLowLatencySourceCopy = false
    var pendingLLSRPixelBuffer: CVPixelBuffer?
    var pendingLLSRPresentationTimeStamp: CMTime?
    var llsrProcessingInFlight = false
    var llsrProcessingGeneration: UInt64 = 0
    var currentLLSRGeneration: UInt64 = 0
    var llsrFallbackToPlainSampleBuffer = false
    var llsrDisplayActivated = false
    var didLogFirstLLSRFrame = false
    var didLogLLSRSessionReuse = false
    var didLogLLSRSourceCopy = false
#if canImport(VideoToolbox) && !targetEnvironment(simulator)
    @available(tvOS 26.0, *)
    var activeLowLatencyResources: LowLatencyFrameInterpolationResources?
    @available(tvOS 26.0, *)
    var activeLowLatencySuperResolutionResources: LowLatencySuperResolutionResources?
#endif
    var onDecodeFailure: ((String) -> Void)?
    var onSourceDimensionsChanged: ((Int, Int) -> Void)?
    var onCandidateReady: ((RenderLadderRung) -> Void)?
    var onCandidateFailed: ((RenderLadderRung, String) -> Void)?
    var onTelemetry: ((TelemetrySnapshot) -> Void)?
    var onFirstFrameDrawn: (() -> Void)?
    var hdrEnabled = true

    // MARK: - Telemetry

    /// Captures the renderer counters and last-known processing state exposed to diagnostics.
    struct TelemetrySnapshot: Equatable, Sendable {
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
        let lastError: String?
    }

    /// Emits renderer debug logs only when verbose diagnostics are enabled or forced.
    func streamLog(_ message: @autoclosure () -> String, force: Bool = false) {
        guard force || SettingsStore.snapshotDiagnostics().verboseLogs else { return }
        print(message())
    }

    /// Ignores RTC size callbacks because the display layer follows its host view size instead.
    func setSize(_ size: CGSize) {
        // AVSampleBufferDisplayLayer sizes with its host view.
    }

    /// Ingests the latest WebRTC frame and routes it through low-latency or plain sample-buffer display.
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        guard let cvPixelBuffer = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer else {
            if !didLogUnsupportedBufferType {
                didLogUnsupportedBufferType = true
                streamLog("[StreamView] SampleBuffer renderer unsupported buffer type: \(type(of: frame.buffer))")
            }
            return
        }
        if !didLogCVPixelBufferPath {
            didLogCVPixelBufferPath = true
            streamLog("[StreamView] SampleBuffer renderer using RTCCVPixelBuffer frames")
        }
        if !didLogIncomingCVPixelBufferDetails {
            didLogIncomingCVPixelBufferDetails = true
            let inputPixelFormat = pixelFormatDescription(CVPixelBufferGetPixelFormatType(cvPixelBuffer))
            let creationAttributes = (CVPixelBufferCopyCreationAttributes(cvPixelBuffer) as? [String: Any])
                .map(lowLatencyAttributeSummary) ?? "unavailable"
            let colorAttachments = pixelBufferColorAttachmentSummary(cvPixelBuffer)
            streamLog("[StreamView][SBR \(rendererDebugID)] first WebRTC CVPixelBuffer format=\(inputPixelFormat) attrs={\(creationAttributes)} attachments={\(colorAttachments)}", force: true)
        }

        onSourceDimensionsChanged?(CVPixelBufferGetWidth(cvPixelBuffer), CVPixelBufferGetHeight(cvPixelBuffer))
        let presentationTimeStamp = nextPresentationTimeStamp()
        stateLock.lock()
        framesReceived += 1
        latestFrameReceivedAt = Date.timeIntervalSinceReferenceDate
        stateLock.unlock()

        switch requestedRung {
        case .vtSuperResolution(let scaleFactor):
#if canImport(VideoToolbox) && !targetEnvironment(simulator)
            if #available(tvOS 26.0, *) {
                submitLowLatencySuperResolutionFrame(
                    cvPixelBuffer,
                    presentationTimeStamp: presentationTimeStamp,
                    scaleFactor: scaleFactor
                )
            }
#endif
        case .vtFrameInterpolation:
#if canImport(VideoToolbox) && !targetEnvironment(simulator)
            if #available(tvOS 26.0, *),
               shouldAttemptLowLatencyFrameInterpolation(for: cvPixelBuffer) {
                submitLowLatencyFrameInterpolationFrame(cvPixelBuffer, presentationTimeStamp: presentationTimeStamp)
            }
#endif
        default:
            break
        }

        let shouldDisplayPlainFrame: Bool
        stateLock.lock()
        shouldDisplayPlainFrame = !lowLatencyDisplayActivated && !llsrDisplayActivated
        stateLock.unlock()
        guard shouldDisplayPlainFrame else {
            emitTelemetryIfNeeded()
            return
        }

        guard let sampleBuffer = makeSampleBuffer(from: cvPixelBuffer, presentationTimeStamp: presentationTimeStamp) else { return }
        enqueueSampleBuffer(sampleBuffer)
        emitTelemetryIfNeeded()
    }

}
#endif
