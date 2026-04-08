// StreamStopWorkflowTests.swift
// Exercises stream stop workflow behavior.
//

import Testing
import StratixModels
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct StreamStopWorkflowTests {
    @Test
    func stop_clearsOverlayHeroAchievementsAndLaunchTarget() async {
        let workflow = StreamStopWorkflow()
        let session = makeStreamingSession()
        var published: [StreamAction] = []
        let state = StreamReducer.reduce(
            state: StreamReducer.reduce(
                state: StreamReducer.reduce(
                    state: .empty,
                    action: .cloudLaunchRequested(makeTitleID())
                ),
                action: .overlayVisibilityChanged(true, trigger: .userToggle)
            ),
            action: .streamingSessionSet(session)
        )

        await workflow.stop(
            state: state,
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: StreamStopWorkflowEnvironment(
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: {},
                    exitPriorityMode: {}
                ),
                publish: { published.append(contentsOf: $0) }
            )
        )

        #expect(published.contains(.overlayVisibilityChanged(false, trigger: .explicitExit)))
        #expect(published.contains(.achievementSnapshotSet(nil)))
        #expect(published.contains(.achievementErrorSet(nil)))
        #expect(published.contains(.launchHeroURLSet(nil)))
        #expect(published.contains(.activeLaunchTargetSet(nil)))
    }

    @Test
    func stop_detachesRuntimeAttachment() async {
        let workflow = StreamStopWorkflow()
        let session = makeStreamingSession()
        var published: [StreamAction] = []
        let state = StreamReducer.reduce(
            state: StreamReducer.reduce(
                state: .empty,
                action: .streamingSessionSet(session)
            ),
            action: .sessionAttachmentStateSet(.attached)
        )

        await workflow.stop(
            state: state,
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: StreamStopWorkflowEnvironment(
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: {},
                    exitPriorityMode: {}
                ),
                publish: { published.append(contentsOf: $0) }
            )
        )

        #expect(published.contains(.streamingSessionSet(nil)))
        #expect(published.contains(.sessionAttachmentStateSet(.detached)))
    }

    @Test
    func stop_exitsPriorityMode_andReturnsShellActive() async {
        let workflow = StreamStopWorkflow()
        var published: [StreamAction] = []
        var exitCalls = 0
        let state = StreamReducer.reduce(
            state: StreamReducer.reduce(
                state: .empty,
                action: .runtimeContextSet(.cloud(titleId: TitleID("1234")))
            ),
            action: .runtimePhaseSet(.streaming)
        )

        await workflow.stop(
            state: state,
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: StreamStopWorkflowEnvironment(
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: {},
                    exitPriorityMode: { exitCalls += 1 }
                ),
                publish: { published.append(contentsOf: $0) }
            )
        )

        #expect(exitCalls == 1)
        #expect(published.contains(.runtimeContextSet(nil)))
        #expect(published.contains(.runtimePhaseSet(.restoringShell)))
        #expect(published.contains(.runtimePhaseSet(.shellActive)))
        #expect(!published.contains(.shellRestoredAfterExitSet(true)))
    }

    @Test
    func stop_resetsReconnectState() async {
        let workflow = StreamStopWorkflow()
        var published: [StreamAction] = []
        let state = StreamReducer.reduce(
            state: .empty,
            action: .reconnectScheduled(attempt: 1, trigger: .failed)
        )

        await workflow.stop(
            state: state,
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: StreamStopWorkflowEnvironment(
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: {},
                    exitPriorityMode: {}
                ),
                publish: { published.append(contentsOf: $0) }
            )
        )

        #expect(published.contains(.reconnectStateReset))
    }

    @Test
    func stop_doesNot_publishShellRestoredCompletion() async {
        let workflow = StreamStopWorkflow()
        var published: [StreamAction] = []

        await workflow.stop(
            state: .empty,
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: StreamStopWorkflowEnvironment(
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: StreamPriorityModeEnvironment(
                    enterPriorityMode: {},
                    exitPriorityMode: {}
                ),
                publish: { published.append(contentsOf: $0) }
            )
        )

        #expect(!published.contains(.shellRestoredAfterExitSet(true)))
    }
}
