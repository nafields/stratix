// StreamLaunchWorkflowTests.swift
// Exercises stream launch workflow behavior.
//

import DiagnosticsKit
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@MainActor
@Suite(.serialized)
struct StreamLaunchWorkflowTests {
    @Test
    func startHome_ignoresStartWhenSessionAlreadyActive() async {
        let workflow = StreamLaunchWorkflow()
        let reconnectCoordinator = StreamReconnectCoordinator()
        var published: [StreamAction] = []

        await workflow.startHome(
            console: makeRemoteConsole(),
            bridge: TestWebRTCBridge(),
            state: {
                StreamReducer.reduce(state: .empty, action: .streamingSessionSet(makeStreamingSession()))
            },
            reconnectCoordinator: reconnectCoordinator,
            environment: StreamHomeLaunchWorkflowEnvironment(
                launchEnvironment: makeStreamLaunchEnvironment(),
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: {},
                    exitPriorityMode: {}
                ),
                logger: GLogger(category: .auth),
                tokens: StreamTokens(
                    xhomeToken: "xhome",
                    xhomeHost: "https://xhome.example.com",
                    xcloudToken: nil,
                    xcloudHost: nil,
                    webToken: nil,
                    webTokenUHS: nil,
                    xcloudRegions: []
                ),
                updateControllerSettings: {},
                prepareVideoCapabilities: {},
                apiSession: .shared,
                publish: { published.append(contentsOf: $0) },
                onLifecycleChange: { _ in }
            )
        )

