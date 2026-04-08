// StreamRuntimeAttachmentService.swift
// Defines stream runtime attachment service for the Streaming surface.
//

import Foundation
import StratixModels
import InputBridge
import StreamingCore

struct StreamRuntimeInputEnvironment {
    let setupControllerObservation: @Sendable @MainActor (InputQueue) -> Void
    let clearStreamingInputBindings: @Sendable @MainActor () -> Void
    let routeVibration: @Sendable @MainActor (VibrationReport) -> Void
}

struct StreamRuntimeAttachmentEnvironment {
    let input: StreamRuntimeInputEnvironment
}

struct StreamSessionLifecycleEvent {
    let lifecycle: StreamLifecycleState
    let disconnectIntent: StreamingDisconnectIntent
}

@MainActor
final class StreamRuntimeAttachmentService {
    private let lifecycleObserver: StreamSessionLifecycleObserver

    init(lifecycleObserver: StreamSessionLifecycleObserver = StreamSessionLifecycleObserver()) {
        self.lifecycleObserver = lifecycleObserver
    }

    func attach(
        session: (any StreamingSessionFacade)?,
        environment: StreamRuntimeAttachmentEnvironment,
        onLifecycleChange: @escaping @Sendable @MainActor (StreamSessionLifecycleEvent) -> Void
    ) -> [StreamAction] {
        lifecycleObserver.bind(
            session: session,
            onLifecycleChange: { event in
                onLifecycleChange(event)
            }
        )

        guard let session else {
            environment.input.clearStreamingInputBindings()
            return [
                .streamingSessionSet(nil),
                .sessionAttachmentStateSet(.detached)
            ]
        }

        environment.input.setupControllerObservation(session.inputQueueRef)
        session.setVibrationHandler { report in
            Task { @MainActor in
                environment.input.routeVibration(report)
            }
        }

        return [
            .streamingSessionSet(session),
            .sessionAttachmentStateSet(.attached)
        ]
    }

    func disconnect(
        session: (any StreamingSessionFacade)?,
        reason: StreamingDisconnectIntent = .userInitiated
    ) async {
        await session?.disconnect(reason: reason)
    }

    func detach(
        environment: StreamRuntimeAttachmentEnvironment
    ) -> [StreamAction] {
        lifecycleObserver.bind(session: nil, onLifecycleChange: { _ in })
        environment.input.clearStreamingInputBindings()
        return [
            .streamingSessionSet(nil),
            .sessionAttachmentStateSet(.detached)
        ]
    }

    func reset(environment: StreamRuntimeAttachmentEnvironment) {
        lifecycleObserver.reset()
        environment.input.clearStreamingInputBindings()
    }
}
