// StreamingRuntime.swift
// Defines streaming runtime for the Streaming surface.
//

import Foundation

/// Periodic snapshot of transport, audio, and renderer health for an active stream session.
public struct StreamingStatsSnapshot: Sendable, Equatable {
    public let timestamp: Date
    public let bitrateKbps: Int?
    public let framesPerSecond: Double?
    public let roundTripTimeMs: Double?
    public let jitterMs: Double?
    public let decodeTimeMs: Double?
    public let packetsLost: Int?
    public let framesLost: Int?
    public let audioJitterMs: Double?
    public let audioPacketsLost: Int?
    public let audioBitrateKbps: Int?
    public let audioJitterBufferDelayMs: Double?
    public let audioConcealedSamples: Int?
    public let audioTotalSamplesReceived: Int?
    public let activeRegion: String?
    public let negotiatedWidth: Int?
    public let negotiatedHeight: Int?
    public let controlPreferredWidth: Int?
    public let controlPreferredHeight: Int?
    public let messagePreferredWidth: Int?
    public let messagePreferredHeight: Int?
    public let rendererMode: String?
    public let inputFlushHz: Double?
    public let inputFlushJitterMs: Double?
    public let rendererFramesReceived: Int?
    public let rendererFramesDrawn: Int?
    public let rendererFramesDroppedByCoalescing: Int?
    public let rendererDrawQueueDepthMax: Int?
    public let rendererFramesFailed: Int?
    public let rendererProcessingStatus: String?
    public let rendererProcessingInputWidth: Int?
    public let rendererProcessingInputHeight: Int?
    public let rendererProcessingOutputWidth: Int?
    public let rendererProcessingOutputHeight: Int?
    public let renderLatencyMs: Double?
    public let rendererOutputFamily: String?
    public let rendererEligibleRungs: [String]
    public let rendererDeadRungs: [String]
    public let rendererLastError: String?

    public init(
        timestamp: Date = Date(),
        bitrateKbps: Int? = nil,
        framesPerSecond: Double? = nil,
        roundTripTimeMs: Double? = nil,
        jitterMs: Double? = nil,
        decodeTimeMs: Double? = nil,
        packetsLost: Int? = nil,
        framesLost: Int? = nil,
        audioJitterMs: Double? = nil,
        audioPacketsLost: Int? = nil,
        audioBitrateKbps: Int? = nil,
        audioJitterBufferDelayMs: Double? = nil,
        audioConcealedSamples: Int? = nil,
        audioTotalSamplesReceived: Int? = nil,
        activeRegion: String? = nil,
        negotiatedWidth: Int? = nil,
        negotiatedHeight: Int? = nil,
        controlPreferredWidth: Int? = nil,
        controlPreferredHeight: Int? = nil,
        messagePreferredWidth: Int? = nil,
        messagePreferredHeight: Int? = nil,
        rendererMode: String? = nil,
        inputFlushHz: Double? = nil,
        inputFlushJitterMs: Double? = nil,
        rendererFramesReceived: Int? = nil,
        rendererFramesDrawn: Int? = nil,
        rendererFramesDroppedByCoalescing: Int? = nil,
        rendererDrawQueueDepthMax: Int? = nil,
        rendererFramesFailed: Int? = nil,
        rendererProcessingStatus: String? = nil,
        rendererProcessingInputWidth: Int? = nil,
        rendererProcessingInputHeight: Int? = nil,
        rendererProcessingOutputWidth: Int? = nil,
        rendererProcessingOutputHeight: Int? = nil,
        renderLatencyMs: Double? = nil,
        rendererOutputFamily: String? = nil,
        rendererEligibleRungs: [String] = [],
        rendererDeadRungs: [String] = [],
        rendererLastError: String? = nil
    ) {
        self.timestamp = timestamp
        self.bitrateKbps = bitrateKbps
        self.framesPerSecond = framesPerSecond
        self.roundTripTimeMs = roundTripTimeMs
        self.jitterMs = jitterMs
        self.decodeTimeMs = decodeTimeMs
        self.packetsLost = packetsLost
        self.framesLost = framesLost
        self.audioJitterMs = audioJitterMs
        self.audioPacketsLost = audioPacketsLost
        self.audioBitrateKbps = audioBitrateKbps
        self.audioJitterBufferDelayMs = audioJitterBufferDelayMs
        self.audioConcealedSamples = audioConcealedSamples
        self.audioTotalSamplesReceived = audioTotalSamplesReceived
        self.activeRegion = activeRegion
        self.negotiatedWidth = negotiatedWidth
        self.negotiatedHeight = negotiatedHeight
        self.controlPreferredWidth = controlPreferredWidth
        self.controlPreferredHeight = controlPreferredHeight
        self.messagePreferredWidth = messagePreferredWidth
        self.messagePreferredHeight = messagePreferredHeight
        self.rendererMode = rendererMode
        self.inputFlushHz = inputFlushHz
        self.inputFlushJitterMs = inputFlushJitterMs
        self.rendererFramesReceived = rendererFramesReceived
        self.rendererFramesDrawn = rendererFramesDrawn
        self.rendererFramesDroppedByCoalescing = rendererFramesDroppedByCoalescing
        self.rendererDrawQueueDepthMax = rendererDrawQueueDepthMax
        self.rendererFramesFailed = rendererFramesFailed
        self.rendererProcessingStatus = rendererProcessingStatus
        self.rendererProcessingInputWidth = rendererProcessingInputWidth
        self.rendererProcessingInputHeight = rendererProcessingInputHeight
        self.rendererProcessingOutputWidth = rendererProcessingOutputWidth
        self.rendererProcessingOutputHeight = rendererProcessingOutputHeight
        self.renderLatencyMs = renderLatencyMs
        self.rendererOutputFamily = rendererOutputFamily
        self.rendererEligibleRungs = rendererEligibleRungs
        self.rendererDeadRungs = rendererDeadRungs
        self.rendererLastError = rendererLastError
    }
}

