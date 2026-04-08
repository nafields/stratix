//
//  SampleBufferDisplayRendererLowLatencySupport.swift
//  Stratix
//
//  Shared low-latency VideoToolbox support for the sample-buffer renderer.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(AVFoundation)
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
#if canImport(VideoToolbox)
@preconcurrency import VideoToolbox
#endif
import UIKit

extension SampleBufferDisplayRenderer {
#if canImport(VideoToolbox) && !targetEnvironment(simulator)
    @available(tvOS 26.0, *)
    struct RetainedReferenceToken: Sendable {
        let address: UInt
    }

    @available(tvOS 26.0, *)
    static func makeRetainedReferenceToken(_ value: AnyObject) -> RetainedReferenceToken {
        RetainedReferenceToken(address: UInt(bitPattern: Unmanaged.passRetained(value).toOpaque()))
    }

    @available(tvOS 26.0, *)
    static func takeRetainedReference(_ token: RetainedReferenceToken) -> AnyObject {
        let pointer = UnsafeMutableRawPointer(bitPattern: token.address)!
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue()
    }

    @available(tvOS 26.0, *)
    final class LowLatencyFrameInterpolationResources {
        let sourceWidth: Int
        let sourceHeight: Int
        let outputWidth: Int
        let outputHeight: Int
        let configuration: VTLowLatencyFrameInterpolationConfiguration
        let processor: VTFrameProcessor
        let sourcePool: CVPixelBufferPool
        let destinationPool: CVPixelBufferPool
        let pixelTransferSession: VTPixelTransferSession

        init(
            sourceWidth: Int,
            sourceHeight: Int,
            outputWidth: Int,
            outputHeight: Int,
            configuration: VTLowLatencyFrameInterpolationConfiguration,
            processor: VTFrameProcessor,
            sourcePool: CVPixelBufferPool,
            destinationPool: CVPixelBufferPool,
            pixelTransferSession: VTPixelTransferSession
        ) {
            self.sourceWidth = sourceWidth
            self.sourceHeight = sourceHeight
            self.outputWidth = outputWidth
            self.outputHeight = outputHeight
            self.configuration = configuration
            self.processor = processor
            self.sourcePool = sourcePool
            self.destinationPool = destinationPool
            self.pixelTransferSession = pixelTransferSession
        }

        deinit {
            processor.endSession()
            VTPixelTransferSessionInvalidate(pixelTransferSession)
        }
    }

    @available(tvOS 26.0, *)
    final class LowLatencySuperResolutionResources {
        let sourceWidth: Int
        let sourceHeight: Int
        let outputWidth: Int
        let outputHeight: Int
        let scaleFactor: Float
        let configuration: VTLowLatencySuperResolutionScalerConfiguration
        let processor: VTFrameProcessor
        let sourcePool: CVPixelBufferPool
        let destinationPool: CVPixelBufferPool
        let pixelTransferSession: VTPixelTransferSession

        init(
            sourceWidth: Int,
            sourceHeight: Int,
            outputWidth: Int,
            outputHeight: Int,
            scaleFactor: Float,
            configuration: VTLowLatencySuperResolutionScalerConfiguration,
            processor: VTFrameProcessor,
            sourcePool: CVPixelBufferPool,
            destinationPool: CVPixelBufferPool,
            pixelTransferSession: VTPixelTransferSession
        ) {
            self.sourceWidth = sourceWidth
            self.sourceHeight = sourceHeight
            self.outputWidth = outputWidth
            self.outputHeight = outputHeight
            self.scaleFactor = scaleFactor
            self.configuration = configuration
            self.processor = processor
            self.sourcePool = sourcePool
            self.destinationPool = destinationPool
            self.pixelTransferSession = pixelTransferSession
        }

        deinit {
            processor.endSession()
            VTPixelTransferSessionInvalidate(pixelTransferSession)
        }
    }
#endif

