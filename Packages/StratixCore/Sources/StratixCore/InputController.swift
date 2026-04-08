// InputController.swift
// Defines the input controller.
//

import DiagnosticsKit
import Foundation
import GameController
import InputBridge
import Observation
import StratixModels
import StreamingCore

@MainActor
final class HoldComboCommandInterpreter {
    enum Command: Equatable {
        case nexusTap
        case overlayToggle
    }

    private let holdDurationNanoseconds: UInt64
    private let onCommand: @MainActor (Command) -> Void
    private var startSelectPressed = false
    private var l3r3Pressed = false
    private var didFireStartSelect = false
    private var didFireL3R3 = false
    private var startSelectTask: Task<Void, Never>?
    private var l3r3Task: Task<Void, Never>?

    init(
        holdDurationMs: UInt64 = 600,
        onCommand: @escaping @MainActor (Command) -> Void
    ) {
        self.holdDurationNanoseconds = holdDurationMs * 1_000_000
        self.onCommand = onCommand
    }

    var suppressesPrimaryInput: Bool {
        startSelectPressed || l3r3Pressed
    }

    func update(startSelectPressed: Bool, l3r3Pressed: Bool) {
        updateStartSelect(pressed: startSelectPressed)
        updateL3R3(pressed: l3r3Pressed)
    }

    func cancelAll() {
        startSelectTask?.cancel()
        startSelectTask = nil
        l3r3Task?.cancel()
        l3r3Task = nil
        startSelectPressed = false
        l3r3Pressed = false
        didFireStartSelect = false
        didFireL3R3 = false
    }

    private func updateStartSelect(pressed: Bool) {
        if pressed {
            guard !startSelectPressed else { return }
            startSelectPressed = true
            didFireStartSelect = false
            startSelectTask?.cancel()
            startSelectTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.startSelectTask = nil }
                try? await Task.sleep(for: .nanoseconds(self.holdDurationNanoseconds))
                guard !Task.isCancelled else { return }
                guard self.startSelectPressed, !self.didFireStartSelect else { return }
                self.didFireStartSelect = true
                self.onCommand(.nexusTap)
            }
            return
        }

        startSelectPressed = false
        didFireStartSelect = false
        startSelectTask?.cancel()
        startSelectTask = nil
    }

    private func updateL3R3(pressed: Bool) {
        if pressed {
            guard !l3r3Pressed else { return }
            l3r3Pressed = true
            didFireL3R3 = false
            l3r3Task?.cancel()
            l3r3Task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.l3r3Task = nil }
                try? await Task.sleep(for: .nanoseconds(self.holdDurationNanoseconds))
                guard !Task.isCancelled else { return }
                guard self.l3r3Pressed, !self.didFireL3R3 else { return }
                self.didFireL3R3 = true
                self.onCommand(.overlayToggle)
            }
            return
        }

        l3r3Pressed = false
        didFireL3R3 = false
        l3r3Task?.cancel()
        l3r3Task = nil
    }

    deinit {
        startSelectTask?.cancel()
        l3r3Task?.cancel()
    }
}

@Observable
@MainActor
public final class InputController {
    public private(set) var controllerSettings = ControllerSettings()

    @ObservationIgnored private weak var dependencies: (any InputControllerDependencies)?
    @ObservationIgnored private let logger = GLogger(category: .auth)
    @ObservationIgnored private var gamepadHandlers: [ObjectIdentifier: GamepadHandler] = [:]
    @ObservationIgnored private var comboInterpreters: [ObjectIdentifier: HoldComboCommandInterpreter] = [:]
    @ObservationIgnored private var startupHapticsProbeControllers: Set<ObjectIdentifier> = []
    @ObservationIgnored private var didRunAppLaunchHapticsProbe = false
    @ObservationIgnored private var hapticsProbeTask: Task<Void, Never>?
    @ObservationIgnored private var activeInputQueue: InputQueue?
    @ObservationIgnored private var didConfigureControllerObservers = false
    init() {}

    func attach(_ dependencies: any InputControllerDependencies) {
        self.dependencies = dependencies
    }

    func setControllerSettings(_ settings: ControllerSettings) {
        controllerSettings = settings
    }

    public func updateControllerSettings(from settingsStore: SettingsStore) {
        var settings = settingsStore.buildControllerSettings()
        if settings.deadzone <= 0 {
            settings.deadzone = 0.15
        }
        if settings.triggerSensitivity <= 0 {
            settings.triggerSensitivity = 0.5
        }
        if settings.vibrationIntensity <= 0 {
            settings.vibrationIntensity = 1.0
        } else {
            settings.vibrationIntensity = min(settings.vibrationIntensity, 1.0)
        }
        controllerSettings = settings
    }

    public func startupHapticsProbeEnabled(from settingsStore: SettingsStore) -> Bool {
        settingsStore.diagnostics.startupHapticsProbeEnabled
    }

