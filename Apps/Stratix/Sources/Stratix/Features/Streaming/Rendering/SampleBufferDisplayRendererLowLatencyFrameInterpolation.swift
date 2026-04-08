//
//  SampleBufferDisplayRendererLowLatencyFrameInterpolation.swift
//  Stratix
//
//  Low-latency frame interpolation pipeline for the sample-buffer renderer.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(AVFoundation)
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
#if canImport(VideoToolbox)
@preconcurrency import VideoToolbox
#endif

#if canImport(VideoToolbox) && !targetEnvironment(simulator)
extension SampleBufferDisplayRenderer {
    @available(tvOS 26.0, *)
    enum LowLatencySourceRoute: String {
        case direct
        case copied
    }

    @available(tvOS 26.0, *)
    func shouldAttemptLowLatencyFrameInterpolation(for pixelBuffer: CVPixelBuffer) -> Bool {
        stateLock.lock()
        let shouldAttempt = !lowLatencyFallbackToPlainSampleBuffer
        stateLock.unlock()
        guard shouldAttempt else { return false }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard VTLowLatencyFrameInterpolationConfiguration.isSupported else {
            activateLowLatencyFallback(reason: "configuration unsupported for \(width)x\(height)", failedStatus: "fallback")
            return false
        }
        return true
    }

