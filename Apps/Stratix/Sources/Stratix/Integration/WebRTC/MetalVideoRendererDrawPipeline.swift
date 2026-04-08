// MetalVideoRendererDrawPipeline.swift
// Defines metal video renderer draw pipeline for the Integration / WebRTC surface.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(Metal)
import Foundation
import AVFoundation
import CoreVideo
import Metal
import MetalKit

extension MetalVideoRenderer {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Drawable size is explicitly driven by incoming frame dimensions in setSize(_:)
        // to avoid partial top-left blits when the view size exceeds stream resolution.
    }

    @MainActor
    func draw(in view: MTKView) {
        lock.lock()
        let pixelBuffer = latestPixelBuffer
        let frameArrivalTime = latestFrameArrivalTime
        lock.unlock()

        guard
            let pixelBuffer,
            let textureCache,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            finishDrawCycle(didDraw: false)
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        if outputSize.width != width || outputSize.height != height {
            setSize(CGSize(width: width, height: height))
        }
        guard let outputTexture else {
            finishDrawCycle(didDraw: false)
            return
        }

        var yRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .r8Unorm, width, height, 0, &yRef
        )

        var cbcrRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .rg8Unorm, width / 2, height / 2, 1, &cbcrRef
        )

        guard
            let yTexture = yRef.flatMap({ CVMetalTextureGetTexture($0) }),
            let cbcrTexture = cbcrRef.flatMap({ CVMetalTextureGetTexture($0) })
        else {
            commandBuffer.commit()
            finishDrawCycle(didDraw: false)
            return
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            finishDrawCycle(didDraw: false)
            return
        }
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(yTexture, index: 0)
        encoder.setTexture(cbcrTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)

        var isFullRange: UInt32 = CVPixelBufferGetPixelFormatType(pixelBuffer)
            == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ? 1 : 0
        encoder.setBytes(&isFullRange, length: MemoryLayout<UInt32>.size, index: 2)

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(
            width: (width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        let presentationTexture: MTLTexture
#if canImport(MetalFX)
        if let spatialScaler, let spatialScalerOutputTexture {
            spatialScaler.colorTexture = outputTexture
            spatialScaler.outputTexture = spatialScalerOutputTexture
            spatialScaler.encode(commandBuffer: commandBuffer)
            presentationTexture = spatialScalerOutputTexture
        } else {
            presentationTexture = outputTexture
        }
#else
        presentationTexture = outputTexture
#endif

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            let drawableTexture = drawable.texture
            let copyWidth = min(presentationTexture.width, drawableTexture.width)
            let copyHeight = min(presentationTexture.height, drawableTexture.height)
            blit.copy(
                from: presentationTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOriginMake(0, 0, 0),
                sourceSize: MTLSizeMake(copyWidth, copyHeight, 1),
                to: drawableTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOriginMake(0, 0, 0)
            )
            blit.endEncoding()
        }

        if let frameArrivalTime {
            commandBuffer.addCompletedHandler { [weak self] _ in
                self?.lock.lock()
                self?.renderLatencyMs = (Date.timeIntervalSinceReferenceDate - frameArrivalTime) * 1_000
                self?.lock.unlock()
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
        finishDrawCycle(didDraw: true)
    }

    // MARK: - Sizing

    @MainActor
    func desiredDrawableSize(sourceWidth: Int, sourceHeight: Int) -> CGSize {
        let sourceSize = CGSize(width: sourceWidth, height: sourceHeight)
        guard let screen = mtkView.window?.windowScene?.screen ?? mtkView.window?.screen else {
            return sourceSize
        }
        let nativeBounds = screen.nativeBounds
        guard nativeBounds.width > 0, nativeBounds.height > 0 else {
            return sourceSize
        }

        let fittedRect = AVMakeRect(
            aspectRatio: sourceSize,
            insideRect: CGRect(origin: .zero, size: nativeBounds.size)
        )
        let fittedSize = fittedRect.integral.size
        guard fittedSize.width >= sourceSize.width, fittedSize.height >= sourceSize.height else {
            return sourceSize
        }
        return fittedSize
    }

    private func finishDrawCycle(didDraw: Bool) {
        let shouldScheduleFollowUp: Bool
        let shouldReportFirstDraw: Bool
        lock.lock()
        if didDraw {
            framesDrawn += 1
            shouldReportFirstDraw = !didReportFirstDraw
            if shouldReportFirstDraw {
                didReportFirstDraw = true
            }
        } else {
            shouldReportFirstDraw = false
        }
        if frameArrivedWhileDrawing {
            frameArrivedWhileDrawing = false
            shouldScheduleFollowUp = true
        } else {
            drawScheduled = false
            shouldScheduleFollowUp = false
        }
        lock.unlock()

        if shouldReportFirstDraw {
            onFirstFrameDrawn?()
        }
        emitTelemetryIfNeeded()

        if shouldScheduleFollowUp {
            scheduleMainThreadDraw()
        }
    }

    private func emitTelemetryIfNeeded() {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastTelemetryEmitTime >= 1 else { return }
        lastTelemetryEmitTime = now
        onTelemetry?(telemetrySnapshot)
    }

}
#endif
