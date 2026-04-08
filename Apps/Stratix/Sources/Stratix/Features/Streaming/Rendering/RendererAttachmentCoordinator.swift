// RendererAttachmentCoordinator.swift
// Defines the renderer attachment coordinator for the Features / Streaming surface.
//

import Foundation
import StratixCore
import StratixModels
import StreamingCore
import VideoRenderingKit
#if canImport(AVFoundation)
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Metal)
import Metal
import MetalKit
#endif

#if WEBRTC_AVAILABLE && canImport(UIKit)
@MainActor
/// Owns the concrete renderer attachment lifecycle for a stream session's UIKit surface.
final class RendererAttachmentCoordinator: NSObject {
    /// Callback hooks used to surface renderer mode, telemetry, and first-frame events.
    struct Callbacks {
        var onRendererModeChanged: @MainActor (String) -> Void
        var onRendererTelemetryChanged: @MainActor (StreamSurfaceModel.RendererTelemetrySnapshot) -> Void
        var onRendererDecodeFailure: @MainActor (String) -> Void
        var onFirstVideoFrameDrawn: @MainActor () -> Void

        static let noop = Callbacks(
            onRendererModeChanged: { _ in },
            onRendererTelemetryChanged: { _ in },
            onRendererDecodeFailure: { _ in },
            onFirstVideoFrameDrawn: {}
        )
    }

    /// Configuration bundle derived from live settings and passed into the renderer pipeline.
    struct Configuration {
        var upscalingEnabled: Bool
        var frameProbeEnabled: Bool
        var hdrEnabled: Bool
        var floorBehavior: RenderLadderFloorBehavior
        var callbacks: Callbacks

        /// Creates a configuration snapshot from the current settings store values.
        @MainActor
        static func make(
            settingsStore: SettingsStore,
            callbacks: Callbacks
        ) -> Self {
            let floorBehavior: RenderLadderFloorBehavior
            switch settingsStore.diagnostics.upscalingFloorBehavior {
            case .metalFloor:
                floorBehavior = .metalFloor
            case .sampleFloor:
                floorBehavior = .sampleFloor
            }
            return Self(
                upscalingEnabled: settingsStore.stream.upscalingEnabled,
                frameProbeEnabled: settingsStore.diagnostics.frameProbe,
                hdrEnabled: settingsStore.stream.hdrEnabled,
                floorBehavior: floorBehavior,
                callbacks: callbacks
            )
        }
    }

    /// Internal event stream used to serialize renderer callbacks back onto the main actor.
    private enum CallbackEvent: Sendable {
        case firstVideoFrameDrawn
        case decodeFailure(String)
        case sourceDimensionsChanged(width: Int, height: Int)
        case candidateReady(RenderLadderRung, outputFamily: String)
        case candidateFailed(RenderLadderRung, reason: String)
        case sampleTelemetry(StreamSurfaceModel.RendererTelemetrySnapshot)
        case metalTelemetry(StreamSurfaceModel.RendererTelemetrySnapshot)
    }

    /// Pump that forwards callback events into the coordinator's main-actor handlers.
    private final class CallbackEventPump {
        let continuation: AsyncStream<CallbackEvent>.Continuation
        private let task: Task<Void, Never>

        init(owner: RendererAttachmentCoordinator) {
            var capturedContinuation: AsyncStream<CallbackEvent>.Continuation?
            let stream = AsyncStream<CallbackEvent>(bufferingPolicy: .unbounded) {
                capturedContinuation = $0
            }
            self.continuation = capturedContinuation!
            self.task = Task { [weak owner] in
                for await event in stream {
                    guard let owner else { return }
                    await owner.handleCallbackEvent(event)
                }
            }
        }

        deinit {
            continuation.finish()
            task.cancel()
        }
    }

