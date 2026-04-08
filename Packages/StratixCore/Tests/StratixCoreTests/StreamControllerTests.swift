// StreamControllerTests.swift
// Exercises stream controller behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels
import StreamingCore

@MainActor
@Suite(.serialized)
struct StreamControllerTests {
    @Test
    func commandStream_emitsOverlayDisconnectAndStatsCommands() async {
        let controller = StreamController()
        let commandStream = controller.makeCommandStream()

        controller.requestOverlayToggle()
        controller.requestDisconnect()
        controller.toggleStatsHUD()

        var iterator = commandStream.makeAsyncIterator()
        #expect(await iterator.next() == .toggleOverlay)
        #expect(await iterator.next() == .disconnect)
        #expect(await iterator.next() == .toggleStatsHUD)
    }

    @Test
    func commandStream_replaysCommandsQueuedBeforeSubscription() async {
        let controller = StreamController()

        controller.requestOverlayToggle()
        controller.requestDisconnect()

        var iterator = controller.makeCommandStream().makeAsyncIterator()
        #expect(await iterator.next() == .toggleOverlay)
        #expect(await iterator.next() == .disconnect)
    }

    @Test
    func apply_action_updatesCanonicalState() {
        let controller = StreamController()

        controller.apply(.overlayVisibilityChanged(true, trigger: .userToggle))
        controller.apply(.cloudLaunchRequested(makeTitleID()))
        controller.apply(.achievementErrorSet("error"))

        #expect(controller.state.isStreamOverlayVisible == true)
        #expect(controller.state.activeLaunchTarget == .cloud(makeTitleID()))
        #expect(controller.state.lastStreamAchievementError == "error")
    }

    @Test
    func streamSnapshot_readsCanonicalState() async {
        let session = makeStreamingSession()
        let controller = StreamController(
            initialState: StreamReducer.reduce(
                state: StreamReducer.reduce(
                    state: StreamState.empty,
                    action: .streamingSessionSet(session)
                ),
                action: .overlayVisibilityChanged(true, trigger: .automatic)
            )
        )

        let snapshot = await controller.streamSnapshot()

        #expect(snapshot.isStreaming == true)
        #expect(snapshot.lifecycleDescription == "\(session.lifecycle)")
        #expect(snapshot.isStreamOverlayVisible == true)
    }

    @Test
    func enterAndExitStreamPriorityMode_updatesRuntimePhase() async {
        let controller = StreamController()

        #expect(controller.runtimePhase == .shellActive)
        #expect(controller.isStreamPriorityModeActive == false)

        await controller.enterStreamPriorityMode(context: .cloud(titleId: TitleID("1234")))

        #expect(controller.runtimePhase == .preparingStream)
        #expect(controller.isStreamPriorityModeActive == true)

        await controller.exitStreamPriorityMode()

        #expect(controller.runtimePhase == .shellActive)
        #expect(controller.isStreamPriorityModeActive == false)
    }

    @Test
    func startHomeStream_delegatesToWorkflowInjection_andPublishesExpectedState() async {
        var invoked = false
        let controllerBox = StreamControllerBox()
        let controller = StreamController(
            startHomeWorkflow: { console, _ in
                invoked = true
                controllerBox.controller?.apply([
                    .homeLaunchRequested(consoleId: console.serverId),
                    .runtimePhaseSet(.preparingStream)
                ])
            }
        )
        controllerBox.controller = controller

        await controller.startHomeStream(console: makeRemoteConsole(), bridge: TestWebRTCBridge())

        #expect(invoked == true)
        #expect(controller.state.activeLaunchTarget == .home(consoleId: "console-1"))
        #expect(controller.runtimePhase == .preparingStream)
    }