    func setupControllerObservation(inputQueue: InputQueue) {
        activeInputQueue = inputQueue

        for controller in GCController.controllers() {
            attachController(controller)
        }

        guard !didConfigureControllerObservers else { return }
        didConfigureControllerObservers = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleControllerDidConnectNotification(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleControllerDidDisconnectNotification(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }

    func runAppLaunchHapticsProbeIfNeeded(settingsStore: SettingsStore) {
        guard !didRunAppLaunchHapticsProbe else { return }
        didRunAppLaunchHapticsProbe = true

        guard startupHapticsProbeEnabled(from: settingsStore) else {
            logger.info("App launch haptics probe disabled by debug.controller.startup_haptics_probe=false")
            return
        }

        let connectedControllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        if connectedControllers.isEmpty {
            logger.info("App launch haptics probe: no extended controllers connected")
            return
        }

        for controller in connectedControllers {
            let probeHandler = GamepadHandler(gamepadIndex: 0)
            probeHandler.controller = controller
            probeHandler.settings = controllerSettings
            runStartupHapticsProbeIfNeeded(
                handler: probeHandler,
                controller: controller,
                controllerID: ObjectIdentifier(controller),
                settingsStore: settingsStore
            )
        }
    }

    func routeVibration(_ report: VibrationReport, settingsStore: SettingsStore) {
        guard settingsStore.controller.vibrationEnabled else { return }
        for handler in gamepadHandlers.values {
            handler.sendHaptics(from: report)
        }
    }

    func injectNeutralGamepadFrame(index: UInt8 = 0) {
        guard let session = dependencies?.currentStreamingSession() else { return }
        let frame = GamepadInputFrame(
            gamepadIndex: index,
            buttons: [],
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
        session.inputQueueRef.enqueueInjectedGamepadFrame(frame)
    }

    func injectPauseMenuTap(index: UInt8 = 0) {
        guard let session = dependencies?.currentStreamingSession() else { return }
        guard case .connected = session.lifecycle else { return }

        let pressed = GamepadInputFrame(
            gamepadIndex: index,
            buttons: [.menu],
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
        let released = GamepadInputFrame(
            gamepadIndex: index,
            buttons: [],
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
        let queue = session.inputQueueRef
        queue.enqueueInjectedGamepadFrame(pressed)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            queue.enqueueInjectedGamepadFrame(released)
        }

        logger.info("Injected synthetic Menu tap to request in-game pause")
    }

    private func injectNexusTap(into queue: InputQueue, index: UInt8 = 0) {
        let pressed = GamepadInputFrame(
            gamepadIndex: index,
            buttons: [.nexus],
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
        let released = GamepadInputFrame(
            gamepadIndex: index,
            buttons: [],
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )

        queue.enqueueInjectedGamepadFrame(pressed)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            queue.enqueueInjectedGamepadFrame(released)
        }
    }

    func clearStreamingInputBindings() {
        activeInputQueue = nil
    }

    func resetForSignOut() {
        clearStreamingInputBindings()
        comboInterpreters.values.forEach { $0.cancelAll() }
        comboInterpreters.removeAll()
        gamepadHandlers.removeAll()
        hapticsProbeTask?.cancel()
        hapticsProbeTask = nil
        startupHapticsProbeControllers.removeAll()
        didRunAppLaunchHapticsProbe = false
    }

    private func attachController(_ controller: GCController) {
        guard let queue = activeInputQueue else { return }
        guard let extended = controller.extendedGamepad else { return }
        configureControllerSystemGestureHandling(controller)
        let handler = GamepadHandler(gamepadIndex: 0)
        handler.controller = controller

        let controllerID = ObjectIdentifier(controller)
        gamepadHandlers[controllerID] = handler

        let controllerName = controller.vendorName ?? "Unknown"
        var didLogFirstControllerValueChange = false
        var previousAPressed = false
        var previousBPressed = false
        var chordRecognizer = ChordRecognizer(definitions: [
            ChordDefinition(buttons: [.leftShoulder, .rightShoulder], holdDurationMs: 0, action: .toggleStatsHUD)
        ])
        let comboInterpreter = HoldComboCommandInterpreter { [weak self] command in
            guard let self else { return }
            guard self.gamepadHandlers[controllerID] != nil else { return }

            switch command {
            case .nexusTap:
                self.logger.info("[INPUT] Combo fired: Start+Select hold → Nexus tap")
                self.injectNexusTap(into: queue, index: handler.gamepadIndex)
            case .overlayToggle:
                self.logger.info("[INPUT] Combo fired: L3+R3 hold → overlay toggle")
                self.dependencies?.requestOverlayToggle()
            }
        }
        comboInterpreters.removeValue(forKey: controllerID)?.cancelAll()
        comboInterpreters[controllerID] = comboInterpreter

        extended.valueChangedHandler = { [weak self] gamepad, _ in
            guard let self else { return }
            if !didLogFirstControllerValueChange {
                didLogFirstControllerValueChange = true
                self.logger.info("First controller valueChanged event: \(controllerName)")
            }

            let leftStickClickPressed = gamepad.leftThumbstickButton?.isPressed == true
            let rightStickClickPressed = gamepad.rightThumbstickButton?.isPressed == true
            let menuPressed = gamepad.buttonMenu.isPressed
            let optionsPressed = gamepad.buttonOptions?.isPressed == true
            let startSelectPressed = menuPressed && optionsPressed
            let l3r3Pressed = leftStickClickPressed && rightStickClickPressed

            comboInterpreter.update(startSelectPressed: startSelectPressed, l3r3Pressed: l3r3Pressed)

            let aPressed = gamepad.buttonA.isPressed
            let bPressed = gamepad.buttonB.isPressed

            if comboInterpreter.suppressesPrimaryInput {
                previousAPressed = aPressed
                previousBPressed = bPressed
                queue.enqueueGamepadFrame(handler.idleFrame())
                return
            }

            if self.dependencies?.isStreamOverlayVisible == true {
                if aPressed && !previousAPressed {
                    self.logger.info("Overlay shortcut: A -> disconnect stream")
                    self.dependencies?.requestDisconnect()
                } else if bPressed && !previousBPressed {
                    self.logger.info("Overlay shortcut: B -> close overlay")
                    self.dependencies?.requestOverlayToggle()
                }

                previousAPressed = aPressed
                previousBPressed = bPressed
                queue.enqueueGamepadFrame(handler.idleFrame())
                return
            }

            previousAPressed = aPressed
            previousBPressed = bPressed

            let settings = self.controllerSettings
            handler.settings = settings
            let frame = handler.readFrame(from: gamepad, settings: settings)
            let actions = chordRecognizer.process(frame: frame)
            if !actions.isEmpty {
                for action in actions {
                    guard action == .toggleStatsHUD else { continue }
                    self.logger.info("[INPUT] Chord fired: LB+RB → toggleStatsHUD")
                    self.dependencies?.toggleStatsHUD()
                }
                queue.enqueueGamepadFrame(handler.idleFrame())
                return
            }
            queue.enqueueGamepadFrame(frame)
        }

        dependencies?.currentStreamingSession()?.setGamepadConnectionState(index: 0, connected: true)
        logger.info("Controller attached: \(controller.vendorName ?? "Unknown")")
    }

    private func runStartupHapticsProbeIfNeeded(
        handler: GamepadHandler,
        controller: GCController,
        controllerID: ObjectIdentifier,
        settingsStore: SettingsStore
    ) {
        guard !startupHapticsProbeControllers.contains(controllerID) else { return }
        startupHapticsProbeControllers.insert(controllerID)

        guard startupHapticsProbeEnabled(from: settingsStore) else {
            logger.info("Controller startup haptics probe disabled by debug.controller.startup_haptics_probe=false")
            return
        }

        guard let haptics = controller.haptics else {
            logger.warning("Controller haptics unavailable: \(controller.vendorName ?? "Unknown")")
            return
        }

        let localities = haptics.supportedLocalities.map(\.rawValue).sorted().joined(separator: ",")
        let controllerName = controller.vendorName ?? "Unknown"
        logger.info("Controller haptics available: \(controllerName) localities=[\(localities)]")

        let probe = VibrationReport(
            gamepadIndex: 0,
            leftMotorPercent: 0.55,
            rightMotorPercent: 0.55,
            leftTriggerMotorPercent: 0,
            rightTriggerMotorPercent: 0,
            durationMs: 140,
            delayMs: 0,
            repeatCount: 0
        )
        handler.sendHaptics(from: probe)
        logger.info("Controller startup haptics probe pulse 1/2 fired: \(controllerName)")
        hapticsProbeTask?.cancel()
        hapticsProbeTask = Task { @MainActor [weak self, weak controller] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            guard self.startupHapticsProbeControllers.contains(controllerID) else { return }
            guard controller != nil else { return }
            handler.sendHaptics(from: probe)
            self.logger.info("Controller startup haptics probe pulse 2/2 fired: \(controllerName)")
        }
    }

    private func configureControllerSystemGestureHandling(_ controller: GCController) {
#if os(tvOS)
        guard #available(tvOS 14.0, *) else { return }

        let profile = controller.physicalInputProfile
        var disabledCount = 0

        for element in profile.allElements {
            guard element.isBoundToSystemGesture else { continue }
            if element.preferredSystemGestureState != .disabled {
                element.preferredSystemGestureState = .disabled
            }
            disabledCount += 1
        }

        if disabledCount > 0 {
            logger.info("Disabled tvOS system gestures for \(disabledCount) controller element(s): \(controller.vendorName ?? "Unknown")")
        }
#else
        _ = controller
#endif
    }

    @objc private func handleControllerDidConnectNotification(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        attachController(controller)
    }

    @objc private func handleControllerDidDisconnectNotification(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        let controllerID = ObjectIdentifier(controller)
        gamepadHandlers.removeValue(forKey: controllerID)
        comboInterpreters.removeValue(forKey: controllerID)?.cancelAll()
        startupHapticsProbeControllers.remove(controllerID)
        let isAnyExtendedControllerConnected = GCController.controllers().contains { $0.extendedGamepad != nil }
        dependencies?.currentStreamingSession()?.setGamepadConnectionState(
            index: 0,
            connected: isAnyExtendedControllerConnected
        )
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
