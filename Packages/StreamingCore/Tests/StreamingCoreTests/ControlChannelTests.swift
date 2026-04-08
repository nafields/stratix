// ControlChannelTests.swift
// Exercises control channel behavior.
//

import Foundation
import Testing
import StratixModels
@testable import StreamingCore

@Suite(.serialized)
struct ControlChannelTests {
    @Test
    func onOpen_sendsAuthorizationGamepadHandshakeAndVideoPreference() async throws {
        let bridge = ControlChannelRecordingBridge()
        let channel = ControlChannel(bridge: bridge, keyframeIntervalSeconds: 0)

        await channel.configureVideoPreference(
            width: 2560,
            height: 1440,
            framesPerSecond: 120,
            colorRange: "Full"
        )
        await channel.onOpen()
        await channel.onOpen()

        #expect(bridge.sentTexts.count == 4)

        let authorization = try controlChannelJSONObject(from: bridge.sentTexts[0])
        #expect(authorization["message"] as? String == "authorizationRequest")
        #expect(authorization["accessKey"] as? String == "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E")

        let gamepadAdded = try controlChannelJSONObject(from: bridge.sentTexts[1])
        let gamepadRemoved = try controlChannelJSONObject(from: bridge.sentTexts[2])
        #expect(gamepadAdded["message"] as? String == "gamepadChanged")
        #expect(gamepadAdded["wasAdded"] as? Bool == true)
        #expect(gamepadRemoved["message"] as? String == "gamepadChanged")
        #expect(gamepadRemoved["wasAdded"] as? Bool == false)

        let videoPreference = try controlChannelJSONObject(from: bridge.sentTexts[3])
        #expect(videoPreference["message"] as? String == "VideoPreference")
        #expect(videoPreference["type"] as? String == "VideoPreference")
        #expect(videoPreference["maxFPS"] as? Int == 120)
        let resolution = try #require(videoPreference["resolution"] as? [String: Int])
        #expect(resolution["width"] == 2560)
        #expect(resolution["height"] == 1440)
        #expect(videoPreference["colorRange"] as? String == "full")
    }

    @Test
    func requestKeyframe_sendsExplicitMessage() async throws {
        let bridge = ControlChannelRecordingBridge()
        let channel = ControlChannel(bridge: bridge, keyframeIntervalSeconds: 0)

        await channel.requestKeyframe(ifrRequested: false)

        #expect(bridge.sentTexts.count == 1)
        let payload = try controlChannelJSONObject(from: bridge.sentTexts[0])
        #expect(payload["message"] as? String == "videoKeyframeRequested")
        #expect(payload["ifrRequested"] as? Bool == false)
    }

    @Test
    func destroy_cancelsPeriodicKeyframeRequests() async throws {
        let bridge = ControlChannelRecordingBridge()
        let channel = ControlChannel(bridge: bridge, keyframeIntervalSeconds: 1)

        await channel.onOpen()
        try? await Task.sleep(for: .milliseconds(100))
        await channel.destroy()
        let sentCountAfterDestroy = bridge.sentTexts.count

        try? await Task.sleep(for: .milliseconds(1_200))

        #expect(sentCountAfterDestroy == 4)
        #expect(bridge.sentTexts.count == sentCountAfterDestroy)
    }
}

private final class ControlChannelRecordingBridge: WebRTCBridge, @unchecked Sendable {
    var delegate: WebRTCBridgeDelegate?
    private let queue = DispatchQueue(label: "ControlChannelTests.RecordingStringBridge")
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

private func controlChannelJSONObject(from text: String) throws -> [String: Any] {
    let data = try #require(text.data(using: .utf8))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}
