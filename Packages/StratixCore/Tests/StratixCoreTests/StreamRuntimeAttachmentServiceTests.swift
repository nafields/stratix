// StreamRuntimeAttachmentServiceTests.swift
// Exercises stream runtime attachment service behavior.
//

import Testing
@testable import StratixCore
import StratixModels
import InputBridge

@MainActor
@Suite(.serialized)
struct StreamRuntimeAttachmentServiceTests {
    @Test
    func attach_session_returnsAttachedActionsAndWiresInputAndVibration() async {
        let service = StreamRuntimeAttachmentService()
        let session = makeStreamingSession()
        var observedInputQueue = false
        var vibrationReports: [VibrationReport] = []

        let actions = service.attach(
            session: session,
            environment: makeRuntimeAttachmentEnvironment(
                setupControllerObservation: { _ in observedInputQueue = true },
                routeVibration: { vibrationReports.append($0) }
            ),
            onLifecycleChange: { _ in }
        )

        #expect(observedInputQueue == true)
        #expect(actions.contains(StreamAction.streamingSessionSet(session)))
        #expect(actions.contains(StreamAction.sessionAttachmentStateSet(.attached)))

        let report = VibrationReport(
            gamepadIndex: 0,
            leftMotorPercent: 1,
            rightMotorPercent: 0.5,
            leftTriggerMotorPercent: 0,
            rightTriggerMotorPercent: 0,
            durationMs: 100,
            delayMs: 0,
            repeatCount: 0
        )
        session.onVibration?(report)
        try? await Task.sleep(for: .milliseconds(10))
        #expect(vibrationReports.count == 1)
        #expect(vibrationReports.first?.gamepadIndex == report.gamepadIndex)
        #expect(vibrationReports.first?.leftMotorPercent == report.leftMotorPercent)
        #expect(vibrationReports.first?.rightMotorPercent == report.rightMotorPercent)
    }

    @Test
    func detach_returnsDetachedActionsAndClearsBindings() {
        let service = StreamRuntimeAttachmentService()
        var cleared = false

        let actions = service.detach(
            environment: makeRuntimeAttachmentEnvironment(
                clearStreamingInputBindings: { cleared = true }
            )
        )

        #expect(cleared == true)
        #expect(actions.count == 2)
        #expect(actions.contains(StreamAction.streamingSessionSet(nil)))
        #expect(actions.contains(StreamAction.sessionAttachmentStateSet(.detached)))
    }

    @Test
    func disconnect_disconnectsThroughSessionFacadeBoundary() async {
        let service = StreamRuntimeAttachmentService()
        let session = makeStreamingSession()

        await service.disconnect(
            session: session,
            reason: .reconnectTransition
        )

        #expect(session.lifecycle == .disconnected)
        #expect(session.disconnectIntent == .reconnectTransition)
    }

    @Test
    func reset_clearsLifecycleObserver_andInputBindings() {
        let lifecycleObserver = StreamSessionLifecycleObserver()
        let service = StreamRuntimeAttachmentService(lifecycleObserver: lifecycleObserver)
        let session = makeStreamingSession()
        var cleared = false

        _ = service.attach(
            session: session,
            environment: makeRuntimeAttachmentEnvironment(),
            onLifecycleChange: { _ in }
        )

        service.reset(
            environment: makeRuntimeAttachmentEnvironment(
                clearStreamingInputBindings: { cleared = true }
            )
        )

        #expect(cleared == true)
        #expect(session.onLifecycleChange == nil)
    }
}
