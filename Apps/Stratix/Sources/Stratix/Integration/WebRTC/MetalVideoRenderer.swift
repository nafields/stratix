//
//  MetalVideoRenderer.swift
//  Stratix
//
//  RTCVideoRenderer that converts each WebRTC NV12 frame to BGRA via a Metal
//  compute shader, then upscales to the display's native resolution using the
//  best available strategy resolved by UpscaleCapabilityResolver.
//
//  Upscale priority: Metal4FX → LLSR → LLFI → MetalFX → passthrough.
//  (VT tiers detected and logged; MetalFX encode path used until VT display path lands.)
//
//  Pipeline:
//    WebRTC frame (RTCCVPixelBuffer NV12)
//      ↓ CVMetalTextureCacheCreateTextureFromImage (zero-copy)
//      ↓ nv12ToBGRA compute shader  (NV12 → BGRA, BT.709, auto 420f/420v range)
//      ↓ optional MTLFXSpatialScaler  (frame → display-native resolution)
//      ↓ blit to MTKView drawable
//      ↓ MTKView display
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(Metal)
import UIKit
import Metal
import MetalKit
#if canImport(MetalFX)
import MetalFX
#endif
import CoreVideo
import AVFoundation
import VideoRenderingKit

// MARK: - MetalVideoRenderer

/// An RTCVideoRenderer conformant object that converts each incoming NV12 frame to
/// BGRA via a Metal compute shader and optionally upscales to the display's native
/// resolution with MetalFX Spatial Scaling.
///
/// Usage:
///   1. Create with `MetalVideoRenderer(frame:)` — returns nil if Metal is unavailable.
///   2. Add `mtkView` as a subview and size it to fill the video container.
///   3. Register as an RTCVideoRenderer on the received RTCVideoTrack.
final class MetalVideoRenderer: NSObject, RTCVideoRenderer, MTKViewDelegate, @unchecked Sendable {

    // MARK: - Public interface

    /// The MTKView managed by this renderer. Add as a subview in the video container.
    let mtkView: MTKView
    var metalDevice: MTLDevice { device }

    /// Called at most once per second with renderer counter telemetry.
    var onTelemetry: ((TelemetrySnapshot) -> Void)?
    var onCandidateReady: ((RenderLadderRung) -> Void)?
    var onCandidateFailed: ((RenderLadderRung, String) -> Void)?
    var onSourceDimensionsChanged: ((Int, Int) -> Void)?
    var onFirstFrameDrawn: (() -> Void)?

    // MARK: - Shared renderer resources
    //
    // These members intentionally stay module-visible so the companion-file
    // extensions can own draw-pipeline and presentation-resource boundaries
    // without collapsing everything back into this root file.

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    var textureCache: CVMetalTextureCache?

    /// Intermediate BGRA texture written by the compute shader.
    /// Sized to match the incoming video resolution; recreated on resolution change.
    var outputTexture: MTLTexture?
    var outputSize: MTLSize = MTLSize(width: 0, height: 0, depth: 1)
#if canImport(MetalFX)
    var spatialScaler: (any MTLFXSpatialScaler)?
    var spatialScalerOutputTexture: MTLTexture?
    var spatialScalerInputSize: MTLSize = MTLSize(width: 0, height: 0, depth: 1)
    var spatialScalerOutputSize: MTLSize = MTLSize(width: 0, height: 0, depth: 1)
#endif

    // MARK: - Thread safety
    //
    // WebRTC calls renderFrame(_:) on a background thread. We use a simple NSLock to
    // pass the latest CVPixelBuffer to the draw loop on the main thread. Only the most
    // recent frame is retained — if MTKView hasn't drawn by the time the next frame
    // arrives, the earlier frame is silently dropped (correct temporal behaviour).

    let lock = NSLock()
    var latestPixelBuffer: CVPixelBuffer?
    var drawScheduled = false
    var frameArrivedWhileDrawing = false
    var framesReceived = 0
    var framesDrawn = 0
    var framesDroppedByCoalescing = 0
    var drawQueueDepthMax = 0
    var lastTelemetryEmitTime: TimeInterval = 0
    var processingStatus: String?
    var processingInputWidth: Int?
    var processingInputHeight: Int?
    var processingOutputWidth: Int?
    var processingOutputHeight: Int?
    var renderLatencyMs: Double?
    var lastError: String?
    var latestFrameArrivalTime: TimeInterval?
    var requestedRung: RenderLadderRung?
    var lastReadyRung: RenderLadderRung?
    var lastFailedRung: RenderLadderRung?
    var didReportFirstDraw = false

