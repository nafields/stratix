// InputModels.swift
// Defines the input models.
//

import Foundation

/// Bitset representation of the Xbox-style controller buttons carried over the input channel.
public struct GamepadButtons: OptionSet, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let nexus = GamepadButtons(rawValue: 1 << 1)
    public static let menu = GamepadButtons(rawValue: 1 << 2)
    public static let view = GamepadButtons(rawValue: 1 << 3)
    public static let a = GamepadButtons(rawValue: 1 << 4)
    public static let b = GamepadButtons(rawValue: 1 << 5)
    public static let x = GamepadButtons(rawValue: 1 << 6)
    public static let y = GamepadButtons(rawValue: 1 << 7)
    public static let dpadUp = GamepadButtons(rawValue: 1 << 8)
    public static let dpadDown = GamepadButtons(rawValue: 1 << 9)
    public static let dpadLeft = GamepadButtons(rawValue: 1 << 10)
    public static let dpadRight = GamepadButtons(rawValue: 1 << 11)
    public static let leftShoulder = GamepadButtons(rawValue: 1 << 12)
    public static let rightShoulder = GamepadButtons(rawValue: 1 << 13)
    public static let leftThumb = GamepadButtons(rawValue: 1 << 14)
    public static let rightThumb = GamepadButtons(rawValue: 1 << 15)
}

/// One sampled controller state ready to serialize into the streaming input protocol.
public struct GamepadInputFrame: Sendable, Equatable {
    public let gamepadIndex: UInt8
    public let buttons: GamepadButtons
    public let leftThumb: SIMD2<Float>
    public let rightThumb: SIMD2<Float>
    public let triggers: SIMD2<Float>

    public init(gamepadIndex: UInt8, buttons: GamepadButtons, leftThumb: SIMD2<Float>, rightThumb: SIMD2<Float>, triggers: SIMD2<Float>) {
        self.gamepadIndex = gamepadIndex
        self.buttons = buttons
        self.leftThumb = leftThumb
        self.rightThumb = rightThumb
        self.triggers = triggers
    }
}

// MARK: - Controller Settings

/// User-configurable controller input settings.
/// Passed into GamepadHandler.readFrame(from:settings:) on each poll.
public struct ControllerSettings: Sendable {
    /// Controls how partially-analog triggers are interpreted before they are serialized.
    public enum TriggerInterpretationMode: String, Sendable, CaseIterable {
        case auto = "Auto"
        case digitalFallback = "Compatibility"
        case analogOnly = "Analog"
    }

    /// Radial deadzone radius (0.0–1.0). Stick values below this are zeroed.
    public var deadzone: Float = 0.15
    /// When true, left and right stick Y axes are negated.
    public var invertY: Bool = false
    /// When true, the A and B face buttons are swapped in the output frame.
    public var swapAB: Bool = false
    /// Trigger sensitivity (0.0–1.0). Lower values = more sensitive (hair trigger).
    /// 0.5 = half pull = full output, which matches the guide's default slider.
    public var triggerSensitivity: Float = 0.5
    /// Trigger interpretation mode.
    /// Auto chooses analog by default, then uses digital fallback for controllers
    /// that report pressed triggers without analog travel values.
    public var triggerInterpretationMode: TriggerInterpretationMode = .auto
    /// Haptic/vibration multiplier (0.0–1.0).
    public var vibrationIntensity: Float = 1.0
    public init() {}
}
