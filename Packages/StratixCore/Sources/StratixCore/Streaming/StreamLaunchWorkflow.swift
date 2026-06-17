// StreamLaunchWorkflow.swift
// Defines stream launch workflow for the Streaming surface.
//

import Foundation
import StratixModels
import StreamingCore
import XCloudAPI
import DiagnosticsKit

private actor StreamLaunchStartGate {
    private var isStarting = false

    func begin() -> Bool {
        guard !isStarting else { return false }
        isStarting = true
        return true
    }

    func end() {
        isStarting = false
    }
}

actor StreamLaunchCancellation {
    private var generation = 0

    func begin() -> Int {
        generation += 1
        return generation
    }

    func cancel() {
        generation += 1
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation
    }
}

@MainActor
final class StreamLaunchWorkflow {
    private let homeLaunchWorkflow: StreamHomeLaunchWorkflow
    private let cloudLaunchWorkflow: StreamCloudLaunchWorkflow
    private let startGate = StreamLaunchStartGate()
    private let launchCancellation = StreamLaunchCancellation()

    @MainActor
    init(
        homeLaunchWorkflow: StreamHomeLaunchWorkflow = StreamHomeLaunchWorkflow(),
        cloudLaunchWorkflow: StreamCloudLaunchWorkflow = StreamCloudLaunchWorkflow()
    ) {
        self.homeLaunchWorkflow = homeLaunchWorkflow
        self.cloudLaunchWorkflow = cloudLaunchWorkflow
    }

    func cancelLaunch() async {
        await launchCancellation.cancel()
    }

    @MainActor
    func startHome(
        console: RemoteConsole,
        bridge: any WebRTCBridge,
        state: @escaping @MainActor () -> StreamState,
        reconnectCoordinator: StreamReconnectCoordinator,
        environment: StreamHomeLaunchWorkflowEnvironment
    ) async {
        let currentState = await state()
        guard currentState.streamingSession == nil else {
            environment.logger.warning("Ignoring home stream start because a session is already active")
            return
        }
        guard await startGate.begin() else {
            environment.logger.warning("Ignoring duplicate home stream start while another start is in progress")
            return
        }
        defer {
            Task { await self.startGate.end() }
        }

        let launchToken = await launchCancellation.begin()
        await homeLaunchWorkflow.run(
            console: console,
            bridge: bridge,
            state: state,
            reconnectCoordinator: reconnectCoordinator,
            environment: environment,
            shouldContinue: { [launchCancellation] in
                await launchCancellation.isCurrent(launchToken) && !Task.isCancelled
            }
        )
    }

    @MainActor
    func startCloud(
        titleId: TitleID,
        bridge: any WebRTCBridge,
        state: @escaping @MainActor () -> StreamState,
        reconnectCoordinator: StreamReconnectCoordinator,
        environment: StreamCloudLaunchWorkflowEnvironment
    ) async {
        let currentState = await state()
        guard currentState.streamingSession == nil else {
            environment.logger.warning("Ignoring cloud stream start because a session is already active")
            return
        }
        guard await startGate.begin() else {
            environment.logger.warning("Ignoring duplicate cloud stream start while another start is in progress")
            return
        }
        defer {
            Task { await self.startGate.end() }
        }

        let launchToken = await launchCancellation.begin()
        await cloudLaunchWorkflow.run(
            titleId: titleId,
            bridge: bridge,
            state: state,
            reconnectCoordinator: reconnectCoordinator,
            environment: environment,
            shouldContinue: { [launchCancellation] in
                await launchCancellation.isCurrent(launchToken) && !Task.isCancelled
            }
        )
    }
}