    /// Returns the latest renderer counters and processing state for diagnostics surfaces.
    var telemetrySnapshot: TelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return TelemetrySnapshot(
            framesReceived: framesReceived,
            framesDrawn: framesDrawn,
            framesDroppedByCoalescing: framesDroppedByCoalescing,
            drawQueueDepthMax: drawQueueDepthMax,
            processingStatus: processingStatus,
            processingInputWidth: processingInputWidth,
            processingInputHeight: processingInputHeight,
            processingOutputWidth: processingOutputWidth,
            processingOutputHeight: processingOutputHeight,
            renderLatencyMs: renderLatencyMs,
            lastError: lastError
        )
    }

    // MARK: - Init

    /// Returns nil if Metal is unavailable (simulator without Metal, unsupported hardware).
    /// Must be called on the main actor because MTKView is @MainActor-isolated.
    @MainActor
    init?(frame: CGRect) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else {
            print("[MetalRenderer] Metal device/command queue unavailable — renderer init failed")
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue

        // Load the nv12ToBGRA function from the app's default Metal library
        // (compiled from CASShader.metal as part of the app target's Sources).
        guard
            let library = device.makeDefaultLibrary(),
            let kernelFn = library.makeFunction(name: "nv12ToBGRA")
        else {
            print("[MetalRenderer] nv12ToBGRA not found in default Metal library — renderer init failed")
            return nil
        }
        do {
            self.pipelineState = try device.makeComputePipelineState(function: kernelFn)
        } catch {
            print("[MetalRenderer] makeComputePipelineState failed: \(error) — renderer init failed")
            return nil
        }

        // CVMetalTextureCache gives zero-copy CVPixelBuffer → MTLTexture access.
        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard cacheStatus == kCVReturnSuccess, let cache else {
            print("[MetalRenderer] CVMetalTextureCacheCreate failed: \(cacheStatus)")
            return nil
        }
        self.textureCache = cache

        // Configure MTKView for on-demand rendering driven by incoming frames.
        let view = MTKView(frame: frame, device: device)
        view.device = device
        view.isPaused = true                // Frames drive drawing; no CADisplayLink timer.
        view.enableSetNeedsDisplay = false  // We call draw() manually.
        view.framebufferOnly = false        // Allow blit from output texture → drawable.
        view.colorPixelFormat = .bgra8Unorm
        view.backgroundColor = .black
        // Drawable size is updated dynamically to either the video frame size or the
        // MetalFX upscaled target size for the active screen.
        view.autoResizeDrawable = false
        view.contentMode = .scaleAspectFit  // UIKit scales the view contents to fit the container.
        self.mtkView = view

        super.init()

        view.delegate = self
        lastTelemetryEmitTime = Date.timeIntervalSinceReferenceDate
        print("[MetalRenderer] MetalVideoRenderer initialised (device: \(device.name))")
    }

    // MARK: - RTCVideoRenderer

    /// Rebuilds intermediate render resources when the incoming source dimensions change.
    func setSize(_ size: CGSize) {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0 && h > 0 else { return }
        onSourceDimensionsChanged?(w, h)
        if w != outputSize.width || h != outputSize.height {
            outputSize = MTLSize(width: w, height: h, depth: 1)

            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: w,
                height: h,
                mipmapped: false
            )
            desc.usage = [.shaderWrite, .shaderRead]
            desc.storageMode = .private
            outputTexture = device.makeTexture(descriptor: desc)
            print("[MetalRenderer] output texture created \(w)×\(h)")
        }

        Task { @MainActor [weak self] in
            self?.updateDisplayTarget()
        }
    }

    /// Recomputes presentation resources for the current drawable and requested display target.
    @MainActor
    func updateDisplayTarget() {
        guard outputSize.width > 0, outputSize.height > 0 else { return }
        configurePresentationResources(sourceWidth: outputSize.width, sourceHeight: outputSize.height)
    }

    // MARK: - Main Thread Draw

    /// Schedules one MTKView draw pass on the main actor for the most recent coalesced frame.
    func scheduleMainThreadDraw() {
        // isPaused=true means MTKView won't draw autonomously; this call renders one frame.
        Task { @MainActor [weak self] in
            self?.mtkView.draw()
        }
    }

    /// Records the active render-ladder request and clears stale readiness/failure telemetry.
    func setRequestedRung(_ rung: RenderLadderRung?) {
        lock.lock()
        let changed = requestedRung != rung
        requestedRung = rung
        if changed {
            lastReadyRung = nil
            lastFailedRung = nil
            lastError = nil
            processingStatus = rung?.rawName
        }
        lock.unlock()
        Task { @MainActor [weak self] in
            self?.updateDisplayTarget()
        }
    }

    /// Called on a WebRTC background thread for every incoming decoded frame.
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }

        // We only handle CVPixelBuffer-backed frames (H.264/HEVC decoder output on tvOS).
        guard let cvBuf = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer else {
            return
        }

        let shouldScheduleDraw: Bool
        lock.lock()
        framesReceived += 1
        latestPixelBuffer = cvBuf
        latestFrameArrivalTime = Date.timeIntervalSinceReferenceDate
        if drawScheduled {
            frameArrivedWhileDrawing = true
            framesDroppedByCoalescing += 1
            drawQueueDepthMax = max(drawQueueDepthMax, 1)
            shouldScheduleDraw = false
        } else {
            drawScheduled = true
            drawQueueDepthMax = max(drawQueueDepthMax, 1)
            shouldScheduleDraw = true
        }
        lock.unlock()

        guard shouldScheduleDraw else { return }
        scheduleMainThreadDraw()
    }

}

// MARK: - Telemetry

extension MetalVideoRenderer {
    struct TelemetrySnapshot: Sendable {
        let framesReceived: Int
        let framesDrawn: Int
        let framesDroppedByCoalescing: Int
        let drawQueueDepthMax: Int
        let processingStatus: String?
        let processingInputWidth: Int?
        let processingInputHeight: Int?
        let processingOutputWidth: Int?
        let processingOutputHeight: Int?
        let renderLatencyMs: Double?
        let lastError: String?
    }
}

#endif // WEBRTC_AVAILABLE && canImport(UIKit) && canImport(Metal)