    /// The active container view hosting the sample-buffer and Metal renderers.
    weak var container: UIView?
    var metalRenderer: MetalVideoRenderer?
    weak var sampleBufferView: SampleBufferDisplayView?
    private var attachedTrack: RTCVideoTrack?
    private let frameProbe = FrameProbeRenderer()
    private var frameProbeEnabled = false
    private var isFrameProbeAttached = false
    let sampleBufferRenderer = SampleBufferDisplayRenderer()
    private let ladderPlanner = RenderLadderPlanner(
        resolver: UpscaleCapabilityResolver(probe: LiveUpscaleCapabilityProbe())
    )
    private var callbacks: Callbacks = .noop
    private var sampleRendererSnapshot: StreamSurfaceModel.RendererTelemetrySnapshot = .cleared
    private var metalRendererSnapshot: StreamSurfaceModel.RendererTelemetrySnapshot = .cleared
    private var upscalingEnabled = true
    private var floorBehavior: RenderLadderFloorBehavior = .sampleFloor
    private var lastAppliedTrackIdentity: ObjectIdentifier?
    private var lastAppliedUpscalingEnabled: Bool?
    private var lastAppliedFloorBehavior: RenderLadderFloorBehavior?
    private var lastAppliedFrameProbeEnabled: Bool?
    private var lastAppliedContainerBounds: CGSize?
    private var lastRendererMode: String?
    private var lastRendererTelemetry: StreamSurfaceModel.RendererTelemetrySnapshot?
    private var hasReportedRendererDecodeFailure = false
    private var lastSourceDimensions: StreamDimensions?
    private var ladderPlan: RenderLadderPlan?
    private let maxCandidateFailureCount = 3
    private var candidateFailureCounts: [RenderLadderRung: Int] = [:]
    private var deadRungs: Set<RenderLadderRung> = []
    private var activeRung: RenderLadderRung = .sampleBuffer
    private var pendingRung: RenderLadderRung?
    private var outputFamily = "sampleBuffer"
    private var lastFallbackReason: String?
    private lazy var callbackEventPump = CallbackEventPump(owner: self)

    /// Returns whether the optional frame-probe renderer should be attached.
    private var shouldAttachFrameProbe: Bool {
        frameProbeEnabled
    }

    /// Installs or reuses the render container inside the provided host view.
    func install(
        in view: UIView,
        configuration: Configuration
    ) {
        let container: RendererContainerView
        if let existing = view as? RendererContainerView {
            container = existing
        } else {
            let newContainer = RendererContainerView(frame: view.bounds)
            newContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(newContainer)
            container = newContainer
        }

        container.backgroundColor = .black
        container.isOpaque = true
        self.container = container

        if container.sampleBufferView == nil {
            let sampleBufferView = SampleBufferDisplayView(frame: .zero)
            sampleBufferView.translatesAutoresizingMaskIntoConstraints = true
            sampleBufferView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            sampleBufferView.frame = container.bounds
            sampleBufferView.backgroundColor = .clear
            sampleBufferView.displayLayer.videoGravity = .resizeAspect
            sampleBufferView.displayLayer.backgroundColor = UIColor.black.cgColor
            sampleBufferView.displayLayer.isOpaque = true
            sampleBufferView.isUserInteractionEnabled = false
            container.addSubview(sampleBufferView)
            container.sampleBufferView = sampleBufferView
            sampleBufferRenderer.bind(to: sampleBufferView)
        }

        if metalRenderer == nil, let renderer = MetalVideoRenderer(frame: container.bounds) {
            let mtkView = renderer.mtkView
            mtkView.translatesAutoresizingMaskIntoConstraints = true
            mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            mtkView.frame = container.bounds
            mtkView.isOpaque = true
            mtkView.clipsToBounds = true
            mtkView.isHidden = true
            container.addSubview(mtkView)
            container.mtkView = mtkView
            metalRenderer = renderer
            renderer.updateDisplayTarget()
        } else if metalRenderer == nil {
            streamLog("[StreamView] MetalVideoRenderer init failed — using sample-buffer floor only", force: true)
        }

        sampleBufferView = container.sampleBufferView
        applyConfiguration(configuration)
        showOutputFamily("sampleBuffer")
        publishAggregatedRendererState()
        streamLog("[StreamView] makeUIView created video surface container")
    }

