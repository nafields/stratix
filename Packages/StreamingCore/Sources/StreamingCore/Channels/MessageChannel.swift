// MessageChannel.swift
// Defines message channel.
//

import Foundation
import StratixModels

// MARK: - Message Channel
//
// Mirrors channel/message.ts — handles JSON protocol messages from the server.
// Used for stream-level messaging (e.g. disconnect notifications, quality changes).

public actor MessageChannel {
    public typealias MessageObserver = @Sendable (String) -> Void
    public typealias HandshakeObserver = @Sendable () -> Void
    public typealias ProtocolMessageObserver = @Sendable (ProtocolMessageEvent) -> Void
    public typealias DisconnectObserver = @Sendable () -> Void
    public typealias LoggingObserver = @Sendable () -> Bool

    public static let label = "message"
    public static let protocolName = "messageV1"
    private static let handshakeVersion = "messageV1"
    private static let fixedHandshakeID = "be0bfc6d-1e83-4c8a-90ed-fa8601c5a179"
    private static let fixedClientAppInstallID = "c97d7ee0-73b2-4239-bf1d-9d805a338429"

    /// Called with parsed JSON message events received from the server.
    private var onMessage: MessageObserver?
    /// Fired once the message channel handshake completes.
    private var onHandshakeCompleted: HandshakeObserver?
    /// Fired for typed Message/TransactionStart envelopes.
    private var onProtocolMessage: ProtocolMessageObserver?
    /// Fired when the server requests a disconnect.
    private var onServerInitiatedDisconnect: DisconnectObserver?
    /// Temporary startup tracing hook. Fired once on the first outbound message.
    private var onFirstOutboundMessage: HandshakeObserver?
    /// Temporary startup tracing hook. When true, inbound message JSON is logged verbatim.
    private var shouldLogRawInboundMessages: LoggingObserver?

    private weak var bridge: (any WebRTCBridge)?
    private var dimensions: StreamDimensions
    private var handshakeStarted = false
    private var handshakeCompleted = false
    private var lastSentDimensions: StreamDimensions?
    private var didReportFirstOutboundMessage = false

    public init(bridge: any WebRTCBridge, initialDimensions: StreamDimensions = .init(width: 1920, height: 1080)) {
        self.bridge = bridge
        self.dimensions = initialDimensions
    }

    public func configure(
        onMessage: MessageObserver? = nil,
        onHandshakeCompleted: HandshakeObserver? = nil,
        onProtocolMessage: ProtocolMessageObserver? = nil,
        onServerInitiatedDisconnect: DisconnectObserver? = nil,
        onFirstOutboundMessage: HandshakeObserver? = nil,
        shouldLogRawInboundMessages: LoggingObserver? = nil
    ) {
        self.onMessage = onMessage
        self.onHandshakeCompleted = onHandshakeCompleted
        self.onProtocolMessage = onProtocolMessage
        self.onServerInitiatedDisconnect = onServerInitiatedDisconnect
        self.onFirstOutboundMessage = onFirstOutboundMessage
        self.shouldLogRawInboundMessages = shouldLogRawInboundMessages
    }

    public func onChannelOpen() async {
        guard !handshakeStarted else { return }
        handshakeStarted = true
        let handshake: [String: Any] = [
            "type": "Handshake",
            "version": Self.handshakeVersion,
            "id": Self.fixedHandshakeID,
            "cv": "0"
        ]
        await sendJSONAny(handshake)
    }

    public func onTextMessage(text: String) async {
        onMessage?(text)

        if shouldLogRawInboundMessages?() == true {
            print("[MessageChannel][RawInbound] envelope=\(text)")
        }

        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }

        if shouldLogRawInboundMessages?() == true,
           let target = object["target"] as? String,
           let content = object["content"] {
            if let contentString = content as? String {
                print("[MessageChannel][RawInbound] target=\(target) content=\(contentString)")
            } else {
                print("[MessageChannel][RawInbound] target=\(target) content=\(content)")
            }
        }

        switch type {
        case "HandshakeAck":
            guard !handshakeCompleted else { return }
            handshakeCompleted = true
            await sendInitialClientConfig()
            onHandshakeCompleted?()

        case "TransactionStart", "Message":
            if let target = object["target"] as? String {
                onProtocolMessage?(ProtocolMessageEvent(target: target, payload: text))
                await handleTransactionIfNeeded(object, target: target)
            }

        default:
            break
        }
    }

    public func destroy() {
        handshakeStarted = false
        handshakeCompleted = false
        lastSentDimensions = nil
        didReportFirstOutboundMessage = false
    }

    // MARK: - Message protocol helpers

    private func sendInitialClientConfig() async {
        await sendGeneratedMessage(
            target: "/streaming/systemUi/configuration",
            content: [
                "version": [0, 2, 0],
                "systemUis": []
            ]
        )

        await sendGeneratedMessage(
            target: "/streaming/properties/clientappinstallidchanged",
            content: ["clientAppInstallId": Self.fixedClientAppInstallID]
        )

        await sendGeneratedMessage(
            target: "/streaming/characteristics/orientationchanged",
            content: ["orientation": 0]
        )

        await sendGeneratedMessage(
            target: "/streaming/characteristics/touchinputenabledchanged",
            content: ["touchInputEnabled": false]
        )

        await sendGeneratedMessage(
            target: "/streaming/characteristics/clientdevicecapabilities",
            content: [:]
        )

        await sendDimensionsChanged(dimensions)
    }

    public func sendDimensionsChanged(_ newDimensions: StreamDimensions) async {
        dimensions = newDimensions
        guard handshakeCompleted else { return }
        guard lastSentDimensions != newDimensions else { return }

        await sendGeneratedMessage(
            target: "/streaming/characteristics/dimensionschanged",
            content: [
                "horizontal": newDimensions.width,
                "vertical": newDimensions.height,
                "preferredWidth": newDimensions.width,
                "preferredHeight": newDimensions.height,
                "safeAreaLeft": 0,
                "safeAreaTop": 0,
                "safeAreaRight": newDimensions.width,
                "safeAreaBottom": newDimensions.height,
                "supportsCustomResolution": true
            ]
        )
        lastSentDimensions = newDimensions
    }

    private func sendGeneratedMessage(target: String, content: [String: Any]) async {
        guard let contentData = try? JSONSerialization.data(withJSONObject: content),
              let contentText = String(data: contentData, encoding: .utf8) else { return }

        let envelope: [String: Any] = [
            "type": "Message",
            "content": contentText,
            "id": UUID().uuidString.lowercased(),
            "target": target,
            "cv": ""
        ]
        await sendJSONAny(envelope)
    }

    private func sendTransactionComplete(id: String, content: Any) async {
        let contentText: String
        if let contentString = content as? String {
            contentText = contentString
        } else if JSONSerialization.isValidJSONObject(content),
                  let data = try? JSONSerialization.data(withJSONObject: content),
                  let text = String(data: data, encoding: .utf8) {
            contentText = text
        } else {
            contentText = ""
        }

        let payload: [String: Any] = [
            "type": "TransactionComplete",
            "content": contentText,
            "id": id,
            "cv": ""
        ]
        await sendJSONAny(payload)
    }

    private func handleTransactionIfNeeded(_ object: [String: Any], target: String) async {
        guard let id = object["id"] as? String else { return }

        switch target {
        case "/streaming/sessionLifetimeManagement/serverInitiatedDisconnect":
            await sendTransactionComplete(id: id, content: "")
            onServerInitiatedDisconnect?()

        case "/streaming/systemUi/messages/ShowMessageDialog":
            // Auto-acknowledge dialogs for now (Result 0 matches "confirm" path in reference).
            await sendTransactionComplete(id: id, content: ["Result": 0])

        default:
            break
        }
    }

    private func sendJSONAny(_ object: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        if !didReportFirstOutboundMessage {
            didReportFirstOutboundMessage = true
            onFirstOutboundMessage?()
        }
        try? await bridge?.sendString(channelKind: .message, text: text)
    }
}
