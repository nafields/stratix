// StreamHomeLaunchWorkflowTests.swift
// Exercises stream home launch workflow behavior.
//

import DiagnosticsKit
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@MainActor
@Suite(.serialized)
struct StreamHomeLaunchWorkflowTests {
    @Test
    func run_ignoresDuplicateStartWhenSessionAlreadyActive() async {
        let workflow = StreamHomeLaunchWorkflow()
        let reconnectCoordinator = StreamReconnectCoordinator()
        var published: [StreamAction] = []

        await workflow.run(
            console: makeRemoteConsole(),
            bridge: TestWebRTCBridge(),
            state: {
                StreamReducer.reduce(state: .empty, action: .streamingSessionSet(makeStreamingSession()))
            },
            reconnectCoordinator: reconnectCoordinator,
            environment: makeHomeEnvironment { published.append(contentsOf: $0) }
        )

        #expect(published.isEmpty)
        #expect(await reconnectCoordinator.reconnectAttemptCount() == 0)
    }

    @Test
    func run_entersPriorityMode_beforeSessionConnect() async {
        let events = ArrayRecorder<String>()
        let workflow = StreamHomeLaunchWorkflow(
            makeSession: { client, bridge, config, preferences in
                await makeStreamingSession()
            },
            connectHome: { _, _ in
                await events.append("connect")
            }
        )

        await workflow.run(
            console: makeRemoteConsole(),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: makeHomeEnvironment(
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: { await events.append("enter") },
                    exitPriorityMode: {}
                ),
                publish: { _ in }
            )
        )

        #expect(await events.snapshot() == ["enter", "connect"])
    }

    @Test
    func run_resetsLaunchState_beforeSessionAttach() async {
        var publishedBatches: [[StreamAction]] = []
        let workflow = StreamHomeLaunchWorkflow(
            makeSession: { _, _, _, _ in await makeStreamingSession() },
            connectHome: { _, _ in }
        )

        await workflow.run(
            console: makeRemoteConsole(),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: makeHomeEnvironment(
                publish: { publishedBatches.append($0) }
            )
        )

        let resetBatchIndex = publishedBatches.firstIndex(where: { batch in
            batch.contains(.homeLaunchRequested(consoleId: "console-1"))
                && batch.contains(.streamingSessionSet(nil))
        })
        let attachingBatchIndex = publishedBatches.firstIndex(where: { batch in
            batch == [.sessionAttachmentStateSet(.attaching)]
        })

        #expect(resetBatchIndex != nil)
        #expect(attachingBatchIndex != nil)
        #expect(resetBatchIndex! < attachingBatchIndex!)
    }

    private func makeHomeEnvironment(
        priorityModeEnvironment: StreamPriorityModeEnvironment = StreamPriorityModeEnvironment(
            enterPriorityMode: {},
            exitPriorityMode: {}
        ),
        publish: @escaping @MainActor ([StreamAction]) -> Void
    ) -> StreamHomeLaunchWorkflowEnvironment {
        StreamHomeLaunchWorkflowEnvironment(
            launchEnvironment: makeStreamLaunchEnvironment(),
            runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
            priorityModeEnvironment: priorityModeEnvironment,
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
            publish: publish,
            onLifecycleChange: { _ in }
        )
    }
}