    /// Updates renderer state, bounds, and track attachment for an already-installed container.
    func update(
        in view: UIView,
        videoTrack rawTrack: AnyObject?,
        configuration: Configuration
    ) {
        guard let container = (view as? RendererContainerView) ?? self.container as? RendererContainerView else {
            return
        }
        self.container = container
        sampleBufferView = container.sampleBufferView
        applyConfiguration(configuration)

        if let metalRenderer {
            metalRenderer.mtkView.frame = container.bounds
            metalRenderer.updateDisplayTarget()
        }
        if let sampleBufferView = container.sampleBufferView {
            sampleBufferView.frame = container.bounds
            sampleBufferRenderer.updateDisplayTarget(from: sampleBufferView)
        }
        applyIfNeeded(videoTrack: rawTrack, containerBounds: container.bounds.size)
    }

    /// Tears down attached renderers and clears the cached session state.
    func clear() {
        if let metalRenderer {
            attachedTrack?.remove(metalRenderer)
            metalRenderer.onTelemetry = nil
            metalRenderer.onCandidateReady = nil
            metalRenderer.onCandidateFailed = nil
            metalRenderer.onSourceDimensionsChanged = nil
            metalRenderer.onFirstFrameDrawn = nil
        }
        if isFrameProbeAttached {
            attachedTrack?.remove(frameProbe)
            isFrameProbeAttached = false
        }
        attachedTrack?.remove(sampleBufferRenderer)
        sampleBufferRenderer.reset()
        sampleBufferRenderer.onDecodeFailure = nil
        sampleBufferRenderer.onTelemetry = nil
        sampleBufferRenderer.onSourceDimensionsChanged = nil
        sampleBufferRenderer.onCandidateReady = nil
        sampleBufferRenderer.onCandidateFailed = nil
        sampleBufferRenderer.onFirstFrameDrawn = nil
        callbacks = .noop
        metalRenderer = nil
        attachedTrack = nil
        sampleRendererSnapshot = .cleared
        metalRendererSnapshot = .cleared
        candidateFailureCounts.removeAll()
        deadRungs.removeAll()
        pendingRung = nil
        lastFallbackReason = nil
        lastRendererMode = nil
        lastRendererTelemetry = nil
        hasReportedRendererDecodeFailure = false
        lastAppliedTrackIdentity = nil
        lastAppliedUpscalingEnabled = nil
        lastAppliedFloorBehavior = nil
        lastAppliedFrameProbeEnabled = nil
        lastAppliedContainerBounds = nil
        lastSourceDimensions = nil
        ladderPlan = nil
    }

    private func applyConfiguration(_ configuration: Configuration) {
        callbacks = configuration.callbacks
        upscalingEnabled = configuration.upscalingEnabled
        floorBehavior = configuration.floorBehavior
        setFrameProbeEnabled(configuration.frameProbeEnabled)
        sampleBufferRenderer.hdrEnabled = configuration.hdrEnabled
        let eventContinuation = callbackEventPump.continuation
        sampleBufferRenderer.onFirstFrameDrawn = {
            eventContinuation.yield(.firstVideoFrameDrawn)
        }
        sampleBufferRenderer.onDecodeFailure = { details in
            eventContinuation.yield(.decodeFailure(details))
        }
        sampleBufferRenderer.onSourceDimensionsChanged = { width, height in
            eventContinuation.yield(.sourceDimensionsChanged(width: width, height: height))
        }
        sampleBufferRenderer.onCandidateReady = { rung in
            eventContinuation.yield(.candidateReady(rung, outputFamily: "sampleBuffer"))
        }
        sampleBufferRenderer.onCandidateFailed = { rung, reason in
            eventContinuation.yield(.candidateFailed(rung, reason: reason))
        }
        sampleBufferRenderer.onTelemetry = { snapshot in
            eventContinuation.yield(.sampleTelemetry(Self.makeSampleTelemetrySnapshot(from: snapshot)))
        }
        metalRenderer?.onFirstFrameDrawn = {
            eventContinuation.yield(.firstVideoFrameDrawn)
        }
        metalRenderer?.onSourceDimensionsChanged = { width, height in
            eventContinuation.yield(.sourceDimensionsChanged(width: width, height: height))
        }
        metalRenderer?.onCandidateReady = { rung in
            eventContinuation.yield(.candidateReady(rung, outputFamily: "metal"))
        }
        metalRenderer?.onCandidateFailed = { rung, reason in
            eventContinuation.yield(.candidateFailed(rung, reason: reason))
        }
        metalRenderer?.onTelemetry = { snapshot in
            eventContinuation.yield(.metalTelemetry(Self.makeMetalTelemetrySnapshot(from: snapshot)))
        }
    }

