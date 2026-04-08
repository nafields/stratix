// MessageChannelTests.swift
// Exercises message channel behavior.
//

import Foundation
import Testing
import StratixModels
@testable import StreamingCore

@Suite(.serialized)
struct MessageChannelTests {
    @Test
    func onChannelOpen_sendsHandshakeOnce() async throws {
        let bridge = RecordingStringBridge()
        let channel = MessageChannel(bridge: bridge)

        await channel.onChannelOpen()
        await channel.onChannelOpen()

        #expect(bridge.sentTexts.count == 1)

        let payload = try jsonObject(from: bridge.sentTexts[0])
        #expect(payload["type"] as? String == "Handshake")
        #expect(payload["version"] as? String == "messageV1")
        #expect(payload["id"] as? String == "be0bfc6d-1e83-4c8a-90ed-fa8601c5a179")
        #expect(payload["cv"] as? String == "0")
    }

    @Test
    func handshakeAck_sendsInitialConfigAndServerDisconnectAcknowledgement() async throws {
        let bridge = RecordingStringBridge()
        let channel = MessageChannel(
            bridge: bridge,
            initialDimensions: .init(width: 2560, height: 1440)
        )
        let callbackState = CallbackRecorder()
        await channel.configure(
            onHandshakeCompleted: {
                callbackState.markHandshakeCompleted()
            },
            onServerInitiatedDisconnect: {
                callbackState.markServerDisconnectReceived()
            }
        )

        await channel.onChannelOpen()
        await channel.onTextMessage(text: #"{"type":"HandshakeAck"}"#)

        #expect(callbackState.didCompleteHandshake)
        #expect(bridge.sentTexts.count == 7)

        let startupTargets = try bridge.sentTexts.dropFirst().map { text in
            try #require(jsonObject(from: text)["target"] as? String)
        }
        #expect(startupTargets == [
            "/streaming/systemUi/configuration",
            "/streaming/properties/clientappinstallidchanged",
            "/streaming/characteristics/orientationchanged",
            "/streaming/characteristics/touchinputenabledchanged",
            "/streaming/characteristics/clientdevicecapabilities",
            "/streaming/characteristics/dimensionschanged"
        ])

        let dimensionsEnvelope = try jsonObject(from: bridge.sentTexts[6])
        let dimensionsContent = try #require(dimensionsEnvelope["content"] as? String)
        let dimensionsPayload = try jsonObject(from: dimensionsContent)
        #expect(dimensionsPayload["preferredWidth"] as? Int == 2560)
        #expect(dimensionsPayload["preferredHeight"] as? Int == 1440)

        await channel.onTextMessage(
            text: #"{"type":"TransactionStart","target":"/streaming/sessionLifetimeManagement/serverInitiatedDisconnect","id":"disconnect-1","content":""}"#
        )

        #expect(callbackState.didReceiveServerDisconnect)
        #expect(bridge.sentTexts.count == 8)

        let disconnectAck = try jsonObject(from: bridge.sentTexts[7])
        #expect(disconnectAck["type"] as? String == "TransactionComplete")
        #expect(disconnectAck["id"] as? String == "disconnect-1")
        #expect(disconnectAck["content"] as? String == "")
    }
}

private final class CallbackRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MessageChannelTests.CallbackRecorder")
    private var _didCompleteHandshake = false
    private var _didReceiveServerDisconnect = false

    var didCompleteHandshake: Bool {
        queue.sync { _didCompleteHandshake }
    }

    var didReceiveServerDisconnect: Bool {
        queue.sync { _didReceiveServerDisconnect }
    }

    func markHandshakeCompleted() {
        queue.sync { _didCompleteHandshake = true }
    }

    func markServerDisconnectReceived() {
        queue.sync { _didReceiveServerDisconnect = true }
    }
}

private final class RecordingStringBridge: WebRTCBridge, @unchecked Sendable {
    var delegate: WebRTCBridgeDelegate?
    private let queue = DispatchQueue(label: "RecordingStringBridge.sentTexts")
    private var texts: [String] = []

    var sentTexts: [String] {
        queue.sync { texts }
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

    func send(channelKind _: DataChannelKind, data _: Data) async {}

    func sendString(channelKind: DataChannelKind, text: String) async {
        queue.sync {
            texts.append(text)
        }
    }

    func dataChannelRuntimeStats(channelKind: DataChannelKind) -> DataChannelRuntimeStats? {
        nil
    }

    func close() async {}

    func collectStats() async -> StreamingStatsSnapshot {
        StreamingStatsSnapshot()
    }
}

private func jsonObject(from text: String) throws -> [String: Any] {
    let data = try #require(text.data(using: .utf8))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}
