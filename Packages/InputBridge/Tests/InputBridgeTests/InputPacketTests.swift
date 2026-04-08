// InputPacketTests.swift
// Exercises input packet behavior.
//

import Testing
import Foundation
@testable import InputBridge
import StratixModels

// MARK: - InputPacket Tests
//
// Verifies the binary protocol format against known-good values
// derived from the JavaScript reference implementation (packet.ts).

@Suite
struct InputPacketTests {

    // MARK: - ClientMetadata Packet

    @Test func clientMetadata_hasCorrectSize() {
        let data = InputPacket.clientMetadata(sequence: 0)
        #expect(data.count == 15, "ClientMetadata packet must be exactly 15 bytes")
    }

    @Test func clientMetadata_reportTypeIsClientMetadata() {
        let data = InputPacket.clientMetadata(sequence: 0)
        // Bytes 0-1: reportType LE = 8 (clientMetadata)
        let reportType = UInt16(data[0]) | (UInt16(data[1]) << 8)
        #expect(reportType == 8, "ReportType should be 8 (ClientMetadata)")
    }

    @Test func clientMetadata_sequenceFieldMatchesInput() {
        let data = InputPacket.clientMetadata(sequence: 42)
        // Bytes 2-5: sequence LE
        let seq = UInt32(data[2]) | (UInt32(data[3]) << 8) | (UInt32(data[4]) << 16) | (UInt32(data[5]) << 24)
        #expect(seq == 42)
    }

    @Test func clientMetadata_maxTouchpointsAtOffset14() {
        let data = InputPacket.clientMetadata(sequence: 0, maxTouchPoints: 3)
        #expect(data[14] == 3)
    }

    @Test func clientMetadata_defaultMaxTouchpoints() {
        let data = InputPacket.clientMetadata(sequence: 0)
        #expect(data[14] == 1)
    }

    // MARK: - Gamepad Packet

