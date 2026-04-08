// GamepadHandlerTests.swift
// Exercises gamepad handler behavior.
//

import Testing
import StratixModels
@testable import InputBridge

@MainActor
@Suite
struct GamepadHandlerTests {
    @Test
    func triggerInterpretation_digitalFallbackForcesPressedToOne() {
        let handler = GamepadHandler(gamepadIndex: 0)
        var settings = ControllerSettings()
        settings.triggerInterpretationMode = .digitalFallback

        let resolved = handler.resolveTriggerRaw(
            rawValue: 0.0,
            isPressed: true,
            side: .left,
            settings: settings
        )

        #expect(resolved == 1.0)
    }

    @Test
    func triggerInterpretation_analogOnlyKeepsRawValue() {
        let handler = GamepadHandler(gamepadIndex: 0)
        var settings = ControllerSettings()
        settings.triggerInterpretationMode = .analogOnly

        let resolved = handler.resolveTriggerRaw(
            rawValue: 0.24,
            isPressed: true,
            side: .left,
            settings: settings
        )

        #expect(abs(resolved - 0.24) < 0.0001)
    }

    @Test
    func triggerInterpretation_autoDetectsDigitalFallbackFromPressedZero() {
        let handler = GamepadHandler(gamepadIndex: 0)
        var settings = ControllerSettings()
        settings.triggerInterpretationMode = .auto

        let resolved = handler.resolveTriggerRaw(
            rawValue: 0.0,
            isPressed: true,
            side: .left,
            settings: settings
        )

        #expect(resolved == 1.0)
    }

    @Test
    func triggerInterpretation_autoReturnsToAnalogWhenIntermediateTravelAppears() {
        let handler = GamepadHandler(gamepadIndex: 0)
        var settings = ControllerSettings()
        settings.triggerInterpretationMode = .auto

        _ = handler.resolveTriggerRaw(
            rawValue: 0.0,
            isPressed: true,
            side: .left,
            settings: settings
        )
        let resolved = handler.resolveTriggerRaw(
            rawValue: 0.42,
            isPressed: true,
            side: .left,
            settings: settings
        )

        #expect(abs(resolved - 0.42) < 0.0001)
    }
}