    @Test
    func startCloudStream_delegatesToWorkflowInjection_andPublishesExpectedState() async {
        var invoked = false
        let controllerBox = StreamControllerBox()
        let controller = StreamController(
            startCloudWorkflow: { titleId, _ in
                invoked = true
                controllerBox.controller?.apply([
                    .cloudLaunchRequested(titleId),
                    .runtimePhaseSet(.preparingStream)
                ])
            }
        )
        controllerBox.controller = controller

        await controller.startCloudStream(titleId: TitleID("1234"), bridge: TestWebRTCBridge())

        #expect(invoked == true)
        #expect(controller.state.activeLaunchTarget == StreamLaunchTarget.cloud(makeTitleID()))
        #expect(controller.runtimePhase == StreamRuntimePhase.preparingStream)
    }

    @Test
    func stopStreaming_exitsPriorityMode_andClearsRuntimeState() async {
        let controller = StreamController(initialState: makeActiveStreamingState())

        await controller.stopStreaming()

        #expect(controller.runtimePhase == .shellActive)
        #expect(controller.isStreamPriorityModeActive == false)
        #expect(controller.streamingSession == nil)
        #expect(controller.state.sessionAttachmentState == .detached)
        #expect(controller.activeRuntimeContext == nil)
        #expect(controller.state.activeLaunchTarget == nil)
        #expect(controller.isStreamOverlayVisible == false)
        #expect(controller.shellRestoredAfterStreamExit == false)
    }

    @Test
    func stopStreaming_resetsReconnectState() async {
        let controller = StreamController(initialState: makeActiveStreamingState())

        await controller.stopStreaming()

        #expect(controller.isReconnecting == false)
        #expect(controller.state.reconnectAttemptCount == 0)
        #expect(controller.state.lastDisconnectIntent == nil)
        #expect(controller.state.lastReconnectTrigger == nil)
        #expect(controller.state.lastReconnectSuppressionReason == nil)
    }

    @Test
    func setOverlayVisible_updatesCanonicalStateThroughCoordinator() async {
        let controller = StreamController()

        await controller.setOverlayVisible(true, trigger: .userToggle)
        #expect(controller.isStreamOverlayVisible == true)

        await controller.setOverlayVisible(false, trigger: .explicitDismiss)
        #expect(controller.isStreamOverlayVisible == false)
        #expect(controller.currentStreamAchievementSnapshot == nil)
        #expect(controller.lastStreamAchievementError == nil)
    }

    @Test
    func resetForSignOut_resetsStateAndCollaborators() async {
        let controller = StreamController(initialState: makeActiveStreamingState())

        await controller.resetForSignOut()

        #expect(controller.state == .empty)
    }

    @Test
    func regionOverrideDiagnostics_usesInjectedConfigurationSurface() {
        let controller = StreamController(
            regionDiagnosticsResolver: StreamRegionDiagnosticsResolver(
                resolver: { rawValue, _ in
                    "diagnostics:\(rawValue)"
                }
            )
        )

        #expect(controller.regionOverrideDiagnostics(for: "us east") == "diagnostics:us east")
    }
}

private final class StreamControllerBox: @unchecked Sendable {
    var controller: StreamController?
}

@MainActor
private func makeActiveStreamingState() -> StreamState {
    let snapshot = TitleAchievementSnapshot(
        titleId: "1234",
        summary: TitleAchievementSummary(
            titleId: "1234",
            titleName: "Halo Infinite",
            totalAchievements: 0,
            unlockedAchievements: 0,
            totalGamerscore: 0,
            unlockedGamerscore: 0
        ),
        achievements: []
    )

    let actions: [StreamAction] = [
        .cloudLaunchRequested(makeTitleID()),
        .streamingSessionSet(makeStreamingSession()),
        .sessionAttachmentStateSet(.attached),
        .overlayVisibilityChanged(true, trigger: .userToggle),
        .achievementSnapshotSet(snapshot),
        .achievementErrorSet("error"),
        .launchHeroURLSet(URL(string: "https://example.com/hero.jpg")),
        .runtimeContextSet(.cloud(titleId: TitleID("1234"))),
        .runtimePhaseSet(.streaming),
        .reconnectScheduled(attempt: 2, trigger: .failed),
        .streamDisconnected(.reconnectable)
    ]

    return actions.reduce(StreamState.empty) { state, action in
        StreamReducer.reduce(state: state, action: action)
    }
}
