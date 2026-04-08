// InputChannelTests.swift
// Exercises input channel behavior.
//

import Foundation
import Testing
import StratixModels
@testable import InputBridge
@testable import StreamingCore

@Suite(.serialized)
struct InputChannelTests {
    @Test
    func onOpen_sendsMetadataImmediatelyAndFlushesLatestQueuedFrame() async throws {
        let bridge = RecordingBridge()
        let queue = InputQueue()
        let channel = InputChannel(bridge: bridge, queue: queue)

        queue.enqueueGamepadFrame(gamepadFrame(buttons: .a))
        queue.enqueueGamepadFrame(gamepadFrame(buttons: .b))

        await channel.onOpen()
        try? await Task.sleep(for: .milliseconds(40))
        channel.destroy()

        let sentPackets = bridge.sentPackets
        #expect(sentPackets.count == 2)
        #expect(sentPackets[0].count == 15)

        let gamepadPacket = sentPackets[1]
        let reportType = UInt16(gamepadPacket[0]) | (UInt16(gamepadPacket[1]) << 8)
        let buttonMask = UInt16(gamepadPacket[16]) | (UInt16(gamepadPacket[17]) << 8)

        #expect(reportType & 2 != 0)
        #expect(buttonMask & GamepadButtons.b.rawValue == GamepadButtons.b.rawValue)
        #expect(buttonMask & GamepadButtons.a.rawValue == 0)
    }

    @Test
    func slowSend_keepsPollingAndCoalescesFreshState() async throws {
        let bridge = RecordingBridge(sendDelay: .milliseconds(50))
        let queue = InputQueue()
        let channel = InputChannel(bridge: bridge, queue: queue)

        queue.enqueueGamepadFrame(gamepadFrame(buttons: .a))
        await channel.onOpen()

        try? await Task.sleep(for: .milliseconds(20))
        queue.enqueueGamepadFrame(gamepadFrame(buttons: .b))
        try? await Task.sleep(for: .milliseconds(12))
        queue.enqueueGamepadFrame(gamepadFrame(buttons: .x))
        try? await Task.sleep(for: .milliseconds(90))
        channel.destroy()

        let sentPackets = bridge.sentPackets
        #expect(sentPackets.count == 3)

        let secondGamepadPacket = sentPackets[2]
        let secondSequence = packetSequence(secondGamepadPacket)
        let secondButtonMask = UInt16(secondGamepadPacket[16]) | (UInt16(secondGamepadPacket[17]) << 8)

        // Metadata uses sequence 0 and the first gamepad packet uses sequence 1.
        // CI can still coalesce to the freshest state with a follow-up sequence of 2.
        #expect(secondSequence >= 2)
        #expect(secondButtonMask & GamepadButtons.x.rawValue == GamepadButtons.x.rawValue)
        #expect(secondButtonMask & GamepadButtons.b.rawValue == 0)
    }

    @Test
    func destroy_beforeInitialMetadataSendCompletes_doesNotStartLoop() async throws {
        let bridge = RecordingBridge(sendDelay: .milliseconds(50))
        let queue = InputQueue()
        let channel = InputChannel(bridge: bridge, queue: queue)

        let openTask = Task {
            await channel.onOpen()
        }

        try? await Task.sleep(for: .milliseconds(20))
        queue.enqueueGamepadFrame(gamepadFrame(buttons: .a))
        channel.destroy()
        await openTask.value
        try? await Task.sleep(for: .milliseconds(120))

        #expect(bridge.sentPackets.count == 1)
        #expect(bridge.sentPackets[0].count == 15)
    }

    @Test
    func inboundCallbacks_areRoutedThroughLockBackedHooks() async throws {
        let bridge = RecordingBridge()
        let queue = InputQueue()
        let channel = InputChannel(bridge: bridge, queue: queue)
        let recorder = CallbackRecorder()

        channel.configure(
            onVibration: { report in
                recorder.recordVibration(report)
            },
            onServerMetadata: { width, height in
                recorder.recordServerMetadata(width: width, height: height)
            },
            shouldLogRawInboundMetadata: {
                recorder.noteRawMetadataLogCheck()
                return recorder.shouldLogRawInboundMetadata
            }
        )

        recorder.shouldLogRawInboundMetadata = true
        await channel.onOpen()

        var vibration = Data(count: 13)
        vibration[0] = 128
        vibration[3] = 7
        vibration[4] = 80
        vibration[5] = 20
        vibration[6] = 10
        vibration[7] = 5
        vibration[8] = 0x34
        vibration[9] = 0x12
        vibration[10] = 0x78
        vibration[11] = 0x56
        vibration[12] = 3

        var metadata = Data(count: 10)
        metadata[0] = 16
        metadata[2] = 0x20
        metadata[3] = 0x03
        metadata[6] = 0x00
        metadata[7] = 0x05

        channel.onMessage(data: vibration)
        channel.onMessage(data: metadata)

        #expect(recorder.vibrationReports.count == 1)
        #expect(recorder.vibrationReports.first?.gamepadIndex == 7)
        #expect(recorder.serverMetadata.count == 1)
        let receivedMetadata = try #require(recorder.serverMetadata.first)
        #expect(receivedMetadata.0 == 1280)
        #expect(receivedMetadata.1 == 800)
        #expect(recorder.rawMetadataLogChecks == 1)
    }

