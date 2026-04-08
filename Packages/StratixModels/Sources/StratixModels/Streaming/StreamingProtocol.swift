// StreamingProtocol.swift
// Defines streaming protocol for the Streaming surface.
//

import Foundation

public struct WaitTimeResponse: Codable, Sendable, Equatable {
    public let estimatedTotalWaitTimeInSeconds: Int?

    public init(estimatedTotalWaitTimeInSeconds: Int?) {
        self.estimatedTotalWaitTimeInSeconds = estimatedTotalWaitTimeInSeconds
    }
}

public struct StreamSessionStartResponse: Codable, Sendable, Equatable {
    public let sessionPath: String
    public let sessionId: String?
    public let state: String?

    public init(sessionPath: String, sessionId: String? = nil, state: String? = nil) {
        self.sessionPath = sessionPath
        self.sessionId = sessionId
        self.state = state
    }
}

public struct StreamStateResponse: Codable, Sendable, Equatable {
    public struct ErrorDetails: Codable, Sendable, Equatable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public let state: String
    public let errorDetails: ErrorDetails?

    public init(state: String, errorDetails: ErrorDetails? = nil) {
        self.state = state
        self.errorDetails = errorDetails
    }
}

public struct SdpExchangeResponse: Codable, Sendable, Equatable {
    public let sdp: String

    public init(sdp: String) {
        self.sdp = sdp
    }
}

public struct SessionDescription: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case offer
        case answer
    }

    public let type: Kind
    public let sdp: String

    public init(type: Kind, sdp: String) {
        self.type = type
        self.sdp = sdp
    }
}

public struct IceCandidatePayload: Codable, Sendable, Equatable {
    public let candidate: String
    public let sdpMLineIndex: Int
    public let sdpMid: String
    public let usernameFragment: String?

    public init(candidate: String, sdpMLineIndex: Int, sdpMid: String, usernameFragment: String? = nil) {
        self.candidate = candidate
        self.sdpMLineIndex = sdpMLineIndex
        self.sdpMid = sdpMid
        self.usernameFragment = usernameFragment
    }
}

public enum VideoCodecPreference: String, Sendable, Equatable, Codable {
    case h264High
    case h264Main
    case h264Baseline
    case vp9
    case vp8
    case ulpfec
    case flexfec
    case other
}

public struct CodecCapability: Sendable, Equatable {
    public let mimeType: String
    public let fmtp: String?

    public init(mimeType: String, fmtp: String?) {
        self.mimeType = mimeType
        self.fmtp = fmtp
    }
}

public enum PeerConnectionState: String, Sendable, Codable {
    case new
    case connecting
    case connected
    case disconnected
    case failed
    case closed
}

public enum DataChannelKind: String, Sendable, Codable, CaseIterable {
    case message
    case control
    case input
    case chat
}

public enum MediaTrackKind: String, Sendable, Codable {
    case audio
    case video
}

public struct ProtocolMessageEvent: Sendable, Equatable {
    public let target: String
    public let payload: String

    public init(target: String, payload: String) {
        self.target = target
        self.payload = payload
    }
}
