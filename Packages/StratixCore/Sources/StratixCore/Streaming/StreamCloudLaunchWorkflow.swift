// StreamCloudLaunchWorkflow.swift
// Defines stream cloud launch workflow for the Streaming surface.
//

import Foundation
import StratixModels
import StreamingCore
import XCloudAPI
import DiagnosticsKit

final class StreamCloudLaunchWorkflow {
    typealias SessionFactory = @Sendable (XCloudAPIClient, any WebRTCBridge, StreamingConfig, StreamPreferences) async -> any StreamingSessionFacade
    typealias CloudConnect = @Sendable (any StreamingSessionFacade, String, String) async -> Void

    private let launchConfigurationService: StreamLaunchConfigurationService
    private let overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator
    private let runtimeAttachmentService: StreamRuntimeAttachmentService
    private let priorityModeCoordinator: StreamPriorityModeCoordinator
    private let makeSession: SessionFactory
    private let connectCloud: CloudConnect

    @MainActor
    init(
        launchConfigurationService: StreamLaunchConfigurationService = StreamLaunchConfigurationService(),
        overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator = StreamOverlayVisibilityCoordinator(),
        runtimeAttachmentService: StreamRuntimeAttachmentService = StreamRuntimeAttachmentService(),
        priorityModeCoordinator: StreamPriorityModeCoordinator = StreamPriorityModeCoordinator(),
        makeSession: @escaping SessionFactory = { client, bridge, config, preferences in
            await MainActor.run {
                StreamingSession(
                    apiClient: client,
                    bridge: bridge,
                    config: config,
                    preferences: preferences
                )
            }
        },
        connectCloud: @escaping CloudConnect = { session, titleId, userToken in
            await session.connect(type: .cloud, targetId: titleId, msaUserToken: userToken)
        }
    ) {
        self.launchConfigurationService = launchConfigurationService
        self.overlayVisibilityCoordinator = overlayVisibilityCoordinator
        self.runtimeAttachmentService = runtimeAttachmentService
        self.priorityModeCoordinator = priorityModeCoordinator
        self.makeSession = makeSession
        self.connectCloud = connectCloud
    }

    @MainActor
    func run(
        titleId: TitleID,
        bridge: any WebRTCBridge,
        state: @escaping @MainActor () -> StreamState,
        reconnectCoordinator: StreamReconnectCoordinator,
        environment: StreamCloudLaunchWorkflowEnvironment
    ) async {
        let initialState = await state()
        guard initialState.streamingSession == nil else {
            environment.logger.warning("Ignoring cloud stream start because a session is already active")
            return
        }

        let target = StreamLaunchTarget.cloud(titleId)
        StreamMetricsPipeline.shared.recordMilestone(
            .launchRequested,
            context: .cloud,
            targetID: titleId.rawValue
        )
        await priorityModeCoordinator.enter(
            context: target.runtimeContext,
            state: initialState,
            environment: environment.priorityModeEnvironment,
            publish: environment.publish
        )
        await environment.prepareVideoCapabilities()
        await environment.updateControllerSettings()

        let wasReconnectAttempt = initialState.isReconnecting
        if !wasReconnectAttempt {
            await reconnectCoordinator.reset()
        }
        await reconnectCoordinator.recordLaunchContext(target: target, bridge: bridge)

        let launchResetAction: StreamAction
        switch target {
        case .cloud(let launchTitleID):
            launchResetAction = .cloudLaunchRequested(launchTitleID)
        case .home(let consoleID):
            launchResetAction = .homeLaunchRequested(consoleId: consoleID)
        }
        await environment.publish([
            launchResetAction,
            .reconnectingSet(wasReconnectAttempt),
            .streamingSessionSet(nil),
            .sessionAttachmentStateSet(.detached),
            .launchHeroURLSet(nil),
            .achievementSnapshotSet(nil),
            .achievementErrorSet(nil),
            .shellRestoredAfterExitSet(false)
        ])
        await overlayVisibilityCoordinator.stopPresentationRefresh()

        let cloudConnectAuth: SessionController.CloudConnectAuth
        do {
            environment.logger.info("Preparing cloud stream auth…")
            cloudConnectAuth = try await environment.cloudConnectAuth()
        } catch {
            let message = "Cloud connect auth failed: \(error.localizedDescription)"
            environment.logger.error(message)
            await environment.setLastAuthError(message)
            await environment.publish([
                .streamStartFailed(message),
                .sessionAttachmentStateSet(.detached)
            ])
            return
        }

        guard let xcloudToken = cloudConnectAuth.tokens.xcloudToken else {
            let message = "Cloud connect auth failed: missing xCloud token"
            environment.logger.error(message)
            await environment.setLastAuthError(message)
            await environment.publish([
                .streamStartFailed(message),
                .sessionAttachmentStateSet(.detached)
            ])
            return
        }

        let launch = await launchConfigurationService.resolvedCloudLaunchConfigurationOffMain(
            environment: environment.launchEnvironment,
            tokens: cloudConnectAuth.tokens,
            targetId: titleId.rawValue
        )
        if let migrationNote = launch.migrationNote {
            environment.logger.warning("[STREAM CONFIG] \(migrationNote)")
        }
        if let diagnosticsNote = launch.diagnosticsNote {
            environment.logger.warning("[STREAM CONFIG] \(diagnosticsNote)")
        }
        if let resolvedHost = launch.resolvedHost {
            environment.logger.info("Cloud stream host: \(resolvedHost)")
        }
        for line in launch.diagnosticsLines {
            environment.logger.info(line)
        }

        await environment.publish([
            .launchHeroURLSet(await environment.cachedHeroURL(titleId))
        ])

        let overlayState = await state()
        if overlayState.isStreamOverlayVisible {
            let overlayActions = await overlayVisibilityCoordinator.setVisibility(
                true,
                trigger: .automatic,
                state: overlayState,
                environment: environment.overlayEnvironment
            )
            await environment.publish(overlayActions)
        }

        guard let resolvedHost = launch.resolvedHost else {
            let message = "No xCloud host resolved for cloud stream"
            environment.logger.error(message)
            await environment.publish([
                .streamStartFailed(message),
                .sessionAttachmentStateSet(.detached)
            ])
            return
        }

        let client = XCloudAPIClient(
            baseHost: resolvedHost,
            gsToken: xcloudToken,
            session: environment.apiSession
        )
        let session = await makeSession(client, bridge, launch.config, launch.preferences)
        await environment.publish([.sessionAttachmentStateSet(.attaching)])
        await environment.publish(
            await runtimeAttachmentService.attach(
                session: session,
                environment: environment.runtimeAttachmentEnvironment,
                onLifecycleChange: environment.onLifecycleChange
            )
        )
        StreamMetricsPipeline.shared.recordMilestone(
            .runtimePrepared,
            context: .cloud,
            targetID: titleId.rawValue
        )

        StreamPerformanceTracker.mark(
            .sessionStartRequest,
            metadata: ["context": "cloud", "target_id": titleId.rawValue]
        )
        StreamPerformanceTracker.mark(
            .readyToConnect,
            metadata: ["context": "cloud", "target_id": titleId.rawValue]
        )

        await connectCloud(session, titleId.rawValue, cloudConnectAuth.userToken)
    }
}
