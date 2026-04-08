// StreamPriorityModeCoordinatorTests.swift
// Exercises stream priority mode coordinator behavior.
//

import Testing
import StratixModels
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct StreamPriorityModeCoordinatorTests {
    @Test
    func enter_fromShellActive_publishesPreparingActionsAndCallsEnvironment() async {
        let coordinator = StreamPriorityModeCoordinator()
        var published: [StreamAction] = []
        var entered = false

        await coordinator.enter(
            context: .cloud(titleId: TitleID("1234")),
            state: .empty,
            environment: StreamPriorityModeEnvironment(
                enterPriorityMode: { entered = true },
                exitPriorityMode: {}
            ),
            publish: { published.append(contentsOf: $0) }
        )

        #expect(entered == true)
        #expect(published.contains(.runtimeContextSet(.cloud(titleId: TitleID("1234")))))
        #expect(published.contains(.shellRestoredAfterExitSet(false)))
        #expect(published.contains(.runtimePhaseSet(.preparingStream)))
    }

    @Test
    func exit_fromPreparingStream_restoresShellAndClearsRuntimeContext() async {
        let coordinator = StreamPriorityModeCoordinator()
        var published: [StreamAction] = []
        var exited = false

        await coordinator.exit(
            state: StreamReducer.reduce(state: .empty, action: .runtimePhaseSet(.preparingStream)),
            environment: StreamPriorityModeEnvironment(
                enterPriorityMode: {},
                exitPriorityMode: { exited = true }
            ),
            publish: { published.append(contentsOf: $0) }
        )

        #expect(exited == true)
        #expect(published.contains(.runtimeContextSet(nil)))
        #expect(published.contains(.runtimePhaseSet(.restoringShell)))
        #expect(published.contains(.runtimePhaseSet(.shellActive)))
    }

    @Test
    func enterShellPriorityMode_suspendsParticipantsAndReturnsTrue() async {
        let coordinator = StreamPriorityModeCoordinator()
        var suspended: [String] = []

        let active = await coordinator.enterShellPriorityMode(
            isShellSuspendedForStreaming: false,
            policyLabel: "tear_down_shell",
            environment: StreamPriorityShellEnvironment(
                participants: [
                    StreamPriorityShellParticipant(
                        suspend: { suspended.append("shell") },
                        resume: {}
                    ),
                    StreamPriorityShellParticipant(
                        suspend: { suspended.append("library") },
                        resume: {}
                    )
                ],
                refreshPostStreamShellState: {}
            )
        )

        #expect(active == true)
        #expect(suspended == ["shell", "library"])
    }

    @Test
    func exitShellPriorityMode_resumesParticipants_andRefreshesShell() async {
        let coordinator = StreamPriorityModeCoordinator()
        var resumed: [String] = []
        var refreshed = false

        let active = await coordinator.exitShellPriorityMode(
            isShellSuspendedForStreaming: true,
            environment: StreamPriorityShellEnvironment(
                participants: [
                    StreamPriorityShellParticipant(
                        suspend: {},
                        resume: { resumed.append("shell") }
                    ),
                    StreamPriorityShellParticipant(
                        suspend: {},
                        resume: { resumed.append("library") }
                    )
                ],
                refreshPostStreamShellState: { refreshed = true }
            )
        )

        #expect(active == false)
        #expect(resumed == ["shell", "library"])
        #expect(refreshed == true)
    }
}
