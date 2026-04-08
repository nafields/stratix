// StreamingSessionRuntime.swift
// Defines streaming session runtime.
//

import Foundation
import DiagnosticsKit
import StratixModels
import InputBridge
import os

struct StartupPayloadLogWindowState: Sendable {
    var isActive = true
    var deadline: Date?
    var didLogExpiry = false
}

/// Limits startup payload logging to the initial connection window so bring-up stays debuggable
/// without leaving verbose raw-payload logging enabled for the entire session.
final class StartupPayloadLogWindow: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: StartupPayloadLogWindowState())

    func reset() {
        state.withLock { $0 = StartupPayloadLogWindowState() }
    }

    func markFirstOutboundMessage(window: TimeInterval) -> Bool {
        state.withLock { state in
            guard state.isActive, state.deadline == nil else { return false }
            state.deadline = Date.now.addingTimeInterval(window)
            state.didLogExpiry = false
            return true
        }
    }

    func shouldLog() -> Bool {
        let (shouldLog, didExpire) = state.withLock { state in
            guard state.isActive else { return (false, false) }
            guard let deadline = state.deadline else { return (true, false) }
            if Date.now <= deadline {
                return (true, false)
            }
            state.isActive = false
            if !state.didLogExpiry {
                state.didLogExpiry = true
                return (false, true)
            }
            return (false, false)
        }
        if didExpire {
            streamLogger.info("Startup raw payload logging expired 30 seconds after first outbound message")
        }
        return shouldLog
    }
}

struct RetainedTrackToken: Sendable {
    let address: UInt
}

func makeRetainedTrackToken(_ track: AnyObject) -> RetainedTrackToken {
    RetainedTrackToken(address: UInt(bitPattern: Unmanaged.passRetained(track).toOpaque()))
}

func takeRetainedTrack(_ token: RetainedTrackToken) -> AnyObject {
    let pointer = UnsafeMutableRawPointer(bitPattern: token.address)!
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue()
}

func releaseRetainedTrack(_ token: RetainedTrackToken) {
    let pointer = UnsafeMutableRawPointer(bitPattern: token.address)!
    Unmanaged<AnyObject>.fromOpaque(pointer).release()
}

/// Mirrors the runtime-owned stream state that the main-actor session republishes to the app layer.
struct StreamingRuntimeSnapshot: Sendable, Equatable {
    var negotiatedDimensions: StreamDimensions?
    var controlPreferredDimensions: StreamDimensions
    var messagePreferredDimensions: StreamDimensions
    var inputFlushHz: Double?
    var inputFlushJitterMs: Double?
}

@MainActor
protocol StreamingRuntimeDelegate: AnyObject, Sendable {
    var lifecycle: StreamLifecycleState { get }
    func runtimeDidUpdateLifecycle(_ lifecycle: StreamLifecycleState)
    func runtimeDidUpdateSnapshot(_ snapshot: StreamingRuntimeSnapshot)
    func runtimeDidReceiveVideoTrack(_ track: AnyObject)
    func runtimeDidReceiveAudioTrack(_ track: AnyObject)
    func runtimeDidReceiveVibration(_ report: VibrationReport)
    func runtimeDidRequestDisconnect(_ intent: StreamingDisconnectIntent)
}

struct StreamingRuntimeDelegateState: Sendable {
    weak var delegate: (any StreamingRuntimeDelegate)?
}

final class StreamingRuntimeDelegateBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: StreamingRuntimeDelegateState())

    init(delegate: (any StreamingRuntimeDelegate)? = nil) {
        state.withLock { $0.delegate = delegate }
    }

    func currentDelegate() -> (any StreamingRuntimeDelegate)? {
        state.withLock { $0.delegate }
    }

    func setDelegate(_ delegate: (any StreamingRuntimeDelegate)?) {
        state.withLock { $0.delegate = delegate }
    }
}

/// Tracks the active callback generation so stale WebRTC callbacks can be ignored after reconnects.
final class StreamingRuntimeGenerationBox: Sendable {
    private let generationState = OSAllocatedUnfairLock(initialState: UInt64.zero)

    func current() -> UInt64 {
        generationState.withLock { $0 }
    }

    func set(_ generation: UInt64) {
        generationState.withLock { $0 = generation }
    }
}

@MainActor
extension StreamingSession: StreamingRuntimeDelegate {
    /// Forwards gamepad connectivity changes into the actor-isolated runtime without exposing
    /// the runtime actor directly to app callers.
    public func setGamepadConnectionState(index: Int = 0, connected: Bool) {
        Task {
            await model.runtime.setGamepadConnectionState(index: index, connected: connected)
        }
    }

    /// Starts a new session by resetting session-facing state and handing connection ownership
    /// to the runtime actor.
    public func connect(type: StreamKind, targetId: String, msaUserToken: String? = nil) async {
        guard lifecycle == .idle else { return }
        lifecycle = .startingSession
        disconnectIntent = .reconnectable
        model.resetForStreamStart()
        model.bridgeDelegate.setActiveGeneration(model.runtimeGenerationBox.current() &+ 1)
        await model.runtime.connect(type: type, targetId: targetId, msaUserToken: msaUserToken)
    }

    /// Tears down the active runtime session while keeping lifecycle and metrics sequencing
    /// consistent for user and runtime initiated disconnects.
    public func disconnect(reason: StreamingDisconnectIntent = .userInitiated) async {
        stopStatsPolling()
        disconnectIntent = reason
        StreamMetricsPipeline.shared.recordMilestone(
            .disconnectIntent,
            disconnectIntent: metricsDisconnectIntent(for: reason)
        )
        lifecycle = .disconnecting
        model.resetForStreamStop()
        model.bridgeDelegate.invalidateActiveGeneration()
        await model.runtime.disconnect()
        model.latestVideoTrack = nil
        model.latestAudioTrack = nil
        lifecycle = .disconnected
    }

    func runtimeDidUpdateLifecycle(_ lifecycle: StreamLifecycleState) {
        updateLifecycleFromRuntime(lifecycle)
    }

    func runtimeDidUpdateSnapshot(_ snapshot: StreamingRuntimeSnapshot) {
        guard model.runtimeSnapshot != snapshot else { return }
        model.runtimeSnapshot = snapshot
        republishCurrentStats()
    }

    func runtimeDidReceiveVibration(_ report: VibrationReport) {
        onVibration?(report)
    }

    /// Routes runtime-triggered disconnects back through the public disconnect path so teardown,
    /// metrics, and lifecycle updates stay consistent.
    func runtimeDidRequestDisconnect(_ intent: StreamingDisconnectIntent) {
        Task { [weak self] in
            await self?.disconnect(reason: intent)
        }
    }

    private func updateLifecycleFromRuntime(_ nextLifecycle: StreamLifecycleState) {
        guard lifecycle != nextLifecycle else { return }

        switch nextLifecycle {
        case .connected:
            StreamMetricsPipeline.shared.recordMilestone(.peerConnected)
            if model.metricsSupport.diagnosticsPollingEnabled {
                startStatsPolling()
            }
        case .failed, .disconnected:
            stopStatsPolling()
        default:
            break
        }

        lifecycle = nextLifecycle
    }

    private func metricsDisconnectIntent(
        for intent: StreamingDisconnectIntent
    ) -> StreamMetricsDisconnectIntent {
        switch intent {
        case .userInitiated:
            return .userInitiated
        case .reconnectable:
            return .reconnectable
        case .reconnectTransition:
            return .reconnectTransition
        case .serverInitiated:
            return .serverInitiated
        }
    }
}
