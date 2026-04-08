// StreamOverlayInputPolicy.swift
// Defines stream overlay input policy for the Streaming surface.
//

import Foundation

struct StreamOverlayInputPolicy {
    func inputDecision(
        for context: StreamOverlayVisibilityChangeContext
    ) -> StreamOverlayInputDecision {
        let injectNeutralFrame: Bool
        switch (context.oldVisible, context.newVisible) {
        case (false, true):
            injectNeutralFrame = context.hasStreamingSession
        case (true, false):
            injectNeutralFrame = context.hasStreamingSession || context.disconnectArmed
        default:
            injectNeutralFrame = false
        }

        let injectPauseMenuTap = context.newVisible
            && !context.oldVisible
            && context.hasStreamingSession
            && context.trigger != .reconnect
            && !context.disconnectArmed

        return StreamOverlayInputDecision(
            injectNeutralFrame: injectNeutralFrame,
            injectPauseMenuTap: injectPauseMenuTap
        )
    }
}