    private func handleCallbackEvent(_ event: CallbackEvent) {
        switch event {
        case .firstVideoFrameDrawn:
            callbacks.onFirstVideoFrameDrawn()
        case .decodeFailure(let details):
            reportRendererDecodeFailureIfNeeded(details)
        case .sourceDimensionsChanged(let width, let height):
            sourceDimensionsDidChange(width: width, height: height)
        case .candidateReady(let rung, let outputFamily):
            handleCandidateReady(rung, outputFamily: outputFamily)
        case .candidateFailed(let rung, let reason):
            handleCandidateFailure(rung, reason: reason)
        case .sampleTelemetry(let snapshot):
            sampleRendererSnapshot = snapshot
            publishAggregatedRendererState()
        case .metalTelemetry(let snapshot):
            metalRendererSnapshot = snapshot
            publishAggregatedRendererState()
        }
    }

    private static func makeSampleTelemetrySnapshot(
        from snapshot: SampleBufferDisplayRenderer.TelemetrySnapshot
    ) -> StreamSurfaceModel.RendererTelemetrySnapshot {
        StreamSurfaceModel.RendererTelemetrySnapshot(
            framesReceived: snapshot.framesReceived,
            framesDrawn: snapshot.framesDrawn,
            framesDroppedByCoalescing: snapshot.framesDroppedByCoalescing,
            drawQueueDepthMax: snapshot.drawQueueDepthMax,
            framesFailed: snapshot.framesFailed,
            processingStatus: snapshot.processingStatus,
            processingInputWidth: snapshot.processingInputWidth,
            processingInputHeight: snapshot.processingInputHeight,
            processingOutputWidth: snapshot.processingOutputWidth,
            processingOutputHeight: snapshot.processingOutputHeight,
            renderLatencyMs: snapshot.renderLatencyMs,
            outputFamily: "sampleBuffer",
            eligibleRungs: [],
            deadRungs: [],
            lastError: snapshot.lastError
        )
    }

    private static func makeMetalTelemetrySnapshot(
        from snapshot: MetalVideoRenderer.TelemetrySnapshot
    ) -> StreamSurfaceModel.RendererTelemetrySnapshot {
        StreamSurfaceModel.RendererTelemetrySnapshot(
            framesReceived: snapshot.framesReceived,
            framesDrawn: snapshot.framesDrawn,
            framesDroppedByCoalescing: snapshot.framesDroppedByCoalescing,
            drawQueueDepthMax: snapshot.drawQueueDepthMax,
            framesFailed: nil,
            processingStatus: snapshot.processingStatus,
            processingInputWidth: snapshot.processingInputWidth,
            processingInputHeight: snapshot.processingInputHeight,
            processingOutputWidth: snapshot.processingOutputWidth,
            processingOutputHeight: snapshot.processingOutputHeight,
            renderLatencyMs: snapshot.renderLatencyMs,
            outputFamily: "metal",
            eligibleRungs: [],
            deadRungs: [],
            lastError: snapshot.lastError
        )
    }

    private func setFrameProbeEnabled(_ enabled: Bool) {
        guard frameProbeEnabled != enabled else { return }
        frameProbeEnabled = enabled
        updateAttachedRendererFamily()
    }

    private func reportRendererModeIfChanged(_ mode: String) {
        guard lastRendererMode != mode else { return }
        lastRendererMode = mode
        callbacks.onRendererModeChanged(mode)
    }

    private func reportRendererTelemetryIfChanged(_ snapshot: StreamSurfaceModel.RendererTelemetrySnapshot) {
        guard lastRendererTelemetry != snapshot else { return }
        lastRendererTelemetry = snapshot
        callbacks.onRendererTelemetryChanged(snapshot)
    }