    @Test func gamepadPacket_withNoFrames_returnsHeaderOnly() {
        // Empty frames -> reportType = none (0), only header (14 bytes)
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [])
        #expect(data.count == 14, "Empty gamepad packet should be 14 bytes (header only)")
    }

    @Test func gamepadPacket_withOneFrame_hasCorrectSize() {
        let frame = makeIdleFrame()
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [frame])
        // header(14) + gamepad section: 1 byte count + 23 bytes per frame
        let expectedSize = 14 + 1 + 23
        #expect(data.count == expectedSize)
    }

    @Test func gamepadPacket_reportTypeIncludesGamepad() {
        let frame = makeIdleFrame()
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [frame])
        let reportType = UInt16(data[0]) | (UInt16(data[1]) << 8)
        // ReportType.gamepad = 2
        #expect(reportType & 2 != 0, "ReportType must include Gamepad (2)")
    }

    @Test func gamepadPacket_gamepadIndexWrittenCorrectly() {
        let frame = GamepadInputFrame(
            gamepadIndex: 2,
            buttons: [],
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [frame])
        // offset 14: gamepad count byte = 1
        // offset 15: gamepadIndex
        #expect(data[14] == 1)   // count
        #expect(data[15] == 2)   // gamepadIndex
    }

    @Test func gamepadPacket_buttonMask_aButtonSetsBit4() {
        let frame = GamepadInputFrame(
            gamepadIndex: 0,
            buttons: .a,     // bit 4 = 0x10
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [frame])
        // offset 16-17: button mask LE
        let mask = UInt16(data[16]) | (UInt16(data[17]) << 8)
        #expect(mask & 0x0010 == 0x0010, "A button should set bit 4 (0x0010)")
    }

    @Test func gamepadPacket_nexusButton() {
        let frame = GamepadInputFrame(
            gamepadIndex: 0,
            buttons: .nexus,   // bit 1 = 0x0002
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [frame])
        let mask = UInt16(data[16]) | (UInt16(data[17]) << 8)
        #expect(mask & 0x0002 == 0x0002)
    }

    @Test func gamepadPacket_noButtonsProducesZeroMask() {
        let frame = makeIdleFrame()
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [frame])
        let mask = UInt16(data[16]) | (UInt16(data[17]) << 8)
        #expect(mask == 0)
    }

    @Test func gamepadPacket_leftTriggerMaxValue() {
        let frame = GamepadInputFrame(
            gamepadIndex: 0,
            buttons: [],
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: SIMD2(1.0, 0.0)   // left trigger = 1.0 -> 65535
        )
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [frame])
        // Left trigger is at offset 25-26 relative to packet start
        // header(14) + count(1) + gamepadIndex(1) + buttonMask(2) + 4axes(8) = offset 26 from start
        let ltLow  = UInt16(data[26])
        let ltHigh = UInt16(data[27])
        let lt = ltLow | (ltHigh << 8)
        #expect(lt == 65535)
    }

    @Test func gamepadPacket_rightTriggerZero() {
        let frame = makeIdleFrame()
        let data = InputPacket.gamepadPacket(sequence: 0, frames: [frame])
        let rtLow  = UInt16(data[28])
        let rtHigh = UInt16(data[29])
        let rt = rtLow | (rtHigh << 8)
        #expect(rt == 0)
    }

    @Test func gamepadPacket_multipleFrames() {
        let frames = [makeIdleFrame(), makeIdleFrame()]
        let data = InputPacket.gamepadPacket(sequence: 0, frames: frames)
        // header(14) + count(1) + 2 x 23 bytes
        #expect(data.count == 14 + 1 + 46)
        #expect(data[14] == 2)  // count
    }

    @Test func sequenceMonotonicallyIncreases() {
        let queue = InputQueue()
        let frame = makeIdleFrame()
        queue.enqueueGamepadFrame(frame)
        let p1 = queue.flush()!
        queue.enqueueGamepadFrame(frame)
        let p2 = queue.flush()!
        let seq1 = UInt32(p1[2]) | (UInt32(p1[3]) << 8) | (UInt32(p1[4]) << 16) | (UInt32(p1[5]) << 24)
        let seq2 = UInt32(p2[2]) | (UInt32(p2[3]) << 8) | (UInt32(p2[4]) << 16) | (UInt32(p2[5]) << 24)
        #expect(seq2 == seq1 + 1)
    }

    @Test func sequenceProgressesAcrossInitialMetadataAndFlush() {
        let queue = InputQueue()

        let metadata = queue.makeInitialMetadata()
        queue.enqueueGamepadFrame(makeIdleFrame())
        let packet = queue.flush()!

        let metadataSeq = UInt32(metadata[2]) | (UInt32(metadata[3]) << 8) | (UInt32(metadata[4]) << 16) | (UInt32(metadata[5]) << 24)
        let packetSeq = UInt32(packet[2]) | (UInt32(packet[3]) << 8) | (UInt32(packet[4]) << 16) | (UInt32(packet[5]) << 24)

        #expect(packetSeq == metadataSeq + 1)
    }

    // MARK: - Vibration Parsing

    @Test func parseVibration_correctValues() {
        var raw = Data(count: 13)
        raw[0] = 128  // reportType = vibration
        raw[3] = 1    // gamepadIndex
        raw[4] = 50   // leftMotorPercent * 100
        raw[5] = 75   // rightMotorPercent * 100
        raw[6] = 25   // leftTriggerMotorPercent * 100
        raw[7] = 100  // rightTriggerMotorPercent * 100
        // durationMs: LE uint16 at offset 8 = 500
        raw[8] = 244; raw[9] = 1    // 500 LE
        // delayMs: LE uint16 at offset 10 = 100
        raw[10] = 100; raw[11] = 0
        raw[12] = 3   // repeat

        let report = InputPacket.parseVibration(from: raw)
        #expect(report != nil)
        #expect(report!.gamepadIndex == 1)
        #expect(abs(report!.leftMotorPercent - 0.5) < 0.01)
        #expect(abs(report!.rightMotorPercent - 0.75) < 0.01)
        #expect(report!.durationMs == 500)
        #expect(report!.delayMs == 100)
        #expect(report!.repeatCount == 3)
    }

    @Test func parseVibration_tooShort_returnsNil() {
        let raw = Data(count: 5)
        #expect(InputPacket.parseVibration(from: raw) == nil)
    }

    // MARK: - Server Metadata Parsing

    @Test func parseServerMetadata_correctWidthHeight() {
        var raw = Data(count: 10)
        raw[0] = 16  // reportType = serverMetadata
        // height at offset 2, LE uint32 = 1080
        raw[2] = 0x38; raw[3] = 0x04; raw[4] = 0; raw[5] = 0
        // width at offset 6, LE uint32 = 1920
        raw[6] = 0x80; raw[7] = 0x07; raw[8] = 0; raw[9] = 0
        let result = InputPacket.parseServerMetadata(from: raw)
        #expect(result != nil)
        #expect(result!.height == 1080)
        #expect(result!.width == 1920)
    }

    // MARK: - Helpers

    private func makeIdleFrame(index: UInt8 = 0) -> GamepadInputFrame {
        GamepadInputFrame(gamepadIndex: index, buttons: [], leftThumb: .zero, rightThumb: .zero, triggers: .zero)
    }
}
