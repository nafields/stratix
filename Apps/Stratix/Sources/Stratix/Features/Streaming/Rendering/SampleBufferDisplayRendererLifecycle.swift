// SampleBufferDisplayRendererLifecycle.swift
// Defines sample buffer display renderer lifecycle for the Features / Streaming surface.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(AVFoundation)
import Foundation
@preconcurrency import AVFoundation
#if canImport(VideoToolbox)
@preconcurrency import VideoToolbox
#endif
import StratixCore
import VideoRenderingKit
import UIKit

extension SampleBufferDisplayRenderer {
    func setRequestedRung(_ rung: RenderLadderRung) {
        stateLock.lock()
        let changed = requestedRung != rung
        requestedRung = rung
        if changed {
            lastReadyRung = nil
            lastFailedRung = nil
            lastError = nil
        }
        stateLock.unlock()
        guard changed else { return }

        resetLowLatencyFrameInterpolationState()
        resetLowLatencySuperResolutionState()
        if rung == .sampleBuffer {
            updateLowLatencyStatus(
                nil,
                inputWidth: processingInputWidth,
                inputHeight: processingInputHeight,
                outputWidth: processingOutputWidth,
                outputHeight: processingOutputHeight,
                lastError: nil
            )
        }
    }

    @MainActor
    func bind(to displayView: SampleBufferDisplayView) {
        let displayLayer = displayView.displayLayer
        self.displayLayer = displayLayer
        Task { @MainActor [weak self] in
            guard let self, let displayLayer = self.displayLayer else { return }
            displayLayer.videoGravity = .resizeAspect
            await displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
            let displayTarget = displayView.displayTargetDimensions
            self.updateDisplayTargetDimensions(width: displayTarget.width, height: displayTarget.height)
            self.consecutiveDisplayLayerFailures = 0
            self.didReportDecodeFailure = false
            streamLog("[StreamView][SBR \(self.rendererDebugID)] SampleBufferDisplayLayer fallback bound", force: true)
            self.emitTelemetryIfNeeded(force: true)
        }
    }

    @MainActor
    func updateDisplayTarget(from displayView: SampleBufferDisplayView) {
        let displayTarget = displayView.displayTargetDimensions
        updateDisplayTargetDimensions(width: displayTarget.width, height: displayTarget.height)
    }

    func currentDisplayLayerDimensions() -> (width: Int, height: Int)? {
        guard let displayLayer else { return nil }
        let scale = max(displayLayer.contentsScale, 1)
        let width = Int((displayLayer.bounds.width * scale).rounded())
        let height = Int((displayLayer.bounds.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    func flushDisplayLayer(removingDisplayedImage: Bool) {
        Task { @MainActor [weak self] in
            if let displayLayer = self?.displayLayer {
                await displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: removingDisplayedImage)
            }
        }
    }

    func clearPendingPlainSampleBuffers() {
        pendingBufferLock.lock()
        pendingSampleBuffers.removeAll()
        pendingBufferLock.unlock()
    }

    func reset() {
        stateLock.lock()
        frameIndex = 0
        consecutiveDisplayLayerFailures = 0
        didReportDecodeFailure = false
        didReportFirstDraw = false
        framesReceived = 0
        framesDrawn = 0
        framesDroppedByCoalescing = 0
        drawQueueDepthMax = 0
        framesFailed = 0
        processingStatus = nil
        processingInputWidth = nil
        processingInputHeight = nil
        processingOutputWidth = nil
        processingOutputHeight = nil
        lastError = nil
        displayTargetWidth = nil
        displayTargetHeight = nil
        renderLatencyMs = nil
        latestFrameReceivedAt = nil
        lastReadyRung = nil
        lastFailedRung = nil
        didLogIncomingCVPixelBufferDetails = false
#if canImport(VideoToolbox) && !targetEnvironment(simulator)
        if #available(tvOS 26.0, *), let activeLowLatencyResources {
            _ = activeLowLatencyResources
            self.activeLowLatencyResources = nil
        }
        if #available(tvOS 26.0, *), let activeLowLatencySuperResolutionResources {
            _ = activeLowLatencySuperResolutionResources
            self.activeLowLatencySuperResolutionResources = nil
        }
#endif
        stateLock.unlock()
        resetLowLatencyFrameInterpolationState()
        resetLowLatencySuperResolutionState()
        pendingBufferLock.lock()
        pendingSampleBuffers.removeAll()
        enqueueDrainScheduled = false
        pendingBufferLock.unlock()
        streamLog("[StreamView][SBR \(rendererDebugID)] reset", force: true)
        Task { @MainActor [weak self] in
            if let displayLayer = self?.displayLayer {
                await displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
            }
        }
    }
}
#endif