    private func reportRendererDecodeFailureIfNeeded(_ details: String) {
        guard !hasReportedRendererDecodeFailure else { return }
        hasReportedRendererDecodeFailure = true
        callbacks.onRendererDecodeFailure(details)
    }

    private func sourceDimensionsDidChange(width: Int, height: Int) {
        let dimensions = StreamDimensions(width: width, height: height)
        guard lastSourceDimensions != dimensions else { return }
        lastSourceDimensions = dimensions
        _ = refreshLadderPlanIfNeeded(resetDeadRungs: true)
    }

    private func handleCandidateReady(_ rung: RenderLadderRung, outputFamily: String) {
        guard pendingRung == rung || activeRung != rung else { return }
        pendingRung = nil
        activeRung = rung
        self.outputFamily = outputFamily
        lastFallbackReason = nil
        showOutputFamily(outputFamily)
        updateAttachedRendererFamily()
        publishAggregatedRendererState()
    }

    private func handleCandidateFailure(_ rung: RenderLadderRung, reason: String) {
        candidateFailureCounts = ladderPlanner.failureCountsAfterFailure(
            rung,
            existingFailureCounts: candidateFailureCounts
        )
        let failureCount = candidateFailureCounts[rung, default: 0]
        deadRungs = ladderPlanner.deadRungs(
            from: candidateFailureCounts,
            maxFailures: maxCandidateFailureCount
        )
        if pendingRung == rung {
            pendingRung = nil
        }
        if deadRungs.contains(rung) {
            lastFallbackReason = "\(reason) (failed \(failureCount)x; disabling \(rung.rawName) for this session)"
        } else {
            lastFallbackReason = "\(reason) (attempt \(failureCount)/\(maxCandidateFailureCount))"
        }
        if activeRung == rung {
            activeRung = .sampleBuffer
            outputFamily = "sampleBuffer"
            showOutputFamily("sampleBuffer")
            updateAttachedRendererFamily()
        }
        switch rung {
        case .vtSuperResolution, .vtFrameInterpolation:
            sampleBufferRenderer.setRequestedRung(rung)
            metalRenderer?.setRequestedRung(nil)
        case .metal4FXSpatial, .metalFXSpatial, .passthrough:
            metalRenderer?.setRequestedRung(nil)
        case .sampleBuffer:
            break
        }
        updateAttachedRendererFamily()
        if deadRungs.contains(rung) {
            let nextCandidate = ladderPlan.flatMap { ladderPlanner.nextCandidate(in: $0, deadRungs: deadRungs) }
            if let nextCandidate {
                streamLog(
                    "[StreamView] Render ladder disabling \(rung.rawName) after \(failureCount)x failures; advancing to \(nextCandidate.rawName)",
                    force: true
                )
            } else {
                streamLog(
                    "[StreamView] Render ladder disabling \(rung.rawName) after \(failureCount)x failures; no higher rung remains, staying on \(outputFamily)",
                    force: true
                )
            }
        }
        publishAggregatedRendererState()
        attemptNextCandidateIfNeeded()
    }

    private func publishAggregatedRendererState() {
        let baseSnapshot = outputFamily == "metal" ? metalRendererSnapshot : sampleRendererSnapshot
        let desiredTarget = ladderPlan?.desiredProcessingTarget
        let effectiveStatus: String? = {
            if let pendingRung, activeRung == .sampleBuffer {
                return "\(pendingRung.rawName)-warming"
            }
            return baseSnapshot.processingStatus
        }()
        let snapshot = StreamSurfaceModel.RendererTelemetrySnapshot(
            framesReceived: baseSnapshot.framesReceived,
            framesDrawn: baseSnapshot.framesDrawn,
            framesDroppedByCoalescing: baseSnapshot.framesDroppedByCoalescing,
            drawQueueDepthMax: baseSnapshot.drawQueueDepthMax,
            framesFailed: baseSnapshot.framesFailed,
            processingStatus: effectiveStatus,
            processingInputWidth: baseSnapshot.processingInputWidth ?? lastSourceDimensions?.width,
            processingInputHeight: baseSnapshot.processingInputHeight ?? lastSourceDimensions?.height,
            processingOutputWidth: baseSnapshot.processingOutputWidth ?? outputWidthFallback(desiredTarget: desiredTarget),
            processingOutputHeight: baseSnapshot.processingOutputHeight ?? outputHeightFallback(desiredTarget: desiredTarget),
            renderLatencyMs: baseSnapshot.renderLatencyMs,
            outputFamily: outputFamily,
            eligibleRungs: ladderPlan?.eligibleRungs.map(\.rawName) ?? [],
            deadRungs: deadRungs.map(\.rawName).sorted(),
            lastError: baseSnapshot.lastError ?? lastFallbackReason
        )
        reportRendererModeIfChanged(activeRung.rawName)
        reportRendererTelemetryIfChanged(snapshot)
    }

