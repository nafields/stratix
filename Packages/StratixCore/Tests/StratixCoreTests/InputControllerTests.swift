// InputControllerTests.swift
// Exercises input controller behavior.
//

import Foundation
import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct InputControllerTests {
    @Test
    func updateControllerSettings_clampsInvalidValues() {
        let suiteName = "InputControllerTests.updateControllerSettings.clampsInvalidValues"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(0.0, forKey: "guide.controller_deadzone")
        defaults.set(0.0, forKey: "guide.trigger_sensitivity")
        defaults.set(2.5, forKey: "stratix.controller.vibrationIntensity")

        let settingsStore = SettingsStore(defaults: defaults)
        let controller = InputController()
        controller.updateControllerSettings(from: settingsStore)

        #expect(controller.controllerSettings.deadzone == 0.15)
        #expect(controller.controllerSettings.triggerSensitivity == 0.5)
        #expect(controller.controllerSettings.vibrationIntensity == 1.0)
    }

    @Test
    func startupHapticsProbeEnabled_readsTypedDiagnosticsSetting() {
        let suiteName = "InputControllerTests.startupHapticsProbeEnabled.readsTypedDiagnosticsSetting"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.diagnostics.startupHapticsProbeEnabled = false
        let controller = InputController()

        #expect(controller.startupHapticsProbeEnabled(from: settingsStore) == false)
    }

    @Test
    func holdComboInterpreter_startSelectHoldFiresNexusTap() async {
        var commands: [HoldComboCommandInterpreter.Command] = []
        let interpreter = HoldComboCommandInterpreter(holdDurationMs: 40) { command in
            commands.append(command)
        }

        interpreter.update(startSelectPressed: true, l3r3Pressed: false)
        try? await Task.sleep(nanoseconds: 90_000_000)

        #expect(commands == [.nexusTap])
    }

    @Test
    func holdComboInterpreter_startSelectReleaseEarlyDoesNotFire() async {
        var commands: [HoldComboCommandInterpreter.Command] = []
        let interpreter = HoldComboCommandInterpreter(holdDurationMs: 80) { command in
            commands.append(command)
        }

        interpreter.update(startSelectPressed: true, l3r3Pressed: false)
        try? await Task.sleep(nanoseconds: 20_000_000)
        interpreter.update(startSelectPressed: false, l3r3Pressed: false)
        try? await Task.sleep(nanoseconds: 90_000_000)

        #expect(commands.isEmpty)
    }

    @Test
    func holdComboInterpreter_overlayMappedToL3R3Only() async {
        var commands: [HoldComboCommandInterpreter.Command] = []
        let interpreter = HoldComboCommandInterpreter(holdDurationMs: 40) { command in
            commands.append(command)
        }

        interpreter.update(startSelectPressed: true, l3r3Pressed: false)
        try? await Task.sleep(nanoseconds: 90_000_000)
        #expect(commands == [.nexusTap])

        commands.removeAll()
        interpreter.update(startSelectPressed: false, l3r3Pressed: false)
        interpreter.update(startSelectPressed: false, l3r3Pressed: true)
        try? await Task.sleep(nanoseconds: 90_000_000)

        #expect(commands == [.overlayToggle])
    }
}
