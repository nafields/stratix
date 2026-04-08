// StreamingConfig.swift
// Defines streaming config for the Streaming surface.
//

import Foundation

public enum StreamKind: String, Sendable {
    case cloud
    case home
}

public enum StreamResolutionMode: String, CaseIterable, Sendable, Codable {
    case auto
    case p720
    case p1080
    case p1440
    case p1080HQ

    public var osName: String {
        switch self {
        case .auto, .p720: return "android"
        case .p1080: return "windows"
        case .p1440: return "tizen"
        case .p1080HQ: return "tizen"
        }
    }

    public var displayWidth: Int {
        switch self {
        case .auto, .p720: return 1280
        case .p1080: return 1920
        case .p1440: return 2560
        case .p1080HQ: return 3840
        }
    }

    public var displayHeight: Int {
        switch self {
        case .auto, .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .p1080HQ: return 2160
        }
    }
}

public enum StreamResolutionProfileId: String, CaseIterable, Sendable, Codable {
    case p720
    case p1080
    case p1440
    case p1080HQ
}

public enum UpscalingFloorBehavior: String, CaseIterable, Sendable, Codable {
    case sampleFloor
    case metalFloor

    public var label: String {
        switch self {
        case .sampleFloor:
            return "Sample Floor"
        case .metalFloor:
            return "Metal Floor"
        }
    }
}

public enum RendererModePreference: String, CaseIterable, Sendable, Codable {
    case auto
    case sampleBuffer
    case metalCAS
}

public struct StreamDimensions: Sendable, Equatable, Codable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum HUDPosition: String, CaseIterable, Sendable {
    case topRight
    case topLeft
    case bottomLeft
    case bottomRight

    public var isTop: Bool { self == .topRight || self == .topLeft }
    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
}

public struct StreamPreferences: Sendable, Equatable {
    public var resolution: StreamResolutionMode = .p1080
    public var locale: String = "en-US"
    public var preferIPv6: Bool = false
    public var preferredRegionId: String? = nil
    public var fallbackRegionNames: [String] = []
    /// Optional explicit client profile osName override sent to xCloud ("android", "windows", "tizen").
    /// nil means derive from `resolution`.
    public var osNameOverride: String? = nil

    public init() {}
}

public struct CGSizeValue: Codable, Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct XCloudDeviceProfile: Sendable, Equatable {
    public let clientAppId: String
    public let clientAppType: String
    public let clientAppVersion: String
    public let platformName: String
    public let osName: String
    public let locale: String
    public let width: Int
    public let height: Int

    public init(
        clientAppId: String = "Microsoft.GamingApp",
        clientAppType: String = "native",
        clientAppVersion: String = "0.0.0",
        platformName: String = "tvos",
        osName: String = "tvos",
        locale: String = "en-US",
        width: Int = 1920,
        height: Int = 1080
    ) {
        self.clientAppId = clientAppId
        self.clientAppType = clientAppType
        self.clientAppVersion = clientAppVersion
        self.platformName = platformName
        self.osName = osName
        self.locale = locale
        self.width = width
        self.height = height
    }
}

public struct StreamingConfig: Sendable, Equatable {
    public let preferredVideoCodecOrder: [VideoCodecPreference]
    /// SDP codec name to prioritize ("H264", "VP9", "VP8", "H265"). nil = keep default H264 ordering.
    public let preferredSdpCodec: String?
    public let maxVideoBitrateKbps: Int?
    public let maxAudioBitrateKbps: Int?
    public let stereoAudioEnabled: Bool
    public let keyframeRequestIntervalSeconds: Int?
    public let videoDimensionsHint: CGSizeValue
    public let preferredFrameRate: Int
    public let lowLatencyModeEnabled: Bool
    public let enableChatChannel: Bool
    /// Color range hint to send to the server ("Auto", "Limited", "Full"). nil = no hint.
    public let preferredColorRange: String?
    public let resolutionProfileId: StreamResolutionProfileId
    public let upscalingEnabled: Bool
    public let messageChannelDimensions: StreamDimensions
    /// Emits the fully-processed local SDP offer in startup logs for diagnostics.
    public let logLocalSDPOffer: Bool
    /// Optional `a=max-fr:` hint injected into local video SDP.
    public let requestedVideoMaxFrameRate: Int?
    /// Optional H.264 fallback profile-level-id override for local SDP fmtp lines.
    public let h264FallbackProfileLevelId: String?

    public init(
        preferredVideoCodecOrder: [VideoCodecPreference] = [.h264High, .h264Main, .h264Baseline, .vp9, .vp8, .ulpfec, .flexfec],
        preferredSdpCodec: String? = nil,
        maxVideoBitrateKbps: Int? = nil,
        maxAudioBitrateKbps: Int? = nil,
        stereoAudioEnabled: Bool = true,
        keyframeRequestIntervalSeconds: Int? = 5,
        videoDimensionsHint: CGSizeValue = .init(width: 1920, height: 1080),
        preferredFrameRate: Int = 60,
        lowLatencyModeEnabled: Bool = true,
        enableChatChannel: Bool = false,
        preferredColorRange: String? = nil,
        resolutionProfileId: StreamResolutionProfileId = .p1080,
        upscalingEnabled: Bool = true,
        messageChannelDimensions: StreamDimensions = .init(width: 1920, height: 1080),
        logLocalSDPOffer: Bool = false,
        requestedVideoMaxFrameRate: Int? = nil,
        h264FallbackProfileLevelId: String? = nil
    ) {
        self.preferredVideoCodecOrder = preferredVideoCodecOrder
        self.preferredSdpCodec = preferredSdpCodec
        self.maxVideoBitrateKbps = maxVideoBitrateKbps
        self.maxAudioBitrateKbps = maxAudioBitrateKbps
        self.stereoAudioEnabled = stereoAudioEnabled
        self.keyframeRequestIntervalSeconds = keyframeRequestIntervalSeconds
        self.videoDimensionsHint = videoDimensionsHint
        self.preferredFrameRate = preferredFrameRate
        self.lowLatencyModeEnabled = lowLatencyModeEnabled
        self.enableChatChannel = enableChatChannel
        self.preferredColorRange = preferredColorRange
        self.resolutionProfileId = resolutionProfileId
        self.upscalingEnabled = upscalingEnabled
        self.messageChannelDimensions = messageChannelDimensions
        self.logLocalSDPOffer = logLocalSDPOffer
        self.requestedVideoMaxFrameRate = requestedVideoMaxFrameRate
        self.h264FallbackProfileLevelId = h264FallbackProfileLevelId
    }
}
