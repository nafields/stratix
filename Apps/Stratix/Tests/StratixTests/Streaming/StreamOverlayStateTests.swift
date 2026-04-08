// StreamOverlayStateTests.swift
// Exercises stream overlay state behavior.
//

import Testing
@testable import Stratix
import StreamingCore

@MainActor
@Suite
struct StreamOverlayStateTests {
    @Test
    func detailsPanelRequiresVisibleOverlayAndSession() {
        let state = StreamOverlayState(
            lifecycle: .connected,
            overlayInfo: .cloud(item: nil),
            overlayVisible: true,
            hasSession: true
        )

        #expect(state.showsConnectionOverlay == false)
        #expect(state.showsDetailsPanel == true)
    }

    @Test
    func connectingOverlayTracksLifecycle() {
        let state = StreamOverlayState(
            lifecycle: .connectingWebRTC,
            overlayInfo: .cloud(item: nil),
            overlayVisible: false,
            hasSession: true
        )

        #expect(state.showsConnectionOverlay == true)
        #expect(state.showsDetailsPanel == false)
    }

    @Test
    func hiddenOverlayOrMissingSessionDoesNotExposeDetailsPanel() {
        let hidden = StreamOverlayState(
            lifecycle: .connected,
            overlayInfo: .cloud(item: nil),
            overlayVisible: false,
            hasSession: true
        )
        let missingSession = StreamOverlayState(
            lifecycle: .connected,
            overlayInfo: .cloud(item: nil),
            overlayVisible: true,
            hasSession: false
        )

        #expect(hidden.showsDetailsPanel == false)
        #expect(hidden.focusTarget == nil)
        #expect(missingSession.showsDetailsPanel == false)
        #expect(missingSession.focusTarget == nil)
    }
}