    @available(tvOS 26.0, *)
    func makeLowLatencySourceFrame(
        from pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        resources: LowLatencyFrameInterpolationResources
    ) throws -> (frame: VTFrameProcessorFrame, route: LowLatencySourceRoute) {
        if !lowLatencySourceBufferNeedsCopy(pixelBuffer, requiredAttributes: resources.configuration.sourcePixelBufferAttributes),
           let directSourceFrame = VTFrameProcessorFrame(buffer: pixelBuffer, presentationTimeStamp: presentationTimeStamp) {
            return (directSourceFrame, .direct)
        }

        var preparedSourcePixelBuffer: CVPixelBuffer?
        let sourceStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, resources.sourcePool, &preparedSourcePixelBuffer)
        guard sourceStatus == kCVReturnSuccess, let preparedSourcePixelBuffer else {
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: Int(sourceStatus),
                userInfo: [NSLocalizedDescriptionKey: "source pixel buffer allocation failed: \(sourceStatus)"]
            )
        }
        let transferStatus = VTPixelTransferSessionTransferImage(resources.pixelTransferSession, from: pixelBuffer, to: preparedSourcePixelBuffer)
        guard transferStatus == noErr else {
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: Int(transferStatus),
                userInfo: [NSLocalizedDescriptionKey: "source pixel transfer failed: \(transferStatus)"]
            )
        }
        copyDisplayAttachments(from: pixelBuffer, to: preparedSourcePixelBuffer)
        if !didLogLowLatencySourceCopy {
            didLogLowLatencySourceCopy = true
            let inputPixelFormat = pixelFormatDescription(CVPixelBufferGetPixelFormatType(pixelBuffer))
            let copiedPixelFormat = pixelFormatDescription(CVPixelBufferGetPixelFormatType(preparedSourcePixelBuffer))
            let copiedAttributes = (CVPixelBufferCopyCreationAttributes(preparedSourcePixelBuffer) as? [String: Any])
                .map(lowLatencyAttributeSummary) ?? "unavailable"
            let copiedAttachments = pixelBufferColorAttachmentSummary(preparedSourcePixelBuffer)
            streamLog("[StreamView][SBR \(rendererDebugID)] LLFI source copy inputPF=\(inputPixelFormat) copiedPF=\(copiedPixelFormat) attrs={\(copiedAttributes)} attachments={\(copiedAttachments)}", force: true)
        }

        guard let copiedSourceFrame = VTFrameProcessorFrame(buffer: preparedSourcePixelBuffer, presentationTimeStamp: presentationTimeStamp) else {
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "source frame was not IOSurface-backed"]
            )
        }
        return (copiedSourceFrame, .copied)
    }

    @available(tvOS 26.0, *)
    func midpointPresentationTimeStamp(between firstPTS: CMTime, and secondPTS: CMTime) -> CMTime {
        CMTimeAdd(firstPTS, CMTimeMultiplyByRatio(CMTimeSubtract(secondPTS, firstPTS), multiplier: 1, divisor: 2))
    }

    @available(tvOS 26.0, *)
    func submitLowLatencyFrameInterpolationFrame(_ pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let resources: LowLatencyFrameInterpolationResources
        do {
            resources = try lowLatencyFrameInterpolationResources(for: pixelBuffer)
        } catch {
            activateLowLatencyFallback(reason: "session startup failed: \(lowLatencyErrorDetails(error))", failedStatus: "fallback")
            return
        }

        let pairToProcess: (previousPixelBuffer: CVPixelBuffer, previousPTS: CMTime, currentPixelBuffer: CVPixelBuffer, currentPTS: CMTime, expectedGeneration: UInt64)?
        stateLock.lock()
        processingInputWidth = width
        processingInputHeight = height
        processingOutputWidth = resources.outputWidth
        processingOutputHeight = resources.outputHeight
        if previousLLFIPixelBuffer == nil || previousLLFIPresentationTimeStamp == nil {
            previousLLFIPixelBuffer = pixelBuffer
            previousLLFIPresentationTimeStamp = presentationTimeStamp
            processingStatus = "warming"
            stateLock.unlock()
            emitTelemetryIfNeeded(force: true)
            return
        }

        if lowLatencyProcessingInFlight {
            let alreadyQueuedFrame = pendingLLFIPixelBuffer != nil
            if alreadyQueuedFrame {
                framesDroppedByCoalescing += 1
            }
            pendingLLFIPixelBuffer = pixelBuffer
            pendingLLFIPresentationTimeStamp = presentationTimeStamp
            drawQueueDepthMax = max(drawQueueDepthMax, alreadyQueuedFrame ? 2 : 1)
            pairToProcess = nil
        } else {
            let previousPixelBuffer = previousLLFIPixelBuffer!
            let previousPTS = previousLLFIPresentationTimeStamp!
            previousLLFIPixelBuffer = pixelBuffer
            previousLLFIPresentationTimeStamp = presentationTimeStamp
            lowLatencyProcessingInFlight = true
            lowLatencyProcessingGeneration = currentLowLatencyGeneration
            drawQueueDepthMax = max(drawQueueDepthMax, 1)
            pairToProcess = (
                previousPixelBuffer: previousPixelBuffer,
                previousPTS: previousPTS,
                currentPixelBuffer: pixelBuffer,
                currentPTS: presentationTimeStamp,
                expectedGeneration: lowLatencyProcessingGeneration
            )
        }
        stateLock.unlock()

        guard let pairToProcess else {
            emitTelemetryIfNeeded()
            return
        }
        updateLowLatencyStatus("starting", inputWidth: width, inputHeight: height, outputWidth: resources.outputWidth, outputHeight: resources.outputHeight)
        processLowLatencyFrameInterpolation(
            previousPixelBuffer: pairToProcess.previousPixelBuffer,
            previousPresentationTimeStamp: pairToProcess.previousPTS,
            currentPixelBuffer: pairToProcess.currentPixelBuffer,
            currentPresentationTimeStamp: pairToProcess.currentPTS,
            resources: resources,
            expectedGeneration: pairToProcess.expectedGeneration
        )
    }

    @available(tvOS 26.0, *)
    func processLowLatencyFrameInterpolation(
        previousPixelBuffer: CVPixelBuffer,
        previousPresentationTimeStamp: CMTime,
        currentPixelBuffer: CVPixelBuffer,
        currentPresentationTimeStamp: CMTime,
        resources: LowLatencyFrameInterpolationResources,
        expectedGeneration: UInt64,
        initializationRetryAttempt: Int = 0,
        initializationRetryStartTime: TimeInterval? = nil
    ) {
        let previousSource: (frame: VTFrameProcessorFrame, route: LowLatencySourceRoute)
        let currentSource: (frame: VTFrameProcessorFrame, route: LowLatencySourceRoute)
        do {
            previousSource = try makeLowLatencySourceFrame(
                from: previousPixelBuffer,
                presentationTimeStamp: previousPresentationTimeStamp,
                resources: resources
            )
            currentSource = try makeLowLatencySourceFrame(
                from: currentPixelBuffer,
                presentationTimeStamp: currentPresentationTimeStamp,
                resources: resources
            )
        } catch {
            handleLowLatencyFrameInterpolationFailure(
                expectedGeneration: expectedGeneration,
                reason: "source frame preparation failed: \(lowLatencyErrorDetails(error))"
            )
            return
        }

        let midpointPTS = midpointPresentationTimeStamp(between: previousPresentationTimeStamp, and: currentPresentationTimeStamp)

        var interpolatedPixelBuffer: CVPixelBuffer?
        let interpolatedStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, resources.destinationPool, &interpolatedPixelBuffer)
        guard interpolatedStatus == kCVReturnSuccess, let interpolatedPixelBuffer else {
            handleLowLatencyFrameInterpolationFailure(
                expectedGeneration: expectedGeneration,
                reason: "interpolated pixel buffer allocation failed: \(interpolatedStatus)"
            )
            return
        }

        guard let interpolatedFrame = VTFrameProcessorFrame(buffer: interpolatedPixelBuffer, presentationTimeStamp: midpointPTS) else {
            handleLowLatencyFrameInterpolationFailure(
                expectedGeneration: expectedGeneration,
                reason: "interpolated frame was not IOSurface-backed"
            )
            return
        }

        guard let parameters = VTLowLatencyFrameInterpolationParameters(
            sourceFrame: currentSource.frame,
            previousFrame: previousSource.frame,
            interpolationPhase: [0.5],
            destinationFrames: [interpolatedFrame]
        ) else {
            handleLowLatencyFrameInterpolationFailure(
                expectedGeneration: expectedGeneration,
                reason: "failed to create frame interpolation parameters"
            )
            return
        }

        let previousSourceRoute = previousSource.route
        let currentSourceRoute = currentSource.route
        let resourcesToken = Self.makeRetainedReferenceToken(resources)
        let parametersToken = Self.makeRetainedReferenceToken(parameters)
        let currentPixelBufferToken = Self.makeRetainedReferenceToken(currentPixelBuffer as AnyObject)
        let interpolatedPixelBufferToken = Self.makeRetainedReferenceToken(interpolatedPixelBuffer as AnyObject)
        let previousPixelBufferToken = Self.makeRetainedReferenceToken(previousPixelBuffer as AnyObject)

        Task {
            let resources = Self.takeRetainedReference(resourcesToken) as! LowLatencyFrameInterpolationResources
            let parameters = Self.takeRetainedReference(parametersToken) as! VTLowLatencyFrameInterpolationParameters
            let currentPixelBuffer = Self.takeRetainedReference(currentPixelBufferToken) as! CVPixelBuffer
            let interpolatedPixelBuffer = Self.takeRetainedReference(interpolatedPixelBufferToken) as! CVPixelBuffer
            let previousPixelBuffer = Self.takeRetainedReference(previousPixelBufferToken) as! CVPixelBuffer
            do {
                var processedFrameCount = 0
                for try await _ in resources.processor.process(parameters: parameters) {
                    processedFrameCount += 1
                }
                guard processedFrameCount > 0 else {
                    throw NSError(
                        domain: "StreamView.LowLatencyFrameInterpolation",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "LLFI process returned no output frames"]
                    )
                }
                self.handleLowLatencyFrameInterpolationSuccess(
                    expectedGeneration: expectedGeneration,
                    previousSourceRoute: previousSourceRoute,
                    currentSourceRoute: currentSourceRoute,
                    previousPixelBuffer: previousPixelBuffer,
                    currentPixelBuffer: currentPixelBuffer,
                    interpolatedPixelBuffer: interpolatedPixelBuffer,
                    currentPresentationTimeStamp: currentPresentationTimeStamp,
                    interpolatedPresentationTimeStamp: midpointPTS,
                    inputWidth: CVPixelBufferGetWidth(currentPixelBuffer),
                    inputHeight: CVPixelBufferGetHeight(currentPixelBuffer),
                    outputWidth: CVPixelBufferGetWidth(interpolatedPixelBuffer),
                    outputHeight: CVPixelBufferGetHeight(interpolatedPixelBuffer)
                )
            } catch {
                let errorDetails = self.lowLatencyErrorDetails(error)
                streamLog("[StreamView][SBR \(self.rendererDebugID)] LLFI process error: \(errorDetails)", force: true)
                if self.isLowLatencyInitializationError(error) {
                    let retryStartTime = initializationRetryStartTime ?? Date.timeIntervalSinceReferenceDate
                    let elapsed = Date.timeIntervalSinceReferenceDate - retryStartTime
                    let retryWindow = self.lowLatencyInitializationRetryWindowSeconds()
                    if elapsed < retryWindow {
                        let nextAttempt = initializationRetryAttempt + 1
                        let retryDelay = self.lowLatencyInitializationRetryDelayNanoseconds(forAttempt: nextAttempt)
                        let remaining = max(0, retryWindow - elapsed)
                        self.updateLowLatencyStatus(
                            "warming",
                            inputWidth: CVPixelBufferGetWidth(currentPixelBuffer),
                            inputHeight: CVPixelBufferGetHeight(currentPixelBuffer),
                            outputWidth: CVPixelBufferGetWidth(interpolatedPixelBuffer),
                            outputHeight: CVPixelBufferGetHeight(interpolatedPixelBuffer),
                            lastError: String(format: "processor initializing (attempt %d, %.1fs left)", nextAttempt, remaining) + " \(errorDetails)"
                        )
                        streamLog("[StreamView][SBR \(self.rendererDebugID)] LLFI processor not ready yet; retrying attempt \(nextAttempt) in \(retryDelay / 1_000_000)ms (elapsed \(String(format: "%.2f", elapsed))s / 30.00s) error={\(errorDetails)}", force: true)
                            try? await Task.sleep(for: .nanoseconds(retryDelay))
                        guard self.canContinueLowLatencyFrameInterpolation(
                            expectedGeneration: expectedGeneration,
                            resources: resources
                        ) else { return }
                        self.processLowLatencyFrameInterpolation(
                            previousPixelBuffer: previousPixelBuffer,
                            previousPresentationTimeStamp: previousPresentationTimeStamp,
                            currentPixelBuffer: currentPixelBuffer,
                            currentPresentationTimeStamp: currentPresentationTimeStamp,
                            resources: resources,
                            expectedGeneration: expectedGeneration,
                            initializationRetryAttempt: nextAttempt,
                            initializationRetryStartTime: retryStartTime
                        )
                        return
                    }
                }
                let failureReason: String
                if self.isLowLatencyInitializationError(error) {
                    failureReason = "process failed after 30s initialization window: \(errorDetails)"
                } else {
                    failureReason = "process failed: \(errorDetails)"
                }
                self.handleLowLatencyFrameInterpolationFailure(
                    expectedGeneration: expectedGeneration,
                    reason: failureReason
                )
            }
        }
    }

    @available(tvOS 26.0, *)
    func lowLatencyFrameInterpolationResources(for pixelBuffer: CVPixelBuffer) throws -> LowLatencyFrameInterpolationResources {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let requestedSpatialScale = 2
        let outputWidth = width * requestedSpatialScale
        let outputHeight = height * requestedSpatialScale
        let displayTarget = lowLatencyDisplayTargetDimensions()
        let inputPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let configuration = VTLowLatencyFrameInterpolationConfiguration(
            frameWidth: width,
            frameHeight: height,
            spatialScaleFactor: requestedSpatialScale
        )

        guard let configuration else {
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "2x spatial frame interpolation unsupported for \(width)x\(height)"]
            )
        }
        let pixelFormatPreflightSummary = try validateLowLatencyPixelFormatPreflight(
            inputPixelFormat: inputPixelFormat,
            configuration: configuration
        )

        let cachedResources: LowLatencyFrameInterpolationResources?
        let existingResources: LowLatencyFrameInterpolationResources?
        stateLock.lock()
        cachedResources = activeLowLatencyResources
        if let cachedResources,
           cachedResources.sourceWidth == width,
           cachedResources.sourceHeight == height {
            stateLock.unlock()
            if !didLogLowLatencySessionReuse {
                didLogLowLatencySessionReuse = true
                streamLog("[StreamView][SBR \(rendererDebugID)] reusing low-latency frame interpolation session \(width)x\(height) -> \(outputWidth)x\(outputHeight) spatialScale=\(requestedSpatialScale)x interpolatedFrames=\(configuration.numberOfInterpolatedFrames) target=\(displayTarget.width)x\(displayTarget.height)", force: true)
            }
            return cachedResources
        }
        existingResources = activeLowLatencyResources
        stateLock.unlock()

        if let existingResources {
            streamLog("[StreamView][SBR \(rendererDebugID)] querying low-latency frame interpolation source=\(width)x\(height) displayTarget=\(displayTarget.width)x\(displayTarget.height) output=\(outputWidth)x\(outputHeight) inputPixelFormat=\(pixelFormatDescription(inputPixelFormat)) deviceSupported=\(VTLowLatencyFrameInterpolationConfiguration.isSupported) configuration=scale\(requestedSpatialScale)x", force: true)
            streamLog("[StreamView][SBR \(rendererDebugID)] Recreating low-latency frame interpolation session from \(existingResources.sourceWidth)x\(existingResources.sourceHeight) -> \(width)x\(height) spatialScale=\(requestedSpatialScale)x", force: true)
        } else {
            streamLog("[StreamView][SBR \(rendererDebugID)] querying low-latency frame interpolation source=\(width)x\(height) displayTarget=\(displayTarget.width)x\(displayTarget.height) output=\(outputWidth)x\(outputHeight) inputPixelFormat=\(pixelFormatDescription(inputPixelFormat)) deviceSupported=\(VTLowLatencyFrameInterpolationConfiguration.isSupported) configuration=scale\(requestedSpatialScale)x", force: true)
            streamLog("[StreamView][SBR \(rendererDebugID)] Starting low-latency frame interpolation session \(width)x\(height) -> \(outputWidth)x\(outputHeight) spatialScale=\(requestedSpatialScale)x interpolatedFrames=\(configuration.numberOfInterpolatedFrames) target=\(displayTarget.width)x\(displayTarget.height)", force: true)
        }
        streamLog("[StreamView][SBR \(rendererDebugID)] LLFI pixel-format preflight: \(pixelFormatPreflightSummary)", force: true)
        if configuration.spatialScaleFactor != requestedSpatialScale {
            let msg = "LLFI unsupported: requestedSpatialScale=\(requestedSpatialScale)x resolvedSpatialScale=\(configuration.spatialScaleFactor)x"
            streamLog("[StreamView][SBR \(rendererDebugID)] \(msg)", force: true)
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
        if configuration.numberOfInterpolatedFrames < 1 {
            let msg = "LLFI unsupported: requestedSpatialScale=\(requestedSpatialScale)x resolvedSpatialScale=\(configuration.spatialScaleFactor)x requestedInterpolatedFrames>=1 resolvedInterpolatedFrames=\(configuration.numberOfInterpolatedFrames)"
            streamLog("[StreamView][SBR \(rendererDebugID)] \(msg)", force: true)
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
        if outputWidth > displayTarget.width || outputHeight > displayTarget.height {
            let msg = "LLFI output \(outputWidth)x\(outputHeight) exceeds display target \(displayTarget.width)x\(displayTarget.height)"
            streamLog("[StreamView][SBR \(rendererDebugID)] \(msg)", force: true)
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
        streamLog("[StreamView][SBR \(rendererDebugID)] LLFI configuration summary: \(lowLatencyConfigurationSummary(configuration))", force: true)

        let processor = VTFrameProcessor()
        do {
            try processor.startSession(configuration: configuration)
        } catch {
            let errorDetails = lowLatencyErrorDetails(error)
            streamLog("[StreamView][SBR \(rendererDebugID)] LLFI startSession failed: \(errorDetails)", force: true)
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: (error as NSError).code,
                userInfo: [
                    NSLocalizedDescriptionKey: "startSession failed: \(errorDetails)",
                    NSUnderlyingErrorKey: error as NSError
                ]
            )
        }

        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let resolvedSourceAttributes = try makeResolvedPixelBufferAttributes(
            baseAttributes: configuration.sourcePixelBufferAttributes,
            width: width,
            height: height,
            pixelFormat: sourcePixelFormat,
            label: "source"
        )
        var sourcePool: CVPixelBufferPool?
        let sourcePoolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            resolvedSourceAttributes,
            &sourcePool
        )
        guard sourcePoolStatus == kCVReturnSuccess, let sourcePool else {
            processor.endSession()
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: Int(sourcePoolStatus),
                userInfo: [NSLocalizedDescriptionKey: "source pool creation failed: \(sourcePoolStatus)"]
            )
        }
        if let resolvedSourceAttributesDictionary = resolvedSourceAttributes as? [String: Any] {
            streamLog("[StreamView][SBR \(rendererDebugID)] LLFI resolved source attributes: \(lowLatencyAttributeSummary(resolvedSourceAttributesDictionary))", force: true)
        }

        let destinationPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let resolvedDestinationAttributes = try makeResolvedPixelBufferAttributes(
            baseAttributes: configuration.destinationPixelBufferAttributes,
            width: outputWidth,
            height: outputHeight,
            pixelFormat: destinationPixelFormat,
            label: "destination"
        )
        var destinationPool: CVPixelBufferPool?
        let destinationPoolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            resolvedDestinationAttributes,
            &destinationPool
        )
        guard destinationPoolStatus == kCVReturnSuccess, let destinationPool else {
            processor.endSession()
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: Int(destinationPoolStatus),
                userInfo: [NSLocalizedDescriptionKey: "destination pool creation failed: \(destinationPoolStatus)"]
            )
        }
        if let resolvedDestinationAttributesDictionary = resolvedDestinationAttributes as? [String: Any] {
            streamLog("[StreamView][SBR \(rendererDebugID)] LLFI resolved destination attributes: \(lowLatencyAttributeSummary(resolvedDestinationAttributesDictionary))", force: true)
        }

        var pixelTransferSession: VTPixelTransferSession?
        let pixelTransferStatus = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &pixelTransferSession)
        guard pixelTransferStatus == noErr, let pixelTransferSession else {
            processor.endSession()
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: Int(pixelTransferStatus),
                userInfo: [NSLocalizedDescriptionKey: "pixel transfer session creation failed: \(pixelTransferStatus)"]
            )
        }

        let resources = LowLatencyFrameInterpolationResources(
            sourceWidth: width,
            sourceHeight: height,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            configuration: configuration,
            processor: processor,
            sourcePool: sourcePool,
            destinationPool: destinationPool,
            pixelTransferSession: pixelTransferSession
        )
        stateLock.lock()
        currentLowLatencyGeneration &+= 1
        activeLowLatencyResources = resources
        stateLock.unlock()
        didLogLowLatencySessionReuse = false
        updateLowLatencyStatus("starting", inputWidth: width, inputHeight: height, outputWidth: outputWidth, outputHeight: outputHeight)
        return resources
    }

    @available(tvOS 26.0, *)
    func handleLowLatencyFrameInterpolationSuccess(
        expectedGeneration: UInt64,
        previousSourceRoute: LowLatencySourceRoute,
        currentSourceRoute: LowLatencySourceRoute,
        previousPixelBuffer: CVPixelBuffer,
        currentPixelBuffer: CVPixelBuffer,
        interpolatedPixelBuffer: CVPixelBuffer,
        currentPresentationTimeStamp: CMTime,
        interpolatedPresentationTimeStamp: CMTime,
        inputWidth: Int,
        inputHeight: Int,
        outputWidth: Int,
        outputHeight: Int
    ) {
        let shouldDisplayCurrentFrame: Bool
        let shouldPromoteDisplay: Bool
        let nextPair: (previousPixelBuffer: CVPixelBuffer, previousPTS: CMTime, currentPixelBuffer: CVPixelBuffer, currentPTS: CMTime, expectedGeneration: UInt64)?
        stateLock.lock()
        shouldDisplayCurrentFrame = currentLowLatencyGeneration == expectedGeneration
        shouldPromoteDisplay = shouldDisplayCurrentFrame && !lowLatencyDisplayActivated
        if shouldPromoteDisplay {
            lowLatencyDisplayActivated = true
        }
        if lowLatencyProcessingInFlight, lowLatencyProcessingGeneration == expectedGeneration {
            lowLatencyProcessingInFlight = false
            lowLatencyProcessingGeneration = 0
        }
        if shouldDisplayCurrentFrame,
           let queuedPixelBuffer = pendingLLFIPixelBuffer,
           let queuedPTS = pendingLLFIPresentationTimeStamp,
           let nextPreviousPixelBuffer = previousLLFIPixelBuffer,
           let nextPreviousPTS = previousLLFIPresentationTimeStamp {
            pendingLLFIPixelBuffer = nil
            pendingLLFIPresentationTimeStamp = nil
            previousLLFIPixelBuffer = queuedPixelBuffer
            previousLLFIPresentationTimeStamp = queuedPTS
            lowLatencyProcessingInFlight = true
            lowLatencyProcessingGeneration = currentLowLatencyGeneration
            nextPair = (
                previousPixelBuffer: nextPreviousPixelBuffer,
                previousPTS: nextPreviousPTS,
                currentPixelBuffer: queuedPixelBuffer,
                currentPTS: queuedPTS,
                expectedGeneration: lowLatencyProcessingGeneration
            )
        } else {
            nextPair = nil
        }
        stateLock.unlock()

        guard shouldDisplayCurrentFrame else {
            if let nextPair {
                guard let activeLowLatencyResources else { return }
                processLowLatencyFrameInterpolation(
                    previousPixelBuffer: nextPair.previousPixelBuffer,
                    previousPresentationTimeStamp: nextPair.previousPTS,
                    currentPixelBuffer: nextPair.currentPixelBuffer,
                    currentPresentationTimeStamp: nextPair.currentPTS,
                    resources: activeLowLatencyResources,
                    expectedGeneration: nextPair.expectedGeneration
                )
            }
            return
        }

        copyDisplayAttachments(from: currentPixelBuffer, to: interpolatedPixelBuffer)

        if !didLogFirstLLFIFrame {
            didLogFirstLLFIFrame = true
            let sourcePixelFormat = pixelFormatDescription(CVPixelBufferGetPixelFormatType(previousPixelBuffer))
            let outputPixelFormat = pixelFormatDescription(CVPixelBufferGetPixelFormatType(interpolatedPixelBuffer))
            streamLog("[StreamView] Low-latency frame interpolation first processed pair \(inputWidth)x\(inputHeight) -> \(outputWidth)x\(outputHeight) srcPF=\(sourcePixelFormat) dstPF=\(outputPixelFormat) prevRoute=\(previousSourceRoute.rawValue) currRoute=\(currentSourceRoute.rawValue)", force: true)
            streamLog("[StreamView] Low-latency frame interpolation first processed frame planes prev=\(pixelPlaneSummary(previousPixelBuffer)) curr=\(pixelPlaneSummary(currentPixelBuffer)) interpolated=\(pixelPlaneSummary(interpolatedPixelBuffer))", force: true)
        }

        updateLowLatencyStatus("active", inputWidth: inputWidth, inputHeight: inputHeight, outputWidth: outputWidth, outputHeight: outputHeight)

        if shouldPromoteDisplay {
            clearPendingPlainSampleBuffers()
            flushDisplayLayer(removingDisplayedImage: false)
            reportCandidateReadyIfNeeded(.vtFrameInterpolation)
            streamLog("[StreamView][SBR \(rendererDebugID)] LLFI first successful output ready; promoting processed video path", force: true)
            if let nextPair {
                guard let activeLowLatencyResources else {
                    activateLowLatencyFallback(reason: "active low-latency session missing during promotion", failedStatus: "failed")
                    return
                }
                processLowLatencyFrameInterpolation(
                    previousPixelBuffer: nextPair.previousPixelBuffer,
                    previousPresentationTimeStamp: nextPair.previousPTS,
                    currentPixelBuffer: nextPair.currentPixelBuffer,
                    currentPresentationTimeStamp: nextPair.currentPTS,
                    resources: activeLowLatencyResources,
                    expectedGeneration: nextPair.expectedGeneration
                )
            }
            return
        }

        guard let interpolatedSampleBuffer = makeSampleBuffer(from: interpolatedPixelBuffer, presentationTimeStamp: interpolatedPresentationTimeStamp),
              let currentSampleBuffer = makeSampleBuffer(from: currentPixelBuffer, presentationTimeStamp: currentPresentationTimeStamp) else {
            activateLowLatencyFallback(reason: "processed sample buffer creation failed", failedStatus: "failed")
            return
        }
        enqueueSampleBuffer(interpolatedSampleBuffer)
        enqueueSampleBuffer(currentSampleBuffer)
        emitTelemetryIfNeeded(force: true)

        if let nextPair {
            guard let activeLowLatencyResources else {
                activateLowLatencyFallback(reason: "active low-latency session missing during continuation", failedStatus: "failed")
                return
            }
            processLowLatencyFrameInterpolation(
                previousPixelBuffer: nextPair.previousPixelBuffer,
                previousPresentationTimeStamp: nextPair.previousPTS,
                currentPixelBuffer: nextPair.currentPixelBuffer,
                currentPresentationTimeStamp: nextPair.currentPTS,
                resources: activeLowLatencyResources,
                expectedGeneration: nextPair.expectedGeneration
            )
        }
    }

    @available(tvOS 26.0, *)
    func handleLowLatencyFrameInterpolationFailure(expectedGeneration: UInt64, reason: String) {
        let isCurrentGeneration: Bool
        stateLock.lock()
        isCurrentGeneration = currentLowLatencyGeneration == expectedGeneration
        if lowLatencyProcessingInFlight, lowLatencyProcessingGeneration == expectedGeneration {
            lowLatencyProcessingInFlight = false
            lowLatencyProcessingGeneration = 0
        }
        stateLock.unlock()

        guard isCurrentGeneration else { return }

        activateLowLatencyFallback(reason: reason, failedStatus: "failed")
    }
}
#endif

#endif