/// Typed stream failure surfaced across streaming, networking, and UI boundaries.
public struct StreamError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Buckets failures by the layer that surfaced them so recovery logic can branch on class.
    public enum Code: String, Sendable {
        case network
        case signaling
        case authentication
        case webrtc
        case protocolViolation
        case unsupported
        case notImplemented
        case cancelled
        case unknown
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code.rawValue): \(message)" }
}

/// High-level stream lifecycle used by controllers and views to coordinate launch progress.
public enum StreamLifecycleState: Sendable, Equatable {
    case idle
    case startingSession
    case provisioning
    case waitingForResources(estimatedWaitSeconds: Int?)
    case readyToConnect
    case connectingWebRTC
    case connected
    case disconnecting
    case disconnected
    case failed(StreamError)
}

/// Minimal UI-facing view state for the active stream route.
public struct StreamViewState: Sendable, Equatable {
    public let lifecycle: StreamLifecycleState
    public let sessionId: String?
    public let titleId: String?

    /// Couples the current lifecycle with optional session identifiers needed by stream UI.
    public init(lifecycle: StreamLifecycleState, sessionId: String? = nil, titleId: String? = nil) {
        self.lifecycle = lifecycle
        self.sessionId = sessionId
        self.titleId = titleId
    }
}

/// Client-side frame timing markers piggybacked on input packets for server diagnostics.
public struct FrameTimingMetadata: Sendable, Equatable {
    public let serverDataKey: UInt32
    public let firstFramePacketArrivalTimeMs: UInt32
    public let frameSubmittedTimeMs: UInt32
    public let frameDecodedTimeMs: UInt32
    public let frameRenderedTimeMs: UInt32

    public init(serverDataKey: UInt32, firstFramePacketArrivalTimeMs: UInt32, frameSubmittedTimeMs: UInt32, frameDecodedTimeMs: UInt32, frameRenderedTimeMs: UInt32) {
        self.serverDataKey = serverDataKey
        self.firstFramePacketArrivalTimeMs = firstFramePacketArrivalTimeMs
        self.frameSubmittedTimeMs = frameSubmittedTimeMs
        self.frameDecodedTimeMs = frameDecodedTimeMs
        self.frameRenderedTimeMs = frameRenderedTimeMs
    }
}