        #expect(published.isEmpty)
        #expect(await reconnectCoordinator.reconnectAttemptCount() == 0)
    }

    @Test
    func startCloud_publishesLaunchResetActions_beforeAuthFailure() async {
        let workflow = StreamLaunchWorkflow()
        let reconnectCoordinator = StreamReconnectCoordinator()
        var published: [StreamAction] = []

        await workflow.startCloud(
            titleId: makeTitleID(),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: reconnectCoordinator,
            environment: StreamCloudLaunchWorkflowEnvironment(
                launchEnvironment: makeStreamLaunchEnvironment(),
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: {},
                    exitPriorityMode: {}
                ),
                overlayEnvironment: StreamOverlayEnvironment(
                    heroArtworkEnvironment: nil,
                    achievementEnvironment: nil,
                    shouldContinuePresentationRefresh: { false },
                    publishRefreshResult: { _ in },
                    injectNeutralFrame: {},
                    injectPauseMenuTap: {}
                ),
                logger: GLogger(category: .auth),
                updateControllerSettings: {},
                prepareVideoCapabilities: {},
                cloudConnectAuth: {
                    throw APIError.decodingError("auth failed")
                },
                setLastAuthError: { _ in },
                cachedHeroURL: { _ in nil },
                apiSession: .shared,
                publish: { published.append(contentsOf: $0) },
                onLifecycleChange: { _ in }
            )
        )

        #expect(published.contains(.cloudLaunchRequested(makeTitleID())))
        #expect(published.contains(.reconnectingSet(false)))
        #expect(published.contains(.streamingSessionSet(nil)))
        #expect(published.contains(.sessionAttachmentStateSet(.detached)))
        #expect(published.contains(.launchHeroURLSet(nil)))
        #expect(published.contains(.achievementSnapshotSet(nil)))
        #expect(published.contains(.achievementErrorSet(nil)))
        #expect(published.contains(.shellRestoredAfterExitSet(false)))
    }

    @Test
    func startCloud_publishesFailureWhenAuthFetchThrows() async {
        let workflow = StreamLaunchWorkflow()
        let reconnectCoordinator = StreamReconnectCoordinator()
        var published: [StreamAction] = []

        await workflow.startCloud(
            titleId: makeTitleID(),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: reconnectCoordinator,
            environment: StreamCloudLaunchWorkflowEnvironment(
                launchEnvironment: makeStreamLaunchEnvironment(),
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: {},
                    exitPriorityMode: {}
                ),
                overlayEnvironment: StreamOverlayEnvironment(
                    heroArtworkEnvironment: nil,
                    achievementEnvironment: nil,
                    shouldContinuePresentationRefresh: { false },
                    publishRefreshResult: { _ in },
                    injectNeutralFrame: {},
                    injectPauseMenuTap: {}
                ),
                logger: GLogger(category: .auth),
                updateControllerSettings: {},
                prepareVideoCapabilities: {},
                cloudConnectAuth: {
                    throw APIError.decodingError("auth failed")
                },
                setLastAuthError: { _ in },
                cachedHeroURL: { _ in nil },
                apiSession: .shared,
                publish: { published.append(contentsOf: $0) },
                onLifecycleChange: { _ in }
            )
        )

        #expect(
            published.contains { action in
                guard case .streamStartFailed(let message) = action else { return false }
                return message.contains("Cloud connect auth failed")
            }
        )
        #expect(published.contains(.sessionAttachmentStateSet(.detached)))
    }

    @Test
    func startHome_ignoresDuplicateStartWhileAnotherStartIsInProgress() async {
        let connectEvents = ArrayRecorder<String>()
        let homeLaunchWorkflow = StreamHomeLaunchWorkflow(
            makeSession: { _, _, _, _ in
                await makeStreamingSession()
            },
            connectHome: { _, _ in
                await connectEvents.append("connect-start")
                try? await Task.sleep(for: .milliseconds(100))
                await connectEvents.append("connect-end")
            }
        )
        let workflow = StreamLaunchWorkflow(
            homeLaunchWorkflow: homeLaunchWorkflow,
            cloudLaunchWorkflow: StreamCloudLaunchWorkflow()
        )
        let reconnectCoordinator = StreamReconnectCoordinator()
        var published: [StreamAction] = []

        let firstStart = Task {
            await workflow.startHome(
                console: makeRemoteConsole(),
                bridge: TestWebRTCBridge(),
                state: { .empty },
                reconnectCoordinator: reconnectCoordinator,
                environment: StreamHomeLaunchWorkflowEnvironment(
                    launchEnvironment: makeStreamLaunchEnvironment(),
                    runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                    priorityModeEnvironment: StreamPriorityModeEnvironment(
                        enterPriorityMode: {},
                        exitPriorityMode: {}
                    ),
                    logger: GLogger(category: .auth),
                    tokens: StreamTokens(
                        xhomeToken: "xhome",
                        xhomeHost: "https://xhome.example.com",
                        xcloudToken: nil,
                        xcloudHost: nil,
                        webToken: nil,
                        webTokenUHS: nil,
                        xcloudRegions: []
                    ),
                    updateControllerSettings: {},
                    prepareVideoCapabilities: {},
                    apiSession: .shared,
                    publish: { published.append(contentsOf: $0) },
                    onLifecycleChange: { _ in }
                )
            )
        }

        try? await Task.sleep(for: .milliseconds(20))

        let secondStart = Task {
            await workflow.startHome(
                console: makeRemoteConsole(),
                bridge: TestWebRTCBridge(),
                state: { .empty },
                reconnectCoordinator: reconnectCoordinator,
                environment: StreamHomeLaunchWorkflowEnvironment(
                    launchEnvironment: makeStreamLaunchEnvironment(),
                    runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                    priorityModeEnvironment: StreamPriorityModeEnvironment(
                        enterPriorityMode: {},
                        exitPriorityMode: {}
                    ),
                    logger: GLogger(category: .auth),
                    tokens: StreamTokens(
                        xhomeToken: "xhome",
                        xhomeHost: "https://xhome.example.com",
                        xcloudToken: nil,
                        xcloudHost: nil,
                        webToken: nil,
                        webTokenUHS: nil,
                        xcloudRegions: []
                    ),
                    updateControllerSettings: {},
                    prepareVideoCapabilities: {},
                    apiSession: .shared,
                    publish: { published.append(contentsOf: $0) },
                    onLifecycleChange: { _ in }
                )
            )
        }

        await firstStart.value
        await secondStart.value

        #expect(await connectEvents.snapshot() == ["connect-start", "connect-end"])
        #expect(
            published.filter { action in
                guard case .homeLaunchRequested("console-1") = action else { return false }
                return true
            }.count == 1
        )
    }
}
