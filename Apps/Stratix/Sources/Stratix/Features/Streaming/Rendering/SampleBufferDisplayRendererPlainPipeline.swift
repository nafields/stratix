// SampleBufferDisplayRendererPlainPipeline.swift
// Defines sample buffer display renderer plain pipeline for the Features / Streaming surface.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(AVFoundation)
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import StratixCore
import VideoRenderingKit

extension SampleBufferDisplayRenderer {
    func enqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        pendingBufferLock.lock()
        pendingSampleBuffers.append(sampleBuffer)
        let pendingDepth = pendingSampleBuffers.count
        let shouldScheduleDrain = !enqueueDrainScheduled
        if shouldScheduleDrain {
            enqueueDrainScheduled = true
        }
        pendingBufferLock.unlock()
        stateLock.lock()
        drawQueueDepthMax = max(drawQueueDepthMax, pendingDepth)
        stateLock.unlock()

        guard shouldScheduleDrain else { return }
        Task { @MainActor [weak self] in
            self?.drainPendingSampleBuffersOnMain()
        }
    }

    @MainActor
    func drainPendingSampleBuffersOnMain() {
        while true {
            pendingBufferLock.lock()
            if pendingSampleBuffers.isEmpty {
                enqueueDrainScheduled = false
                pendingBufferLock.unlock()
                return
            }
            let nextBuffer = pendingSampleBuffers.removeFirst()
            pendingBufferLock.unlock()

            guard let displayLayer else { continue }
            let renderer = displayLayer.sampleBufferRenderer
            if renderer.status == .failed {
                let message = renderer.error?.localizedDescription ?? "unknown"
                streamLog("[StreamView] SampleBuffer display layer failed; flushing: \(message)", force: true)
                consecutiveDisplayLayerFailures += 1
                if consecutiveDisplayLayerFailures >= 3, !didReportDecodeFailure {
                    didReportDecodeFailure = true
                    onDecodeFailure?("AVSampleBufferDisplayLayer failed repeatedly: \(message)")
                }
                renderer.flush(removingDisplayedImage: true, completionHandler: nil)
            } else {
                consecutiveDisplayLayerFailures = 0
            }
            renderer.enqueue(nextBuffer)
            let shouldReportFirstDraw: Bool
            stateLock.lock()
            framesDrawn += 1
            shouldReportFirstDraw = !didReportFirstDraw
            if shouldReportFirstDraw {
                didReportFirstDraw = true
            }
            if let latestFrameReceivedAt {
                renderLatencyMs = (Date.timeIntervalSinceReferenceDate - latestFrameReceivedAt) * 1_000
            }
            stateLock.unlock()
            if shouldReportFirstDraw {
                onFirstFrameDrawn?()
            }
            if !didLogFirstEnqueue {
                didLogFirstEnqueue = true
                streamLog("[StreamView] SampleBufferDisplayLayer first enqueue")
            }
            emitTelemetryIfNeeded()
        }
    }

    func makeSampleBuffer(from pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) -> CMSampleBuffer? {
        applyPreferredColorAttachments(to: pixelBuffer)

        var formatDescription: CMFormatDescription?
        let descStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard descStatus == noErr, let formatDescription else {
            streamLog("[StreamView] SampleBuffer format description failed: \(descStatus)", force: true)
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            streamLog("[StreamView] SampleBuffer creation failed: \(sampleStatus)", force: true)
            return nil
        }

        if #available(tvOS 26.0, *) {
            pixelBuffer.propagateAttachments(to: sampleBuffer)
        }

        CMSetAttachment(
            sampleBuffer,
            key: kCMSampleAttachmentKey_DisplayImmediately,
            value: kCFBooleanTrue,
            attachmentMode: kCMAttachmentMode_ShouldNotPropagate
        )
        return sampleBuffer
    }

    func applyPreferredColorAttachments(to pixelBuffer: CVPixelBuffer) {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let is10bit = pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            || pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        let is8BitBiPlanar = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

        if hdrEnabled && is10bit {
            CVBufferSetAttachment(pixelBuffer,
                                  kCVImageBufferColorPrimariesKey,
                                  kCVImageBufferColorPrimaries_ITU_R_2020,
                                  .shouldPropagate)
            CVBufferSetAttachment(pixelBuffer,
                                  kCVImageBufferTransferFunctionKey,
                                  kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
                                  .shouldPropagate)
            CVBufferSetAttachment(pixelBuffer,
                                  kCVImageBufferYCbCrMatrixKey,
                                  kCVImageBufferYCbCrMatrix_ITU_R_2020,
                                  .shouldPropagate)
            return
        }

        guard is8BitBiPlanar else { return }
        CVBufferSetAttachment(pixelBuffer,
                              kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2,
                              .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer,
                              kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_ITU_R_709_2,
                              .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer,
                              kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                              .shouldPropagate)
    }

    func nextPresentationTimeStamp() -> CMTime {
        stateLock.lock()
        defer { stateLock.unlock() }
        let presentationTimeStamp = CMTime(value: frameIndex, timescale: 60)
        frameIndex += 1
        return presentationTimeStamp
    }

    func copyDisplayAttachments(from sourceBuffer: CVImageBuffer, to destinationBuffer: CVImageBuffer) {
        if let propagatingAttachments = CVBufferCopyAttachments(sourceBuffer, .shouldPropagate) {
            CVBufferSetAttachments(destinationBuffer, propagatingAttachments, .shouldPropagate)
        }
        if let nonPropagatingAttachments = CVBufferCopyAttachments(sourceBuffer, .shouldNotPropagate) {
            CVBufferSetAttachments(destinationBuffer, nonPropagatingAttachments, .shouldNotPropagate)
        }
    }

    func pixelFormatDescription(_ pixelFormat: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((pixelFormat >> 24) & 0xff),
            UInt8((pixelFormat >> 16) & 0xff),
            UInt8((pixelFormat >> 8) & 0xff),
            UInt8(pixelFormat & 0xff)
        ]
        let ascii = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)) ?? ""
        if ascii.isEmpty {
            return "\(pixelFormat)"
        }
        return "\(ascii) (\(pixelFormat))"
    }

    func pixelBufferColorAttachmentSummary(_ pixelBuffer: CVPixelBuffer) -> String {
        let keys: [(CFString, String)] = [
            (kCVImageBufferColorPrimariesKey, "primaries"),
            (kCVImageBufferTransferFunctionKey, "transfer"),
            (kCVImageBufferYCbCrMatrixKey, "matrix")
        ]
        let parts = keys.compactMap { key, label -> String? in
            guard let value = CVBufferCopyAttachment(pixelBuffer, key, nil) else { return nil }
            return "\(label)=\(value)"
        }
        return parts.isEmpty ? "none" : parts.joined(separator: " ")
    }

    func lowLatencyAttributeSummary(_ attributes: [String: Any]) -> String {
        let pixelFormatKey = kCVPixelBufferPixelFormatTypeKey as String
        let iosurfaceKey = kCVPixelBufferIOSurfacePropertiesKey as String
        let interestingKeys = [
            pixelFormatKey,
            kCVPixelBufferWidthKey as String,
            kCVPixelBufferHeightKey as String,
            iosurfaceKey,
            kCVPixelBufferMetalCompatibilityKey as String,
            kCVPixelBufferOpenGLCompatibilityKey as String,
            kCVPixelBufferOpenGLESCompatibilityKey as String,
            kCVPixelBufferExtendedPixelsLeftKey as String,
            kCVPixelBufferExtendedPixelsTopKey as String,
            kCVPixelBufferExtendedPixelsRightKey as String,
            kCVPixelBufferExtendedPixelsBottomKey as String
        ]

        var parts: [String] = []
        for key in interestingKeys {
            guard let value = attributes[key] else { continue }
            switch key {
            case pixelFormatKey:
                if let number = value as? NSNumber {
                    parts.append("pixelFormat=\(pixelFormatDescription(OSType(truncating: number)))")
                } else {
                    parts.append("pixelFormat=\(value)")
                }
            case iosurfaceKey:
                if let dictionary = value as? [String: Any] {
                    parts.append("iosurfaceKeys=[\(dictionary.keys.sorted().joined(separator: ","))]")
                } else {
                    parts.append("iosurface=\(value)")
                }
            default:
                parts.append("\(key)=\(value)")
            }
        }

        let remainingKeys = attributes.keys
            .filter { !interestingKeys.contains($0) }
            .sorted()
        if !remainingKeys.isEmpty {
            parts.append("otherKeys=[\(remainingKeys.joined(separator: ","))]")
        }
        return parts.joined(separator: " ")
    }

    func pixelPlaneSummary(_ pixelBuffer: CVPixelBuffer) -> String {
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        guard planeCount >= 2 else {
            return "planes=\(planeCount)"
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return "planes=\(planeCount) baseAddress=nil"
        }

        let yWidth = max(1, CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        let yHeight = max(1, CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvWidth = max(1, CVPixelBufferGetWidthOfPlane(pixelBuffer, 1))
        let uvHeight = max(1, CVPixelBufferGetHeightOfPlane(pixelBuffer, 1))
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        let yBytes = yBaseAddress.assumingMemoryBound(to: UInt8.self)
        let uvBytes = uvBaseAddress.assumingMemoryBound(to: UInt8.self)

        let sampleCols = 16
        let sampleRows = 9

        var yValues: [Int] = []
        yValues.reserveCapacity(sampleCols * sampleRows)
        for row in 0..<sampleRows {
            let y = min(yHeight - 1, (row * yHeight) / sampleRows)
            for col in 0..<sampleCols {
                let x = min(yWidth - 1, (col * yWidth) / sampleCols)
                yValues.append(Int(yBytes[(y * yStride) + x]))
            }
        }

        var cbTotal = 0
        var crTotal = 0
        var uvSamples = 0
        for row in 0..<sampleRows {
            let y = min(uvHeight - 1, (row * uvHeight) / sampleRows)
            for col in 0..<sampleCols {
                let x = min(uvWidth - 1, (col * uvWidth) / sampleCols)
                let uvIndex = (y * uvStride) + (x * 2)
                cbTotal += Int(uvBytes[uvIndex])
                crTotal += Int(uvBytes[uvIndex + 1])
                uvSamples += 1
            }
        }

        let yMin = yValues.min() ?? 0
        let yMax = yValues.max() ?? 0
        let yAvg = yValues.isEmpty ? 0 : (yValues.reduce(0, +) / yValues.count)
        let cbAvg = uvSamples == 0 ? 0 : (cbTotal / uvSamples)
        let crAvg = uvSamples == 0 ? 0 : (crTotal / uvSamples)
        return "Y(avg=\(yAvg) min=\(yMin) max=\(yMax)) UV(avgCb=\(cbAvg) avgCr=\(crAvg))"
    }

    private var telemetrySnapshot: TelemetrySnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return TelemetrySnapshot(
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
            lastError: lastError
        )
    }

    func emitTelemetryIfNeeded(force: Bool = false) {
        let now = Date.timeIntervalSinceReferenceDate
        guard force || now - lastTelemetryEmitTime >= 1 else { return }
        lastTelemetryEmitTime = now
        onTelemetry?(telemetrySnapshot)
    }

    func reportCandidateReadyIfNeeded(_ rung: RenderLadderRung) {
        guard lastReadyRung != rung else { return }
        lastReadyRung = rung
        lastFailedRung = nil
        onCandidateReady?(rung)
    }

    func reportCandidateFailureIfNeeded(_ rung: RenderLadderRung, reason: String) {
        guard lastFailedRung != rung else { return }
        lastFailedRung = rung
        lastError = reason
        onCandidateFailed?(rung, reason)
    }
}
#endif
