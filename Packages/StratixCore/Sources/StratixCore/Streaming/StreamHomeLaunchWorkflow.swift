// StreamHomeLaunchWorkflow.swift
// Defines stream home launch workflow for the Streaming surface.
//

import Foundation
import StratixModels
import StreamingCore
import XCloudAPI
import DiagnosticsKit

final class StreamHomeLaunchWorkflow {
    typealias SessionFactory = @Sendable (XCloudAPIClient, any WebRTCBridge, StreamingConfig, StreamPreferences) async -> any StreamingSessionFacade
    typealias HomeConnect = @Sendable (any StreamingSessionFacade, String) async -> Void

    private let launchConfigurationService: StreamLaunchConfigurationService
    private let overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator
    private let runtimeAttachmentService: StreamRuntimeAttachmentService
    private let priorityModeCoordinator: StreamPriorityModeCoordinator
    private let makeSession: SessionFactory
    private let connectHome: HomeConnect

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
        connectHome: @escaping HomeConnect = { session, consoleId in
            await session.connect(type: .home, targetId: consoleId, msaUserToken: nil)
        }
    ) {
        self.launchConfigurationService = launchConfigurationService
        self.overlayVisibilityCoordinator = overlayVisibilityCoordinator
        self.runtimeAttachmentService = runtimeAttachmentService
        self.priorityModeCoordinator = priorityModeCoordinator
        self.makeSession = makeSession
        self.connectHome = connectHome
    }

    @MainActor
    func run(
        console: RemoteConsole,
        bridge: any WebRTCBridge,
        state: @escaping @MainActor () -> StreamState,
        reconnectCoordinator: StreamReconnectCoordinator,
        environment: StreamHomeLaunchWorkflowEnvironment
    ) async {
        let initialState = await state()
        guard initialState.streamingSession == nil else {
            environment.logger.warning("Ignoring home stream start because a session is already active")
            return
        }

        let target = StreamLaunchTarget.home(consoleId: console.serverId)
        StreamMetricsPipeline.shared.recordMilestone(
            .launchRequested,
            context: .home,
            targetID: console.serverId
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
        case .cloud(let titleID):
            launchResetAction = .cloudLaunchRequested(titleID)
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

        let launch = await launchConfigurationService.resolvedHomeLaunchConfigurationOffMain(
            environment: environment.launchEnvironment
        )
        if let migrationNote = launch.migrationNote {
            environment.logger.warning("[STREAM CONFIG] \(migrationNote)")
        }
        if let diagnosticsNote = launch.diagnosticsNote {
            environment.logger.warning("[STREAM CONFIG] \(diagnosticsNote)")
        }
        for line in launch.diagnosticsLines {
            environment.logger.info(line)
        }

        let client = XCloudAPIClient(
            baseHost: environment.tokens.xhomeHost,
            gsToken: environment.tokens.xhomeToken,
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
            context: .home,
            targetID: console.serverId
        )

        StreamPerformanceTracker.mark(
            .sessionStartRequest,
            metadata: ["context": "home", "target_id": console.serverId]
        )
        StreamPerformanceTracker.mark(
            .readyToConnect,
            metadata: ["context": "home", "target_id": console.serverId]
        )

        await connectHome(session, console.serverId)
    }
}