    func resetLowLatencyFrameInterpolationState() {
        stateLock.lock()
        previousLLFIPixelBuffer = nil
        previousLLFIPresentationTimeStamp = nil
        pendingLLFIPixelBuffer = nil
        pendingLLFIPresentationTimeStamp = nil
        lowLatencyProcessingInFlight = false
        lowLatencyProcessingGeneration = 0
        currentLowLatencyGeneration &+= 1
        lowLatencyFallbackToPlainSampleBuffer = false
        lowLatencyDisplayActivated = false
        didLogFirstLLFIFrame = false
        didLogLowLatencySessionReuse = false
        didLogLowLatencySourceCopy = false
#if canImport(VideoToolbox) && !targetEnvironment(simulator)
        if #available(tvOS 26.0, *), let activeLowLatencyResources {
            _ = activeLowLatencyResources
            self.activeLowLatencyResources = nil
        }
#endif
        stateLock.unlock()
    }

    func resetLowLatencySuperResolutionState() {
        stateLock.lock()
        pendingLLSRPixelBuffer = nil
        pendingLLSRPresentationTimeStamp = nil
        llsrProcessingInFlight = false
        llsrProcessingGeneration = 0
        currentLLSRGeneration &+= 1
        llsrFallbackToPlainSampleBuffer = false
        llsrDisplayActivated = false
        didLogFirstLLSRFrame = false
        didLogLLSRSessionReuse = false
        didLogLLSRSourceCopy = false
#if canImport(VideoToolbox) && !targetEnvironment(simulator)
        if #available(tvOS 26.0, *), let activeLowLatencySuperResolutionResources {
            _ = activeLowLatencySuperResolutionResources
            self.activeLowLatencySuperResolutionResources = nil
        }
#endif
        stateLock.unlock()
    }

    func updateLowLatencyStatus(
        _ status: String?,
        inputWidth: Int?,
        inputHeight: Int?,
        outputWidth: Int?,
        outputHeight: Int?,
        lastError: String? = nil
    ) {
        stateLock.lock()
        processingStatus = status
        processingInputWidth = inputWidth
        processingInputHeight = inputHeight
        processingOutputWidth = outputWidth
        processingOutputHeight = outputHeight
        if let lastError {
            self.lastError = lastError
        }
        stateLock.unlock()
        emitTelemetryIfNeeded(force: true)
    }

    func updateDisplayTargetDimensions(
        width: Int?,
        height: Int?
    ) {
        stateLock.lock()
        displayTargetWidth = width
        displayTargetHeight = height
        stateLock.unlock()
    }

    func activateLowLatencyFallback(reason: String, failedStatus: String) {
        streamLog("[StreamView] Low-latency frame interpolation fallback: \(reason)", force: true)
        stateLock.lock()
        lowLatencyFallbackToPlainSampleBuffer = true
        framesFailed += 1
        processingStatus = failedStatus
        lastError = reason
        lowLatencyProcessingInFlight = false
        lowLatencyProcessingGeneration = 0
        currentLowLatencyGeneration &+= 1
        previousLLFIPixelBuffer = nil
        previousLLFIPresentationTimeStamp = nil
        pendingLLFIPixelBuffer = nil
        pendingLLFIPresentationTimeStamp = nil
        lowLatencyDisplayActivated = false
#if canImport(VideoToolbox) && !targetEnvironment(simulator)
        if #available(tvOS 26.0, *), let activeLowLatencyResources {
            _ = activeLowLatencyResources
            self.activeLowLatencyResources = nil
        }
#endif
        stateLock.unlock()
        reportCandidateFailureIfNeeded(.vtFrameInterpolation, reason: reason)
        emitTelemetryIfNeeded(force: true)
    }

