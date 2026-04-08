// MetalVideoRendererPresentationResources.swift
// Defines metal video renderer presentation resources for the Integration / WebRTC surface.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(Metal)
import Metal
import MetalKit
#if canImport(MetalFX)
import MetalFX
#endif
import VideoRenderingKit

extension MetalVideoRenderer {
    private func notifyCandidateReadyIfNeeded(_ rung: RenderLadderRung) {
        guard lastReadyRung != rung else { return }
        lastReadyRung = rung
        lastFailedRung = nil
        onCandidateReady?(rung)
    }

    private func notifyCandidateFailedIfNeeded(_ rung: RenderLadderRung, reason: String) {
        guard lastFailedRung != rung else { return }
        lastFailedRung = rung
        processingStatus = "failed"
        lastError = reason
        onCandidateFailed?(rung, reason)
    }

    @MainActor
    func configurePresentationResources(sourceWidth: Int, sourceHeight: Int) {
        let requestedRung = self.requestedRung
#if canImport(MetalFX)
        let drawableSize = desiredDrawableSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        let targetWidth = Int(drawableSize.width.rounded())
        let targetHeight = Int(drawableSize.height.rounded())

        processingInputWidth = sourceWidth
        processingInputHeight = sourceHeight

        guard let requestedRung else {
            mtkView.drawableSize = CGSize(width: sourceWidth, height: sourceHeight)
            spatialScaler = nil
            spatialScalerOutputTexture = nil
            spatialScalerInputSize = MTLSize(width: 0, height: 0, depth: 1)
            spatialScalerOutputSize = MTLSize(width: 0, height: 0, depth: 1)
            processingStatus = "idle"
            processingOutputWidth = sourceWidth
            processingOutputHeight = sourceHeight
            return
        }

        switch requestedRung {
        case .passthrough:
            mtkView.drawableSize = CGSize(width: sourceWidth, height: sourceHeight)
            spatialScaler = nil
            spatialScalerOutputTexture = nil
            spatialScalerInputSize = MTLSize(width: 0, height: 0, depth: 1)
            spatialScalerOutputSize = MTLSize(width: 0, height: 0, depth: 1)
            processingStatus = requestedRung.rawName
            processingOutputWidth = sourceWidth
            processingOutputHeight = sourceHeight
            return
        case .metalFXSpatial, .metal4FXSpatial:
            mtkView.drawableSize = drawableSize
            processingStatus = requestedRung.rawName
            processingOutputWidth = targetWidth
            processingOutputHeight = targetHeight
        default:
            mtkView.drawableSize = CGSize(width: sourceWidth, height: sourceHeight)
            spatialScaler = nil
            spatialScalerOutputTexture = nil
            spatialScalerInputSize = MTLSize(width: 0, height: 0, depth: 1)
            spatialScalerOutputSize = MTLSize(width: 0, height: 0, depth: 1)
            processingStatus = "unsupported"
            processingOutputWidth = sourceWidth
            processingOutputHeight = sourceHeight
            return
        }

        guard targetWidth != spatialScalerOutputSize.width
            || targetHeight != spatialScalerOutputSize.height
            || sourceWidth != spatialScalerInputSize.width
            || sourceHeight != spatialScalerInputSize.height
            || spatialScaler == nil
        else {
            return
        }

        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = sourceWidth
        descriptor.inputHeight = sourceHeight
        descriptor.outputWidth = targetWidth
        descriptor.outputHeight = targetHeight
        descriptor.colorTextureFormat = .bgra8Unorm
        descriptor.outputTextureFormat = .bgra8Unorm
        descriptor.colorProcessingMode = .perceptual

        guard let spatialScaler = descriptor.makeSpatialScaler(device: device) else {
            self.spatialScaler = nil
            spatialScalerOutputTexture = nil
            spatialScalerInputSize = MTLSize(width: 0, height: 0, depth: 1)
            spatialScalerOutputSize = MTLSize(width: 0, height: 0, depth: 1)
            notifyCandidateFailedIfNeeded(
                requestedRung,
                reason: "MetalFX spatial scaler unavailable for \(sourceWidth)x\(sourceHeight) -> \(targetWidth)x\(targetHeight)"
            )
            return
        }

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: targetWidth,
            height: targetHeight,
            mipmapped: false
        )
        outputDescriptor.storageMode = .private
        outputDescriptor.usage = spatialScaler.outputTextureUsage

        guard let spatialScalerOutputTexture = device.makeTexture(descriptor: outputDescriptor) else {
            self.spatialScaler = nil
            self.spatialScalerOutputTexture = nil
            spatialScalerInputSize = MTLSize(width: 0, height: 0, depth: 1)
            spatialScalerOutputSize = MTLSize(width: 0, height: 0, depth: 1)
            print("[MetalRenderer] MetalFX output texture creation failed for \(targetWidth)×\(targetHeight)")
            return
        }

        self.spatialScaler = spatialScaler
        self.spatialScalerOutputTexture = spatialScalerOutputTexture
        spatialScalerInputSize = MTLSize(width: sourceWidth, height: sourceHeight, depth: 1)
        spatialScalerOutputSize = MTLSize(width: targetWidth, height: targetHeight, depth: 1)
        notifyCandidateReadyIfNeeded(requestedRung)
#else
        mtkView.drawableSize = CGSize(width: sourceWidth, height: sourceHeight)
        processingStatus = requestedRung?.rawName ?? "idle"
        processingOutputWidth = sourceWidth
        processingOutputHeight = sourceHeight
        if let requestedRung, requestedRung != .passthrough {
            notifyCandidateFailedIfNeeded(requestedRung, reason: "MetalFX framework unavailable in this build")
        }
#endif
    }
}
#endif
