// StreamReducer.swift
// Defines stream reducer for the Streaming surface.
//

import Foundation

enum StreamReducer {
    static func reduce(
        state: StreamState,
        action: StreamAction
    ) -> StreamState {
        var next = state

        switch action {
        case .homeLaunchRequested(let consoleId):
            next.activeLaunchTarget = .home(consoleId: consoleId)
            next.lastDisconnectIntent = nil
            next.lastReconnectSuppressionReason = nil
            next.lastReconnectTrigger = nil
            next.lastStreamStartFailure = nil

        case .cloudLaunchRequested(let titleId):
            next.activeLaunchTarget = .cloud(titleId)
            next.lastDisconnectIntent = nil
            next.lastReconnectSuppressionReason = nil
            next.lastReconnectTrigger = nil
            next.lastStreamStartFailure = nil

        case .reconnectingSet(let value):
            next.isReconnecting = value

        case .reconnectCompleted:
            next.isReconnecting = false
            next.reconnectAttemptCount = 0
            next.lastDisconnectIntent = nil
            next.lastReconnectTrigger = nil
            next.lastReconnectSuppressionReason = nil

        case .reconnectStateReset:
            next.isReconnecting = false
            next.reconnectAttemptCount = 0
            next.lastDisconnectIntent = nil
            next.lastReconnectTrigger = nil
            next.lastReconnectSuppressionReason = nil

        case .reconnectScheduled(let attempt, let trigger):
            next.isReconnecting = true
            next.reconnectAttemptCount = attempt
            next.lastReconnectTrigger = trigger
            next.lastReconnectSuppressionReason = nil

        case .reconnectSuppressed(let reason):
            next.isReconnecting = false
            next.lastReconnectSuppressionReason = reason

        case .streamingSessionSet(let session):
            next.streamingSession = session

        case .sessionAttachmentStateSet(let attachmentState):
            next.sessionAttachmentState = attachmentState

        case .overlayVisibilityChanged(let visible, _):
            next.isStreamOverlayVisible = visible

        case .achievementSnapshotSet(let snapshot):
            next.currentStreamAchievementSnapshot = snapshot

        case .achievementErrorSet(let message):
            next.lastStreamAchievementError = message

        case .launchHeroURLSet(let url):
            next.launchHeroURL = url

        case .runtimePhaseSet(let phase):
            next.runtimePhase = phase

        case .shellRestoredAfterExitSet(let value):
            next.shellRestoredAfterStreamExit = value

        case .runtimeContextSet(let context):
            next.activeRuntimeContext = context

        case .activeLaunchTargetSet(let target):
            next.activeLaunchTarget = target

        case .streamDisconnected(let intent):
            next.lastDisconnectIntent = intent
            next.sessionAttachmentState = .detached

        case .streamStartFailed(let message):
            next.lastStreamStartFailure = message
            next.sessionAttachmentState = .detached

        case .signedOutReset:
            next = .empty
        }

        return next
    }
}