#if canImport(VideoToolbox) && !targetEnvironment(simulator)
    @available(tvOS 26.0, *)
    func lowLatencyDisplayTargetDimensions() -> (width: Int, height: Int) {
        stateLock.lock()
        let cachedWidth = displayTargetWidth
        let cachedHeight = displayTargetHeight
        stateLock.unlock()
        if let cachedWidth, let cachedHeight, cachedWidth > 0, cachedHeight > 0 {
            return (cachedWidth, cachedHeight)
        }
        if let displayTarget = currentDisplayLayerDimensions() {
            return displayTarget
        }
        return (3840, 2160)
    }

    @available(tvOS 26.0, *)
    func lowLatencyPixelFormatListDescription(_ formats: [NSNumber]) -> String {
        guard !formats.isEmpty else { return "[]" }
        let labels = formats.map { pixelFormatDescription(OSType(truncating: $0)) }
        return "[" + labels.joined(separator: ", ") + "]"
    }

    @available(tvOS 26.0, *)
    func lowLatencyPixelFormatListDescription(_ formats: [OSType]) -> String {
        guard !formats.isEmpty else { return "[]" }
        let labels = formats.map { pixelFormatDescription($0) }
        return "[" + labels.joined(separator: ", ") + "]"
    }

    @available(tvOS 26.0, *)
    func lowLatencyDimensionDescription(_ dimensions: CMVideoDimensions?) -> String {
        guard let dimensions else { return "nil" }
        return "\(dimensions.width)x\(dimensions.height)"
    }

    @available(tvOS 26.0, *)
    func lowLatencyStaticDimensionConstraintSummary(width: Int, height: Int) -> String {
        let minimumDimensions = VTLowLatencyFrameInterpolationConfiguration.minimumDimensions
        let maximumDimensions = VTLowLatencyFrameInterpolationConfiguration.maximumDimensions
        let meetsMinimum = minimumDimensions.map { width >= Int($0.width) && height >= Int($0.height) } ?? true
        let meetsMaximum = maximumDimensions.map { width <= Int($0.width) && height <= Int($0.height) } ?? true
        return "minimumDimensions=\(lowLatencyDimensionDescription(minimumDimensions)) maximumDimensions=\(lowLatencyDimensionDescription(maximumDimensions)) withinStaticLimits=\(meetsMinimum && meetsMaximum)"
    }

    @available(tvOS 26.0, *)
    func lowLatencyRequiredPixelFormat(from attributes: [String: Any]) -> OSType? {
        guard let pixelFormatNumber = attributes[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber else {
            return nil
        }
        return OSType(truncating: pixelFormatNumber)
    }

    @available(tvOS 26.0, *)
    func lowLatencyPixelFormatPreflightSummary(
        inputPixelFormat: OSType,
        configuration: VTLowLatencyFrameInterpolationConfiguration
    ) -> String {
        let supportedPixelFormats = configuration.supportedPixelFormats
        let sourcePixelFormat = lowLatencyRequiredPixelFormat(from: configuration.sourcePixelBufferAttributes) ?? inputPixelFormat
        let destinationPixelFormat = lowLatencyRequiredPixelFormat(from: configuration.destinationPixelBufferAttributes) ?? sourcePixelFormat
        let inputSupported = supportedPixelFormats.contains(inputPixelFormat)
        let sourceSupported = supportedPixelFormats.contains(sourcePixelFormat)
        let destinationSupported = supportedPixelFormats.contains(destinationPixelFormat)
        let route = inputPixelFormat == sourcePixelFormat ? "direct" : "copy"
        return "frameSupportedPixelFormats=unavailable-in-swift supportedPixelFormats=\(lowLatencyPixelFormatListDescription(supportedPixelFormats)) input=\(pixelFormatDescription(inputPixelFormat)) source=\(pixelFormatDescription(sourcePixelFormat)) destination=\(pixelFormatDescription(destinationPixelFormat)) route=\(route) inputSupported=\(inputSupported) sourceSupported=\(sourceSupported) destinationSupported=\(destinationSupported)"
    }

    @available(tvOS 26.0, *)
    func validateLowLatencyPixelFormatPreflight(
        inputPixelFormat: OSType,
        configuration: VTLowLatencyFrameInterpolationConfiguration
    ) throws -> String {
        let summary = lowLatencyPixelFormatPreflightSummary(inputPixelFormat: inputPixelFormat, configuration: configuration)
        let supportedPixelFormats = configuration.supportedPixelFormats
        guard !supportedPixelFormats.isEmpty else { return summary }

        let sourcePixelFormat = lowLatencyRequiredPixelFormat(from: configuration.sourcePixelBufferAttributes) ?? inputPixelFormat
        let destinationPixelFormat = lowLatencyRequiredPixelFormat(from: configuration.destinationPixelBufferAttributes) ?? sourcePixelFormat

        guard supportedPixelFormats.contains(sourcePixelFormat) else {
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "LLFI source pixel format preflight failed: \(summary)"]
            )
        }
        guard supportedPixelFormats.contains(destinationPixelFormat) else {
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "LLFI destination pixel format preflight failed: \(summary)"]
            )
        }

        return summary
    }

    @available(tvOS 26.0, *)
    func lowLatencyErrorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]

        if nsError.domain == VTFrameProcessorErrorDomain,
           let frameProcessorCode = VTFrameProcessorError.Code(rawValue: nsError.code) {
            parts.append("vtCode=\(String(describing: frameProcessorCode))")
        }

        parts.append("description=\(nsError.localizedDescription)")

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            parts.append("failureReason=\(failureReason)")
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            parts.append("recovery=\(recoverySuggestion)")
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying={domain=\(underlyingError.domain) code=\(underlyingError.code) description=\(underlyingError.localizedDescription)}")
        }

        let filteredUserInfo = nsError.userInfo
            .filter { key, _ in
                return key != NSLocalizedDescriptionKey
                    && key != NSLocalizedFailureReasonErrorKey
                    && key != NSLocalizedRecoverySuggestionErrorKey
                    && key != NSUnderlyingErrorKey
            }
            .map { key, value in
                "\(key)=\(value)"
            }
            .sorted()
        if !filteredUserInfo.isEmpty {
            parts.append("userInfo={\(filteredUserInfo.joined(separator: "; "))}")
        }

        return parts.joined(separator: " ")
    }

    @available(tvOS 26.0, *)
    func lowLatencyConfigurationSummary(_ configuration: VTLowLatencyFrameInterpolationConfiguration) -> String {
        "frame=\(configuration.frameWidth)x\(configuration.frameHeight) scale=\(configuration.spatialScaleFactor)x interpolatedFrames=\(configuration.numberOfInterpolatedFrames) constraints={\(lowLatencyStaticDimensionConstraintSummary(width: configuration.frameWidth, height: configuration.frameHeight))} frameSupportedPixelFormats=unavailable-in-swift supportedPixelFormats=\(lowLatencyPixelFormatListDescription(configuration.supportedPixelFormats)) sourceAttributes={\(lowLatencyAttributeSummary(configuration.sourcePixelBufferAttributes))} destinationAttributes={\(lowLatencyAttributeSummary(configuration.destinationPixelBufferAttributes))}"
    }

    @available(tvOS 26.0, *)
    func lowLatencyInitializationRetryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let clampedAttempt = max(1, min(attempt, 6))
        return UInt64(clampedAttempt) * 33_000_000
    }

    @available(tvOS 26.0, *)
    func lowLatencyInitializationRetryWindowSeconds() -> TimeInterval {
        30
    }

    @available(tvOS 26.0, *)
    func isLowLatencyInitializationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == VTFrameProcessorErrorDomain else {
            return nsError.localizedDescription == "Processor is not initialized"
        }
        if let code = VTFrameProcessorError.Code(rawValue: nsError.code),
           code == .sessionNotStarted || code == .initializationFailed {
            return true
        }
        return nsError.localizedDescription == "Processor is not initialized"
    }

    @available(tvOS 26.0, *)
    func canContinueLowLatencyFrameInterpolation(
        expectedGeneration: UInt64,
        resources: LowLatencyFrameInterpolationResources
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard currentLowLatencyGeneration == expectedGeneration else { return false }
        guard let activeLowLatencyResources else { return false }
        return activeLowLatencyResources === resources && !lowLatencyFallbackToPlainSampleBuffer
    }

    @available(tvOS 26.0, *)
    func makeResolvedPixelBufferAttributes(
        baseAttributes: [String: Any],
        width: Int,
        height: Int,
        pixelFormat: OSType?,
        label: String
    ) throws -> CFDictionary {
        var concreteAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        if let pixelFormat,
           baseAttributes[kCVPixelBufferPixelFormatTypeKey as String] == nil {
            concreteAttributes[kCVPixelBufferPixelFormatTypeKey as String] = pixelFormat
        }

        var resolvedAttributes: CFDictionary?
        let resolveStatus = CVPixelBufferCreateResolvedAttributesDictionary(
            kCFAllocatorDefault,
            [baseAttributes as CFDictionary, concreteAttributes as CFDictionary] as CFArray,
            &resolvedAttributes
        )
        guard resolveStatus == kCVReturnSuccess, let resolvedAttributes else {
            throw NSError(
                domain: "StreamView.LowLatencyFrameInterpolation",
                code: Int(resolveStatus),
                userInfo: [NSLocalizedDescriptionKey: "\(label) attribute resolution failed: \(resolveStatus)"]
            )
        }
        return resolvedAttributes
    }

    @available(tvOS 26.0, *)
    func lowLatencySourceBufferNeedsCopy(
        _ pixelBuffer: CVPixelBuffer,
        requiredAttributes: [String: Any]
    ) -> Bool {
        if let desiredPixelFormatNumber = requiredAttributes[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber {
            let desiredPixelFormat = OSType(truncating: desiredPixelFormatNumber)
            let actualPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
            if actualPixelFormat != desiredPixelFormat {
                return true
            }
        }

        guard let creationAttributes = CVPixelBufferCopyCreationAttributes(pixelBuffer) as? [String: Any] else {
            return true
        }

        let criticalKeys = [
            kCVPixelBufferExtendedPixelsLeftKey as String,
            kCVPixelBufferExtendedPixelsTopKey as String,
            kCVPixelBufferExtendedPixelsRightKey as String,
            kCVPixelBufferExtendedPixelsBottomKey as String
        ]

        for key in criticalKeys {
            if let desiredValue = requiredAttributes[key] as? Int {
                let receivedValue = (creationAttributes[key] as? Int) ?? 0
                if receivedValue != desiredValue {
                    return true
                }
            }
        }

        return false
    }
#endif
}

#endif
