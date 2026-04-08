// StreamOverlayControllerTests.swift
// Exercises stream overlay controller behavior.
//

import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct StreamOverlayControllerTests {
    @Test
    func makeCommandStream_flushesBufferedCommandsOnFirstConsumer() async {
        let controller = StreamOverlayController()
        controller.requestOverlayToggle()
        controller.requestDisconnect()
        controller.toggleStatsHUD()

        var iterator = controller.makeCommandStream().makeAsyncIterator()
        #expect(await iterator.next() == .toggleOverlay)
        #expect(await iterator.next() == .disconnect)
        #expect(await iterator.next() == .toggleStatsHUD)
    }

    @Test
    func requestOverlayToggle_yieldsToggleCommand() async {
        let controller = StreamOverlayController()
        var iterator = controller.makeCommandStream().makeAsyncIterator()
        controller.requestOverlayToggle()
        #expect(await iterator.next() == .toggleOverlay)
    }

    @Test
    func requestDisconnect_yieldsDisconnectCommand() async {
        let controller = StreamOverlayController()
        var iterator = controller.makeCommandStream().makeAsyncIterator()
        controller.requestDisconnect()
        #expect(await iterator.next() == .disconnect)
    }

    @Test
    func toggleStatsHUD_yieldsToggleStatsHUDCommand() async {
        let controller = StreamOverlayController()
        var iterator = controller.makeCommandStream().makeAsyncIterator()
        controller.toggleStatsHUD()
        #expect(await iterator.next() == .toggleStatsHUD)
    }

    @Test
    func reset_clearsBufferedCommandsAndContinuation() async {
        let controller = StreamOverlayController()
        controller.requestOverlayToggle()
        controller.reset()

        var iterator = controller.makeCommandStream().makeAsyncIterator()
        controller.requestDisconnect()
        #expect(await iterator.next() == .disconnect)
    }
}
