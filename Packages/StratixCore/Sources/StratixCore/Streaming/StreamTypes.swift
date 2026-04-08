// StreamTypes.swift
// Defines stream types for the Streaming surface.
//

import Foundation
import StratixModels
import StreamingCore

public enum StreamUICommand: Sendable, Equatable {
    case toggleOverlay
    case disconnect
    case toggleStatsHUD
}

public enum StreamRuntimePhase: Sendable, Equatable {
    case shellActive
    case preparingStream
    case streaming
    case restoringShell
}

public enum StreamRuntimeContext: Sendable, Equatable {
    case cloud(titleId: TitleID)
    case home(consoleId: String)
}

public enum StreamLaunchTarget: Sendable, Equatable {
    case cloud(TitleID)
    case home(consoleId: String)

    var targetId: String {
        switch self {
        case .cloud(let titleId):
            return titleId.rawValue
        case .home(let consoleId):
            return consoleId
        }
    }

    var titleId: TitleID? {
        switch self {
        case .cloud(let titleId):
            return titleId
        case .home:
            return nil
        }
    }

    var runtimeContext: StreamRuntimeContext {
        switch self {
        case .cloud(let titleId):
            return .cloud(titleId: titleId)
        case .home(let consoleId):
            return .home(consoleId: consoleId)
        }
    }
}

public enum StreamSessionAttachmentState: Sendable, Equatable {
    case detached
    case attaching
    case attached
}

public enum StreamReconnectSuppressionReason: Sendable, Equatable {
    case autoReconnectDisabled
    case attemptsExhausted
    case missingLaunchContext
    case userInitiatedDisconnect
    case serverInitiatedDisconnect
    case reconnectTransition
}

public enum StreamReconnectTrigger: Sendable, Equatable {
    case failed
    case disconnected(StreamingDisconnectIntent)
}

public enum StreamOverlayTrigger: Sendable, Equatable {
    case userToggle
    case explicitDismiss
    case explicitExit
    case reconnect
    case automatic
}

public struct StreamOverlayVisibilityChangeContext: Sendable, Equatable {
    let oldVisible: Bool
    let newVisible: Bool
    let hasStreamingSession: Bool
    let disconnectArmed: Bool
    let trigger: StreamOverlayTrigger
}

public struct StreamOverlayInputDecision: Sendable, Equatable {
    let injectNeutralFrame: Bool
    let injectPauseMenuTap: Bool
}

extension StreamRuntimeContext {
    var performanceLabel: String {
        switch self {
        case .cloud(let titleId):
            return "cloud:\(titleId.rawValue)"
        case .home(let consoleId):
            return "home:\(consoleId)"
        }
    }
}
