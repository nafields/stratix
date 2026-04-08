// InputPacket.swift
// Defines input packet.
//

import Foundation
import StratixModels

// MARK: - Report Type Bitmask
// Mirrors ReportTypes enum in packet.ts

public struct ReportType: OptionSet, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let none              = ReportType([])
    public static let metadata          = ReportType(rawValue: 1 << 0)   // 1
    public static let gamepad           = ReportType(rawValue: 1 << 1)   // 2
    public static let pointer           = ReportType(rawValue: 1 << 2)   // 4
    public static let clientMetadata    = ReportType(rawValue: 1 << 3)   // 8
    public static let serverMetadata    = ReportType(rawValue: 1 << 4)   // 16
    public static let mouse             = ReportType(rawValue: 1 << 5)   // 32
    public static let keyboard          = ReportType(rawValue: 1 << 6)   // 64
    public static let vibration         = ReportType(rawValue: 1 << 7)   // 128
    public static let sensor            = ReportType(rawValue: 1 << 8)   // 256
    public static let unreliableInput   = ReportType(rawValue: 1 << 9)   // 512
    public static let unreliableAck     = ReportType(rawValue: 1 << 10)  // 1024
}

// MARK: - Vibration Report (inbound from server)

public struct VibrationReport: Sendable {
    public let gamepadIndex: UInt8
    public let leftMotorPercent: Float       // 0.0 – 1.0
    public let rightMotorPercent: Float
    public let leftTriggerMotorPercent: Float
    public let rightTriggerMotorPercent: Float
    public let durationMs: UInt16
    public let delayMs: UInt16
    public let repeatCount: UInt8

    public init(
        gamepadIndex: UInt8,
        leftMotorPercent: Float,
        rightMotorPercent: Float,
        leftTriggerMotorPercent: Float,
        rightTriggerMotorPercent: Float,
        durationMs: UInt16,
        delayMs: UInt16,
        repeatCount: UInt8
    ) {
        self.gamepadIndex = gamepadIndex
        self.leftMotorPercent = leftMotorPercent
        self.rightMotorPercent = rightMotorPercent
        self.leftTriggerMotorPercent = leftTriggerMotorPercent
        self.rightTriggerMotorPercent = rightTriggerMotorPercent
        self.durationMs = durationMs
        self.delayMs = delayMs
        self.repeatCount = repeatCount
    }
}

// MARK: - InputPacket Builder
// Mirrors packet.ts — binary little-endian format sent over the input data channel.

public struct InputPacket: Sendable {

    // MARK: Packet header size
    private static let headerSize = 14

    // MARK: - Build ClientMetadata packet (sent once on channel open)
    // totalSize = 15 = header(14) + 1 byte for maxTouchPoints

    public static func clientMetadata(sequence: UInt32, maxTouchPoints: UInt8 = 1) -> Data {
        var buffer = makeHeaderBuffer(
            reportType: .clientMetadata,
            sequence: sequence,
            payloadSize: 1
        )
        buffer[headerSize] = maxTouchPoints
        return buffer
    }

    // MARK: - Build Gamepad + optional Metadata packet

    public static func gamepadPacket(
        sequence: UInt32,
        frames: [GamepadInputFrame],
        timingFrames: [FrameTimingMetadata] = []
    ) -> Data {
        var reportType = ReportType.none

        var metadataBytes = Data()
        if !timingFrames.isEmpty {
            reportType.insert(.metadata)
            metadataBytes = encodeMetadata(timingFrames)
        }

        var gamepadBytes = Data()
        if !frames.isEmpty {
            reportType.insert(.gamepad)
            gamepadBytes = encodeGamepads(frames)
        }

        var buffer = makeHeaderBuffer(
            reportType: reportType,
            sequence: sequence,
            payloadSize: metadataBytes.count + gamepadBytes.count
        )

        var offset = headerSize
        if !metadataBytes.isEmpty {
            buffer.replaceSubrange(offset..<(offset + metadataBytes.count), with: metadataBytes)
            offset += metadataBytes.count
        }
        if !gamepadBytes.isEmpty {
            buffer.replaceSubrange(offset..<(offset + gamepadBytes.count), with: gamepadBytes)
        }
        return buffer
    }

    // MARK: - Encode helpers

    /// Gamepad frame: 1 + count*(1+2+8+4+4) = 1 + count*23 bytes
    private static func encodeGamepads(_ frames: [GamepadInputFrame]) -> Data {
        // 1 byte count + 23 bytes per frame
        var data = Data(count: 1 + frames.count * 23)
        data[0] = UInt8(min(frames.count, 255))
        var offset = 1
        for frame in frames {
            data[offset] = frame.gamepadIndex
            offset += 1

            // Button mask (uint16 LE)
            data.writeLE(frame.buttons.rawValue, at: offset)
            offset += 2

            // Axes as int16 LE, scaled to ±32767; Y-axis inverted
            data.writeLE(normalizeAxis(frame.leftThumb.x), at: offset);   offset += 2
            data.writeLE(normalizeAxis(-frame.leftThumb.y), at: offset);  offset += 2
            data.writeLE(normalizeAxis(frame.rightThumb.x), at: offset);  offset += 2
            data.writeLE(normalizeAxis(-frame.rightThumb.y), at: offset); offset += 2

            // Triggers as uint16 LE, scaled to 0–65535
            data.writeLE(normalizeTrigger(frame.triggers.x), at: offset); offset += 2
            data.writeLE(normalizeTrigger(frame.triggers.y), at: offset); offset += 2

            // PhysicalPhysicality UInt32 LE = 1
            data.writeLE(UInt32(1), at: offset); offset += 4
            // VirtualPhysicality UInt32 BE = 1
            data.writeBE(UInt32(1), at: offset); offset += 4
        }
        return data
    }