    private func showOutputFamily(_ family: String) {
        sampleBufferView?.isHidden = family == "metal"
        metalRenderer?.mtkView.isHidden = family != "metal"
    }

    @discardableResult
    private func refreshLadderPlanIfNeeded(resetDeadRungs: Bool) -> Bool {
        guard let source = lastSourceDimensions else {
            publishAggregatedRendererState()
            return false
        }

        if resetDeadRungs {
            candidateFailureCounts.removeAll()
            deadRungs.removeAll()
            lastFallbackReason = nil
        }

        let target: StreamDimensions = {
            if let sampleBufferView = sampleBufferView {
                let displayTarget = sampleBufferView.displayTargetDimensions
                if let width = displayTarget.width, let height = displayTarget.height {
                    return StreamDimensions(width: width, height: height)
                }
            }
            return source
        }()
        let metalDevice = metalRenderer?.metalDevice ?? MTLCreateSystemDefaultDevice()
        let nextPlan = ladderPlanner.makePlan(
            device: metalDevice,
            sourceW: source.width,
            sourceH: source.height,
            targetW: target.width,
            targetH: target.height,
            upscalingEnabled: upscalingEnabled,
            floorBehavior: floorBehavior
        )
        let planChanged = ladderPlan != nextPlan
        ladderPlan = nextPlan

        guard resetDeadRungs || planChanged else {
            publishAggregatedRendererState()
            return false
        }

        activeRung = .sampleBuffer
        pendingRung = nil
        outputFamily = "sampleBuffer"
        sampleBufferRenderer.setRequestedRung(.sampleBuffer)
        metalRenderer?.setRequestedRung(nil)
        showOutputFamily("sampleBuffer")
        updateAttachedRendererFamily()
        logCurrentLadderPlan()
        publishAggregatedRendererState()
        attemptNextCandidateIfNeeded()
        return true
    }

    private func attemptNextCandidateIfNeeded() {
        guard upscalingEnabled, let ladderPlan, pendingRung == nil else { return }
        guard let nextCandidate = ladderPlanner.nextCandidate(in: ladderPlan, deadRungs: deadRungs) else { return }

        pendingRung = nextCandidate
        let nextAttempt = candidateFailureCounts[nextCandidate, default: 0] + 1
        streamLog(
            "[StreamView] Render ladder attempting \(nextCandidate.rawName) attempt \(nextAttempt)/\(maxCandidateFailureCount) source=\(ladderPlan.sourceDimensions.width)x\(ladderPlan.sourceDimensions.height) target=\(ladderPlan.desiredProcessingTarget.width)x\(ladderPlan.desiredProcessingTarget.height)",
            force: true
        )
        switch nextCandidate {
        case .vtSuperResolution, .vtFrameInterpolation:
            sampleBufferRenderer.setRequestedRung(nextCandidate)
            metalRenderer?.setRequestedRung(nil)
        case .metal4FXSpatial, .metalFXSpatial, .passthrough:
            guard let metalRenderer else {
                handleCandidateFailure(nextCandidate, reason: "Metal renderer unavailable")
                return
            }
            sampleBufferRenderer.setRequestedRung(.sampleBuffer)
            metalRenderer.setRequestedRung(nextCandidate)
        case .sampleBuffer:
            pendingRung = nil
        }
        updateAttachedRendererFamily()
        publishAggregatedRendererState()
    }

