// StreamState.swift
// Defines the stream state.
//

import Foundation
import StratixModels
import StreamingCore

public struct StreamState: Sendable, Equatable {
    public var isReconnecting: Bool
    public var streamingSession: (any StreamingSessionFacade)?
    public var sessionAttachmentState: StreamSessionAttachmentState
    public var isStreamOverlayVisible: Bool
    public var currentStreamAchievementSnapshot: TitleAchievementSnapshot?
    public var lastStreamAchievementError: String?
    public var launchHeroURL: URL?
    public var runtimePhase: StreamRuntimePhase
    public var shellRestoredAfterStreamExit: Bool
    public var activeRuntimeContext: StreamRuntimeContext?
    public var activeLaunchTarget: StreamLaunchTarget?
    public var lastDisconnectIntent: StreamingDisconnectIntent?
    public var reconnectAttemptCount: Int
    public var lastReconnectTrigger: StreamReconnectTrigger?
    public var lastReconnectSuppressionReason: StreamReconnectSuppressionReason?
    public var lastStreamStartFailure: String?

    public static func == (lhs: StreamState, rhs: StreamState) -> Bool {
        lhs.isReconnecting == rhs.isReconnecting &&
        lhs.streamingSession.map(ObjectIdentifier.init) == rhs.streamingSession.map(ObjectIdentifier.init) &&
        lhs.sessionAttachmentState == rhs.sessionAttachmentState &&
        lhs.isStreamOverlayVisible == rhs.isStreamOverlayVisible &&
        lhs.currentStreamAchievementSnapshot == rhs.currentStreamAchievementSnapshot &&
        lhs.lastStreamAchievementError == rhs.lastStreamAchievementError &&
        lhs.launchHeroURL == rhs.launchHeroURL &&
        lhs.runtimePhase == rhs.runtimePhase &&
        lhs.shellRestoredAfterStreamExit == rhs.shellRestoredAfterStreamExit &&
        lhs.activeRuntimeContext == rhs.activeRuntimeContext &&
        lhs.activeLaunchTarget == rhs.activeLaunchTarget &&
        lhs.lastDisconnectIntent == rhs.lastDisconnectIntent &&
        lhs.reconnectAttemptCount == rhs.reconnectAttemptCount &&
        lhs.lastReconnectTrigger == rhs.lastReconnectTrigger &&
        lhs.lastReconnectSuppressionReason == rhs.lastReconnectSuppressionReason &&
        lhs.lastStreamStartFailure == rhs.lastStreamStartFailure
    }
}

extension StreamState {
    public static let empty = StreamState(
        isReconnecting: false,
        streamingSession: nil,
        sessionAttachmentState: .detached,
        isStreamOverlayVisible: false,
        currentStreamAchievementSnapshot: nil,
        lastStreamAchievementError: nil,
        launchHeroURL: nil,
        runtimePhase: .shellActive,
        shellRestoredAfterStreamExit: false,
        activeRuntimeContext: nil,
        activeLaunchTarget: nil,
        lastDisconnectIntent: nil,
        reconnectAttemptCount: 0,
        lastReconnectTrigger: nil,
        lastReconnectSuppressionReason: nil,
        lastStreamStartFailure: nil
    )
}