    /// Metadata frame: 1 byte count + count*(7×4) bytes = 1 + count*28 bytes
    private static func encodeMetadata(_ frames: [FrameTimingMetadata]) -> Data {
        var data = Data(count: 1 + frames.count * 28)
        data[0] = UInt8(min(frames.count, 255))
        var offset = 1
        let nowMs = UInt32(currentTimestampMs())
        for frame in frames {
            data.writeLE(frame.serverDataKey, at: offset);                  offset += 4
            data.writeLE(frame.firstFramePacketArrivalTimeMs, at: offset);  offset += 4
            data.writeLE(frame.frameSubmittedTimeMs, at: offset);           offset += 4
            data.writeLE(frame.frameDecodedTimeMs, at: offset);             offset += 4
            data.writeLE(frame.frameRenderedTimeMs, at: offset);            offset += 4
            data.writeLE(nowMs, at: offset);                                 offset += 4  // framePacketTime
            data.writeLE(nowMs, at: offset);                                 offset += 4  // frameDateNow
        }
        return data
    }

    // MARK: - Inbound Parsing

    /// Parse a vibration report received from the server over the input data channel.
    public static func parseVibration(from data: Data) -> VibrationReport? {
        guard data.count >= 13 else { return nil }
        // Byte 0: reportType (128)
        // Byte 1: padding
        // Byte 2: rumbleType (0 = FourMotorRumble)
        let gamepadIndex = data[3]
        let left    = Float(data[4]) / 100.0
        let right   = Float(data[5]) / 100.0
        let leftT   = Float(data[6]) / 100.0
        let rightT  = Float(data[7]) / 100.0
        let durationMs: UInt16 = data.readLE(at: 8)
        let delayMs: UInt16    = data.readLE(at: 10)
        let repeatCount = data[12]
        return VibrationReport(
            gamepadIndex: gamepadIndex,
            leftMotorPercent: left,
            rightMotorPercent: right,
            leftTriggerMotorPercent: leftT,
            rightTriggerMotorPercent: rightT,
            durationMs: durationMs,
            delayMs: delayMs,
            repeatCount: repeatCount
        )
    }

    /// Parse server metadata (video dimensions) from input channel.
    /// Returns (width, height).
    public static func parseServerMetadata(from data: Data) -> (width: UInt32, height: UInt32)? {
        guard data.count >= 10 else { return nil }
        let height: UInt32 = data.readLE(at: 2)
        let width: UInt32  = data.readLE(at: 6)
        return (width, height)
    }

    // MARK: - Value normalization

    private static func normalizeAxis(_ value: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, value))
        return Int16(clamped * 32767.0)
    }

    private static func normalizeTrigger(_ value: Float) -> UInt16 {
        let clamped = max(0.0, min(1.0, value))
        return UInt16(clamped * 65535.0)
    }

    private static func makeHeaderBuffer(
        reportType: ReportType,
        sequence: UInt32,
        payloadSize: Int
    ) -> Data {
        var buffer = Data(count: headerSize + payloadSize)
        buffer.writeLE(reportType.rawValue, at: 0)
        buffer.writeLE(sequence, at: 2)
        buffer.writeLE(Double(currentTimestampMs()), at: 6)
        return buffer
    }

    private static func currentTimestampMs() -> Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1000)
    }
}

// MARK: - Data write helpers (little-endian / big-endian)

extension Data {
    mutating func writeLE(_ value: UInt16, at offset: Int) {
        self[offset]     = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
    }
    mutating func writeLE(_ value: Int16, at offset: Int) {
        let uval = UInt16(bitPattern: value)
        writeLE(uval, at: offset)
    }
    mutating func writeLE(_ value: UInt32, at offset: Int) {
        self[offset]     = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
        self[offset + 2] = UInt8((value >> 16) & 0xFF)
        self[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
    mutating func writeBE(_ value: UInt32, at offset: Int) {
        self[offset]     = UInt8((value >> 24) & 0xFF)
        self[offset + 1] = UInt8((value >> 16) & 0xFF)
        self[offset + 2] = UInt8((value >> 8) & 0xFF)
        self[offset + 3] = UInt8(value & 0xFF)
    }
    mutating func writeLE(_ value: Double, at offset: Int) {
        var v = value
        let bytes = Swift.withUnsafeBytes(of: &v) { Array($0) }
        for (i, b) in bytes.enumerated() {
            self[offset + i] = b
        }
    }
}

// MARK: - Data read helpers

extension Data {
    func readLE<T: FixedWidthInteger>(at offset: Int) -> T {
        var value: T = 0
        let range = offset..<(offset + MemoryLayout<T>.size)
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            self.copyBytes(to: dest, from: range)
        }
        return T(littleEndian: value)
    }
}
