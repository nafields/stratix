// StreamSessionLifecycleObserver.swift
// Defines stream session lifecycle observer for the Streaming surface.
//

import Foundation
import StreamingCore

@MainActor
final class StreamSessionLifecycleObserver {
    private weak var currentSession: (any StreamingSessionFacade)?
    private var bindingGeneration = 0

    func bind(
        session: (any StreamingSessionFacade)?,
        onLifecycleChange: @escaping @MainActor (StreamSessionLifecycleEvent) -> Void
    ) {
        bindingGeneration += 1
        let generation = bindingGeneration

        if currentSession !== session {
            currentSession?.onLifecycleChange = nil
        }

        currentSession = session
        guard let session else { return }
        session.onLifecycleChange = { [weak self, weak session] lifecycle in
            guard
                let self,
                let session,
                self.bindingGeneration == generation,
                self.currentSession === session
            else { return }
            onLifecycleChange(
                StreamSessionLifecycleEvent(
                    lifecycle: lifecycle,
                    disconnectIntent: session.disconnectIntent
                )
            )
        }
    }

    func reset() {
        currentSession?.onLifecycleChange = nil
        currentSession = nil
    }
}
