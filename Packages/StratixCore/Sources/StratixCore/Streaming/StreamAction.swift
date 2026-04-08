// StreamAction.swift
// Defines stream action for the Streaming surface.
//

import Foundation
import StratixModels
import StreamingCore

enum StreamAction: Sendable, Equatable {
    case homeLaunchRequested(consoleId: String)
    case cloudLaunchRequested(TitleID)
    case reconnectingSet(Bool)
    case reconnectCompleted
    case reconnectStateReset
    case reconnectScheduled(attempt: Int, trigger: StreamReconnectTrigger)
    case reconnectSuppressed(StreamReconnectSuppressionReason)
    case streamingSessionSet((any StreamingSessionFacade)?)
    case sessionAttachmentStateSet(StreamSessionAttachmentState)
    case overlayVisibilityChanged(Bool, trigger: StreamOverlayTrigger)
    case achievementSnapshotSet(TitleAchievementSnapshot?)
    case achievementErrorSet(String?)
    case launchHeroURLSet(URL?)
    case runtimePhaseSet(StreamRuntimePhase)
    case shellRestoredAfterExitSet(Bool)
    case runtimeContextSet(StreamRuntimeContext?)
    case activeLaunchTargetSet(StreamLaunchTarget?)
    case streamDisconnected(StreamingDisconnectIntent)
    case streamStartFailed(String)
    case signedOutReset

    static func == (lhs: StreamAction, rhs: StreamAction) -> Bool {
        switch (lhs, rhs) {
        case (.homeLaunchRequested(let lhsValue), .homeLaunchRequested(let rhsValue)):
            lhsValue == rhsValue
        case (.cloudLaunchRequested(let lhsValue), .cloudLaunchRequested(let rhsValue)):
            lhsValue == rhsValue
        case (.reconnectingSet(let lhsValue), .reconnectingSet(let rhsValue)):
            lhsValue == rhsValue
        case (.reconnectCompleted, .reconnectCompleted):
            true
        case (.reconnectStateReset, .reconnectStateReset):
            true
        case (.reconnectScheduled(let lhsAttempt, let lhsTrigger), .reconnectScheduled(let rhsAttempt, let rhsTrigger)):
            lhsAttempt == rhsAttempt && lhsTrigger == rhsTrigger
        case (.reconnectSuppressed(let lhsValue), .reconnectSuppressed(let rhsValue)):
            lhsValue == rhsValue
        case (.streamingSessionSet(let lhsValue), .streamingSessionSet(let rhsValue)):
            lhsValue.map(ObjectIdentifier.init) == rhsValue.map(ObjectIdentifier.init)
        case (.sessionAttachmentStateSet(let lhsValue), .sessionAttachmentStateSet(let rhsValue)):
            lhsValue == rhsValue
        case (.overlayVisibilityChanged(let lhsValue, let lhsTrigger), .overlayVisibilityChanged(let rhsValue, let rhsTrigger)):
            lhsValue == rhsValue && lhsTrigger == rhsTrigger
        case (.achievementSnapshotSet(let lhsValue), .achievementSnapshotSet(let rhsValue)):
            lhsValue == rhsValue
        case (.achievementErrorSet(let lhsValue), .achievementErrorSet(let rhsValue)):
            lhsValue == rhsValue
        case (.launchHeroURLSet(let lhsValue), .launchHeroURLSet(let rhsValue)):
            lhsValue == rhsValue
        case (.runtimePhaseSet(let lhsValue), .runtimePhaseSet(let rhsValue)):
            lhsValue == rhsValue
        case (.shellRestoredAfterExitSet(let lhsValue), .shellRestoredAfterExitSet(let rhsValue)):
            lhsValue == rhsValue
        case (.runtimeContextSet(let lhsValue), .runtimeContextSet(let rhsValue)):
            lhsValue == rhsValue
        case (.activeLaunchTargetSet(let lhsValue), .activeLaunchTargetSet(let rhsValue)):
            lhsValue == rhsValue
        case (.streamDisconnected(let lhsValue), .streamDisconnected(let rhsValue)):
            lhsValue == rhsValue
        case (.streamStartFailed(let lhsValue), .streamStartFailed(let rhsValue)):
            lhsValue == rhsValue
        case (.signedOutReset, .signedOutReset):
            true
        default:
            false
        }
    }
}
