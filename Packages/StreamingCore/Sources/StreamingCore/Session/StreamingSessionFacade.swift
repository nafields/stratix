// StreamingSessionFacade.swift
// Defines streaming session facade.
//

import Foundation
import StratixModels
import InputBridge

public enum StreamingDisconnectIntent: Sendable, Equatable {
    case reconnectable
    case userInitiated
    case serverInitiated
    case reconnectTransition
}

@MainActor
public protocol StreamingSessionFacade: AnyObject, Sendable {
    var lifecycle: StreamLifecycleState { get }
    var stats: StreamingStatsSnapshot { get }
    var disconnectIntent: StreamingDisconnectIntent { get }
    var inputQueueRef: InputQueue { get }
    var onLifecycleChange: (@MainActor (StreamLifecycleState) -> Void)? { get set }
    var onVideoTrack: ((AnyObject) -> Void)? { get set }

    func connect(type: StreamKind, targetId: String, msaUserToken: String?) async
    func setVibrationHandler(_ handler: @escaping (VibrationReport) -> Void)
    func setDiagnosticsPollingEnabled(_ enabled: Bool)
    func reportRendererDecodeFailure(_ details: String)
    func setGamepadConnectionState(index: Int, connected: Bool)
    func disconnect(reason: StreamingDisconnectIntent) async
}
