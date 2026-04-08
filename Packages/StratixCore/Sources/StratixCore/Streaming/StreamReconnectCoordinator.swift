// StreamReconnectCoordinator.swift
// Defines the stream reconnect coordinator for the Streaming surface.
//

import Foundation
import DiagnosticsKit
import StreamingCore

struct StreamReconnectLauncher: Sendable {
    let disconnectCurrentSession: @Sendable @MainActor () async -> Void
    let relaunch: @Sendable @MainActor (StreamLaunchTarget, any WebRTCBridge) async -> Void
}

struct StreamReconnectEnvironment: Sendable {
    let autoReconnectEnabled: Bool
    let launcher: StreamReconnectLauncher
    let publish: @Sendable @MainActor ([StreamAction]) -> Void
}

actor StreamReconnectCoordinator {
    private let policy: StreamReconnectPolicy

    private var reconnectAttempts = 0
    private var lastLaunchTarget: StreamLaunchTarget?
    private var lastStreamBridge: (any WebRTCBridge)?
    private var reconnectTask: Task<Void, Never>?

    init(policy: StreamReconnectPolicy = StreamReconnectPolicy()) {
        self.policy = policy
    }

    func recordLaunchContext(
        target: StreamLaunchTarget,
        bridge: any WebRTCBridge
    ) {
        lastLaunchTarget = target
        lastStreamBridge = bridge
    }

    func reset() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        lastLaunchTarget = nil
        lastStreamBridge = nil
    }

    func reconnectAttemptCount() -> Int {
        reconnectAttempts
    }

    func handleLifecycleChange(
        event: StreamSessionLifecycleEvent,
        environment: StreamReconnectEnvironment
    ) async {
        switch event.lifecycle {
        case .connected:
            if reconnectAttempts > 0 {
                StreamMetricsPipeline.shared.recordMilestone(
                    .reconnectSuccess,
                    context: metricsContext,
                    targetID: metricsTargetID,
                    reconnectAttempt: reconnectAttempts,
                    reconnectOutcome: .success
                )
            }
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempts = 0
            await environment.publish([
                .reconnectCompleted,
                .runtimePhaseSet(.streaming)
            ])

        case .failed:
            await scheduleReconnectIfNeeded(
                trigger: .failed,
                intent: .reconnectable,
                environment: environment
            )

        case .disconnected:
            await scheduleReconnectIfNeeded(
                trigger: .disconnected(event.disconnectIntent),
                intent: event.disconnectIntent,
                environment: environment
            )

        default:
            break
        }
    }

    private func scheduleReconnectIfNeeded(
        trigger: StreamReconnectTrigger,
        intent: StreamingDisconnectIntent,
        environment: StreamReconnectEnvironment
    ) async {
        let hasLaunchContext = lastLaunchTarget != nil && lastStreamBridge != nil
        let decision = policy.decision(
            intent: intent,
            autoReconnectEnabled: environment.autoReconnectEnabled,
            currentAttemptCount: reconnectAttempts,
            hasLaunchContext: hasLaunchContext
        )
        guard decision.shouldReconnect else {
            reconnectTask?.cancel()
            reconnectTask = nil
            if reconnectAttempts > 0 {
                StreamMetricsPipeline.shared.recordMilestone(
                    .reconnectFailure,
                    context: metricsContext,
                    targetID: metricsTargetID,
                    disconnectIntent: metricsDisconnectIntent(for: intent),
                    reconnectAttempt: reconnectAttempts,
                    reconnectTrigger: String(describing: trigger),
                    reconnectOutcome: .failure,
                    metadata: ["suppression_reason": String(describing: decision.suppressionReason ?? .attemptsExhausted)]
                )
            }
            await environment.publish([
                .streamDisconnected(intent),
                .reconnectSuppressed(decision.suppressionReason ?? .attemptsExhausted)
            ])
            return
        }

        guard reconnectTask == nil,
              let target = lastLaunchTarget,
              let bridge = lastStreamBridge else {
            return
        }

        reconnectAttempts += 1
        StreamMetricsPipeline.shared.recordMilestone(
            .reconnectAttempt,
            context: metricsContext,
            targetID: metricsTargetID,
            disconnectIntent: metricsDisconnectIntent(for: intent),
            reconnectAttempt: reconnectAttempts,
            reconnectTrigger: String(describing: trigger)
        )
        await environment.publish([
            .streamDisconnected(intent),
            .reconnectScheduled(attempt: reconnectAttempts, trigger: trigger)
        ])

        reconnectTask = Task { [weak self, policy, launcher = environment.launcher] in
            try? await Task.sleep(for: policy.retryDelay)
            guard !Task.isCancelled else { return }
            await launcher.disconnectCurrentSession()
            await launcher.relaunch(target, bridge)
            await self?.clearReconnectTask()
        }
    }

    private func clearReconnectTask() {
        reconnectTask = nil
    }

    private var metricsContext: StreamMetricsLaunchContext? {
        switch lastLaunchTarget {
        case .cloud:
            return .cloud
        case .home:
            return .home
        case nil:
            return nil
        }
    }

    private var metricsTargetID: String? {
        lastLaunchTarget?.targetId
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