    @Test
    func destroy_preventsLateInboundCallbacks() async {
        let bridge = RecordingBridge()
        let queue = InputQueue()
        let channel = InputChannel(bridge: bridge, queue: queue)
        let recorder = CallbackRecorder()

        channel.configure(
            onVibration: { report in
                recorder.recordVibration(report)
            },
            onServerMetadata: { width, height in
                recorder.recordServerMetadata(width: width, height: height)
            }
        )
        await channel.onOpen()
        channel.destroy()

        channel.onMessage(data: vibrationPacket())
        channel.onMessage(data: serverMetadataPacket(width: 1920, height: 1080))

        #expect(recorder.vibrationReports.isEmpty)
        #expect(recorder.serverMetadata.isEmpty)
    }
}

private final class RecordingBridge: WebRTCBridge, @unchecked Sendable {
    var delegate: WebRTCBridgeDelegate?
    private let queue = DispatchQueue(label: "RecordingBridge.sentPackets")
    private var packets: [Data] = []
    private let sendDelay: Duration

    init(sendDelay: Duration = .zero) {
        self.sendDelay = sendDelay
    }

    var sentPackets: [Data] {
        queue.sync { packets }
    }

    func createOffer() async -> SessionDescription {
        fatalError("not used")
    }

    func applyH264CodecPreferences() {}

    func setLocalDescription(_ _: SessionDescription) async {}

    func setRemoteDescription(_ _: SessionDescription) async {}

    func addRemoteIceCandidate(_ _: IceCandidatePayload) async {}

    var localIceCandidates: [IceCandidatePayload] {
        get async { [] }
    }

    var connectionState: PeerConnectionState {
        get async { .connected }
    }

    func send(channelKind: DataChannelKind, data: Data) async throws {
        if sendDelay > .zero {
            try? await Task.sleep(for: sendDelay)
        }
        queue.sync {
            packets.append(data)
        }
    }

    func sendString(channelKind _: DataChannelKind, text _: String) async {}

    func dataChannelRuntimeStats(channelKind: DataChannelKind) -> DataChannelRuntimeStats? {
        nil
    }

    func close() async {}

    func collectStats() async -> StreamingStatsSnapshot {
        StreamingStatsSnapshot()
    }
}

private func gamepadFrame(buttons: GamepadButtons) -> GamepadInputFrame {
    GamepadInputFrame(
        gamepadIndex: 0,
        buttons: buttons,
        leftThumb: .zero,
        rightThumb: .zero,
        triggers: .zero
    )
}

private func packetSequence(_ data: Data) -> UInt32 {
    UInt32(data[2])
        | (UInt32(data[3]) << 8)
        | (UInt32(data[4]) << 16)
        | (UInt32(data[5]) << 24)
}

private func vibrationPacket() -> Data {
    var data = Data(count: 13)
    data[0] = 128
    data[3] = 1
    data[4] = 50
    data[5] = 75
    data.writeLE(UInt16(250), at: 8)
    data.writeLE(UInt16(0), at: 10)
    data[12] = 1
    return data
}

private func serverMetadataPacket(width: UInt32, height: UInt32) -> Data {
    var data = Data(count: 10)
    data.writeLE(ReportType.serverMetadata.rawValue, at: 0)
    data.writeLE(height, at: 2)
    data.writeLE(width, at: 6)
    return data
}

private final class CallbackRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "InputChannelTests.CallbackRecorder")
    private var storage = Storage()

    var shouldLogRawInboundMetadata: Bool {
        get { queue.sync { storage.shouldLogRawInboundMetadata } }
        set { queue.sync { storage.shouldLogRawInboundMetadata = newValue } }
    }

    var vibrationReports: [VibrationReport] {
        queue.sync { storage.vibrationReports }
    }

    var serverMetadata: [(UInt32, UInt32)] {
        queue.sync { storage.serverMetadata }
    }

    var rawMetadataLogChecks: Int {
        queue.sync { storage.rawMetadataLogChecks }
    }

    func recordVibration(_ report: VibrationReport) {
        queue.sync {
            storage.vibrationReports.append(report)
        }
    }

    func recordServerMetadata(width: UInt32, height: UInt32) {
        queue.sync {
            storage.serverMetadata.append((width, height))
        }
    }

    func noteRawMetadataLogCheck() {
        queue.sync {
            storage.rawMetadataLogChecks += 1
        }
    }

    private struct Storage {
        var shouldLogRawInboundMetadata = false
        var vibrationReports: [VibrationReport] = []
        var serverMetadata: [(UInt32, UInt32)] = []
        var rawMetadataLogChecks = 0
    }
}
