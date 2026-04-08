// StreamReconnectCoordinatorTests.swift
// Exercises stream reconnect coordinator behavior.
//

import Testing
import DiagnosticsKit
import os
@testable import StratixCore
import StratixModels
import StreamingCore

@MainActor
@Suite(.serialized)
struct StreamReconnectCoordinatorTests {
    @Test
    func recordLaunchContext_andReset_trackReconnectState() async {
        let coordinator = StreamReconnectCoordinator(policy: StreamReconnectPolicy(maxAttempts: 3, retryDelay: .zero))
        await coordinator.recordLaunchContext(target: .cloud(makeTitleID()), bridge: TestWebRTCBridge())
        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .failed(StreamError(code: .unknown, message: "failed")),
                disconnectIntent: .reconnectable
            ),
            environment: makeReconnectEnvironment()
        )
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await coordinator.reconnectAttemptCount() == 1)
        await coordinator.reset()
        #expect(await coordinator.reconnectAttemptCount() == 0)
    }

    @Test
    func reset_cancelsPendingReconnectTask() async {
        let coordinator = StreamReconnectCoordinator(
            policy: StreamReconnectPolicy(maxAttempts: 3, retryDelay: .milliseconds(100))
        )
        let session = makeStreamingSession()
        var relaunched = false

        await coordinator.recordLaunchContext(target: .cloud(makeTitleID()), bridge: TestWebRTCBridge())

        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .failed(StreamError(code: .unknown, message: "decode fail")),
                disconnectIntent: session.disconnectIntent
            ),
            environment: makeReconnectEnvironment(
                autoReconnectEnabled: true,
                relaunch: { _, _ in relaunched = true }
            )
        )

        await coordinator.reset()
        try? await Task.sleep(for: .milliseconds(150))

        #expect(await coordinator.reconnectAttemptCount() == 0)
        #expect(relaunched == false)
    }

    @Test
    func handleLifecycleChange_failed_schedulesCloudReconnectWhenEligible() async {
        let coordinator = StreamReconnectCoordinator(policy: StreamReconnectPolicy(maxAttempts: 3, retryDelay: .zero))
        let session = makeStreamingSession()
        let bridge = TestWebRTCBridge()
        var published: [StreamAction] = []
        var disconnected = false
        var reconnectedTarget: StreamLaunchTarget?

        await coordinator.recordLaunchContext(target: .cloud(makeTitleID()), bridge: bridge)

        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .failed(StreamError(code: .unknown, message: "decode fail")),
                disconnectIntent: session.disconnectIntent
            ),
            environment: makeReconnectEnvironment(
                autoReconnectEnabled: true,
                disconnectCurrentSession: { disconnected = true },
                relaunch: { target, _ in reconnectedTarget = target },
                publish: { published.append(contentsOf: $0) }
            )
        )
        try? await Task.sleep(for: .milliseconds(20))

        #expect(published.contains(.reconnectScheduled(attempt: 1, trigger: .failed)))
        #expect(disconnected == true)
        #expect(reconnectedTarget == .cloud(makeTitleID()))
    }

    @Test
    func handleLifecycleChange_disconnected_suppressesReconnectWhenPolicyRejectsIt() async {
        let coordinator = StreamReconnectCoordinator(policy: StreamReconnectPolicy(maxAttempts: 0, retryDelay: .zero))
        let session = makeStreamingSession()
        var published: [StreamAction] = []
        var reconnected = false

        await coordinator.recordLaunchContext(target: .cloud(makeTitleID()), bridge: TestWebRTCBridge())

        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .disconnected,
                disconnectIntent: session.disconnectIntent
            ),
            environment: makeReconnectEnvironment(
                autoReconnectEnabled: true,
                relaunch: { _, _ in reconnected = true },
                publish: { published.append(contentsOf: $0) }
            )
        )

        #expect(reconnected == false)
        #expect(published.contains(.reconnectSuppressed(.attemptsExhausted)))
    }

    @Test
    func handleLifecycleChange_homeReconnect_usesHomeTarget() async {
        let coordinator = StreamReconnectCoordinator(policy: StreamReconnectPolicy(maxAttempts: 3, retryDelay: .zero))
        let session = makeStreamingSession()
        let bridge = TestWebRTCBridge()
        var relaunchedTarget: StreamLaunchTarget?

        await coordinator.recordLaunchContext(target: .home(consoleId: "console-1"), bridge: bridge)

        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .failed(StreamError(code: .network, message: "network")),
                disconnectIntent: session.disconnectIntent
            ),
            environment: makeReconnectEnvironment(
                autoReconnectEnabled: true,
                relaunch: { target, _ in relaunchedTarget = target }
            )
        )
        try? await Task.sleep(for: .milliseconds(20))

        #expect(relaunchedTarget == .home(consoleId: "console-1"))
    }

    @Test
    func explicitStop_followedByReset_doesNotLeaveReconnectTaskRunning() async {
        let coordinator = StreamReconnectCoordinator(
            policy: StreamReconnectPolicy(maxAttempts: 3, retryDelay: .milliseconds(100))
        )
        let session = makeStreamingSession()
        var disconnectCalls = 0
        var relaunchCalls = 0

        await coordinator.recordLaunchContext(target: .cloud(makeTitleID()), bridge: TestWebRTCBridge())

        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .failed(StreamError(code: .unknown, message: "decode fail")),
                disconnectIntent: session.disconnectIntent
            ),
            environment: makeReconnectEnvironment(
                autoReconnectEnabled: true,
                disconnectCurrentSession: { disconnectCalls += 1 },
                relaunch: { _, _ in relaunchCalls += 1 }
            )
        )

        await coordinator.reset()
        try? await Task.sleep(for: .milliseconds(150))

        #expect(disconnectCalls == 0)
        #expect(relaunchCalls == 0)
        #expect(await coordinator.reconnectAttemptCount() == 0)
    }

    @Test
    func reconnectLifecycle_recordsAttemptsSuccessAndFailureMilestones() async {
        let coordinator = StreamReconnectCoordinator(policy: StreamReconnectPolicy(maxAttempts: 1, retryDelay: .zero))
        let records = OSAllocatedUnfairLock(initialState: [StreamMetricsRecord]())
        let token = StreamMetricsPipeline.shared.registerSink(
            StreamMetricsSink(name: #function) { record in
                records.withLock { $0.append(record) }
            }
        )
        defer { StreamMetricsPipeline.shared.unregisterSink(token) }

        await coordinator.recordLaunchContext(target: .cloud(makeTitleID("metrics-reconnect")), bridge: TestWebRTCBridge())

        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .failed(StreamError(code: .unknown, message: "decode fail")),
                disconnectIntent: .reconnectable
            ),
            environment: makeReconnectEnvironment(autoReconnectEnabled: true)
        )
        try? await Task.sleep(for: .milliseconds(20))

        var reconnectRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone.targetID == "metrics-reconnect" ? milestone : nil
            }
        }
        #expect(reconnectRecords.contains { $0.milestone == StreamMetricsMilestone.reconnectAttempt && $0.reconnectAttempt == 1 })

        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .connected,
                disconnectIntent: .reconnectable
            ),
            environment: makeReconnectEnvironment(autoReconnectEnabled: true)
        )
        reconnectRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone.targetID == "metrics-reconnect" ? milestone : nil
            }
        }
        #expect(reconnectRecords.contains { $0.milestone == StreamMetricsMilestone.reconnectSuccess && $0.reconnectOutcome == StreamMetricsReconnectOutcome.success })

        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .failed(StreamError(code: .unknown, message: "decode fail")),
                disconnectIntent: .reconnectable
            ),
            environment: makeReconnectEnvironment(autoReconnectEnabled: true)
        )
        try? await Task.sleep(for: .milliseconds(20))
        await coordinator.handleLifecycleChange(
            event: StreamSessionLifecycleEvent(
                lifecycle: .failed(StreamError(code: .unknown, message: "decode fail again")),
                disconnectIntent: .reconnectable
            ),
            environment: makeReconnectEnvironment(autoReconnectEnabled: true)
        )

        reconnectRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone.targetID == "metrics-reconnect" ? milestone : nil
            }
        }
        #expect(reconnectRecords.contains { $0.milestone == StreamMetricsMilestone.reconnectFailure && $0.reconnectOutcome == StreamMetricsReconnectOutcome.failure })
    }
}

private func makeReconnectEnvironment(
    autoReconnectEnabled: Bool = true,
    disconnectCurrentSession: @escaping @Sendable @MainActor () async -> Void = {},
    relaunch: @escaping @Sendable @MainActor (StreamLaunchTarget, any WebRTCBridge) async -> Void = { _, _ in },
    publish: @escaping @Sendable @MainActor ([StreamAction]) -> Void = { _ in }
) -> StreamReconnectEnvironment {
    StreamReconnectEnvironment(
        autoReconnectEnabled: autoReconnectEnabled,
        launcher: StreamReconnectLauncher(
            disconnectCurrentSession: disconnectCurrentSession,
            relaunch: relaunch
        ),
        publish: publish
    )
}
