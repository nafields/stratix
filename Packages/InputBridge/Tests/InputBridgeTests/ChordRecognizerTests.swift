// ChordRecognizerTests.swift
// Exercises chord recognizer behavior.
//

import Testing
import StratixModels
@testable import InputBridge

@Suite
struct ChordRecognizerTests {
    @Test func instantChordFiresImmediately() {
        var recognizer = ChordRecognizer(definitions: [
            ChordDefinition(buttons: [.leftShoulder, .rightShoulder], holdDurationMs: 0, action: .toggleStatsHUD)
        ])
        let frame = GamepadInputFrame(gamepadIndex: 0, buttons: [.leftShoulder, .rightShoulder], leftThumb: .zero, rightThumb: .zero, triggers: .zero)
        let actions = recognizer.process(frame: frame)
        #expect(actions == [.toggleStatsHUD])
    }
}
