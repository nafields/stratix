// ControlChannel.swift
// Defines control channel.
//

import Foundation
import os
import StratixModels

// MARK: - Control Channel
//
// Mirrors channel/control.ts — sends JSON control messages over the "control" data channel.
// Protocol label: "controlV1", ordered: true.
//
// Messages sent:
//   - authorizationRequest (on channel open)
//   - gamepadChanged (on controller connect/disconnect)
//   - VideoPreference (on channel open, after auth — tells server preferred resolution/FPS)
//   - videoKeyframeRequested (periodic, every ~5 seconds)

public actor ControlChannel {
    private let logger = Logger(subsystem: "com.stratix.app", category: "StreamingControl")

    // The fixed access key used by all xCloud clients
    private static let accessKey = "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E"

    public static let label = "control"
    public static let protocolName = "controlV1"

    private weak var bridge: (any WebRTCBridge)?
    private var keyframeTimer: Task<Void, Never>?
    private let keyframeIntervalSeconds: Int
    private var didRunOpenSequence = false

    /// Preferred video width — set from StreamingConfig.videoDimensionsHint before onOpen().
    private var preferredWidth: Int = 1920
    /// Preferred video height — set from StreamingConfig.videoDimensionsHint before onOpen().
    private var preferredHeight: Int = 1080
    /// Preferred frame rate — set from streaming settings before onOpen().
    private var preferredFPS: Int = 60
    /// Color range hint ("Limited" or "Full"). nil = omit from message (server decides).
    private var preferredColorRange: String? = nil

    public init(bridge: any WebRTCBridge, keyframeIntervalSeconds: Int = 5) {
        self.bridge = bridge
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
    }

    public func configureVideoPreference(
        width: Int,
        height: Int,
        framesPerSecond: Int,
        colorRange: String?
    ) {
        preferredWidth = width
        preferredHeight = height
        preferredFPS = framesPerSecond
        preferredColorRange = colorRange
    }

    // MARK: - Called by WebRTCBridge when channel opens

    public func onOpen() async {
        guard !didRunOpenSequence else { return }
        didRunOpenSequence = true
        logger.info("Control channel onOpen: sending authorization/startup handshake")
        await sendAuthorization()
        // Announce gamepad index 0 as connected, then disconnected (initial handshake per JS source)
        await sendGamepadChanged(index: 0, wasAdded: true)
        await sendGamepadChanged(index: 0, wasAdded: false)
        // Tell the server which resolution and frame rate we want
        await sendVideoPreference()

        if keyframeIntervalSeconds > 0 {
            startKeyframeTimer()
        }
    }

    // MARK: - Authorization

    private func sendAuthorization() async {
        let msg: [String: String] = [
            "message": "authorizationRequest",
            "accessKey": Self.accessKey
        ]
        await sendJSON(msg)
    }

    // MARK: - Gamepad state

    public func sendGamepadChanged(index: Int, wasAdded: Bool) async {
        logger.info("Control channel send gamepadChanged index=\(index, privacy: .public) wasAdded=\(wasAdded, privacy: .public)")
        let msg: [String: Any] = [
            "message": "gamepadChanged",
            "gamepadIndex": index,
            "wasAdded": wasAdded
        ]
        await sendJSONAny(msg)
    }

    // MARK: - Video preference

    private func sendVideoPreference() async {
        var msg: [String: Any] = [
            "message": "VideoPreference",
            "type": "VideoPreference",
            // Send both keys for compatibility while aligning with the documented payload.
            "resolution": ["width": preferredWidth, "height": preferredHeight],
            "dimensions": ["width": preferredWidth, "height": preferredHeight],
            "maxFPS": preferredFPS
        ]
        // Include color range hint when user has explicitly chosen Limited or Full
        if let colorRange = preferredColorRange {
            msg["colorRange"] = colorRange.lowercased()
        }
        await sendJSONAny(msg)
    }

    // MARK: - Keyframe requests

    private func startKeyframeTimer() {
        keyframeTimer?.cancel()
        let keyframeIntervalSeconds = self.keyframeIntervalSeconds
        keyframeTimer = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(keyframeIntervalSeconds))
                guard !Task.isCancelled else { break }
                await self.requestKeyframe()
            }
        }
    }

    public func requestKeyframe(ifrRequested: Bool = true) async {
        let msg: [String: Any] = [
            "message": "videoKeyframeRequested",
            "ifrRequested": ifrRequested
        ]
        await sendJSONAny(msg)
    }

    // MARK: - Helpers

    private func sendJSON(_ dict: [String: String]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await bridge?.sendString(channelKind: .control, text: text)
    }

    private func sendJSONAny(_ dict: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await bridge?.sendString(channelKind: .control, text: text)
    }

    // MARK: - Cleanup

    public func destroy() {
        keyframeTimer?.cancel()
        keyframeTimer = nil
        didRunOpenSequence = false
    }
}