    private func logCurrentLadderPlan() {
        guard let ladderPlan else { return }
        let eligible = ladderPlan.eligibleRungs.map(\.rawName).joined(separator: ", ")
        let skipped: String = {
            guard !ladderPlan.skippedRungReasons.isEmpty else { return "none" }
            return ladderPlan.skippedRungReasons
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
        }()
        streamLog(
            "[StreamView] Render ladder plan source=\(ladderPlan.sourceDimensions.width)x\(ladderPlan.sourceDimensions.height) displayTarget=\(ladderPlan.displayTargetDimensions.width)x\(ladderPlan.displayTargetDimensions.height) desiredTarget=\(ladderPlan.desiredProcessingTarget.width)x\(ladderPlan.desiredProcessingTarget.height) eligible=[\(eligible)] skipped={\(skipped)} floor=\(ladderPlan.floorRung.rawName)",
            force: true
        )
    }

    private func outputWidthFallback(desiredTarget: RenderLadderDimensions?) -> Int? {
        guard (pendingRung != nil || activeRung != .sampleBuffer), let desiredTarget else { return nil }
        return desiredTarget.width
    }

    private func outputHeightFallback(desiredTarget: RenderLadderDimensions?) -> Int? {
        guard (pendingRung != nil || activeRung != .sampleBuffer), let desiredTarget else { return nil }
        return desiredTarget.height
    }

    private func applyIfNeeded(videoTrack rawTrack: AnyObject?, containerBounds: CGSize) {
        let newTrack = rawTrack as? RTCVideoTrack
        let trackChanged = attachedTrack !== newTrack
        let frameProbeChanged = lastAppliedFrameProbeEnabled != frameProbeEnabled
        let settingsChanged = lastAppliedUpscalingEnabled != upscalingEnabled
            || lastAppliedFloorBehavior != floorBehavior
            || frameProbeChanged
            || lastAppliedContainerBounds != containerBounds

        if trackChanged {
            if let attachedTrack {
                attachedTrack.remove(sampleBufferRenderer)
                if let metalRenderer {
                    attachedTrack.remove(metalRenderer)
                }
                if isFrameProbeAttached {
                    attachedTrack.remove(frameProbe)
                    isFrameProbeAttached = false
                }
                streamLog("[StreamView] detached previous video track")
            }
            attachedTrack = newTrack
        }

        guard trackChanged || settingsChanged else { return }
        lastAppliedTrackIdentity = newTrack.map(ObjectIdentifier.init)
        lastAppliedUpscalingEnabled = upscalingEnabled
        lastAppliedFloorBehavior = floorBehavior
        lastAppliedFrameProbeEnabled = frameProbeEnabled
        lastAppliedContainerBounds = containerBounds
        let didResetLadderPlan = refreshLadderPlanIfNeeded(resetDeadRungs: false)
        if trackChanged || didResetLadderPlan || frameProbeChanged {
            updateAttachedRendererFamily()
        }
    }

    private func updateAttachedRendererFamily() {
        guard let attachedTrack else { return }
        attachedTrack.remove(sampleBufferRenderer)
        if let metalRenderer {
            attachedTrack.remove(metalRenderer)
        }
        let wantsMetalAttachment: Bool = {
            guard upscalingEnabled else { return false }
            switch pendingRung ?? activeRung {
            case .metal4FXSpatial, .metalFXSpatial, .passthrough:
                return metalRenderer != nil
            case .sampleBuffer, .vtSuperResolution, .vtFrameInterpolation:
                return false
            }
        }()
        if wantsMetalAttachment, let metalRenderer {
            attachedTrack.add(metalRenderer)
        } else {
            attachedTrack.add(sampleBufferRenderer)
        }

        if isFrameProbeAttached {
            attachedTrack.remove(frameProbe)
            isFrameProbeAttached = false
        }
        if shouldAttachFrameProbe {
            attachedTrack.add(frameProbe)
            isFrameProbeAttached = true
        }
    }
}
#endif
