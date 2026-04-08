// ChatChannel.swift
// Defines chat channel.
//

import Foundation
import os
import StratixModels

// MARK: - Chat Channel
//
// Mirrors channel/chat.ts — handles audio chat negotiation.
// For Xbox streaming, the chat channel is used for microphone audio.
// On tvOS, tvOS 17+ may support microphone via Continuity Camera;
// for earlier versions this channel opens but sends no audio.

private struct ChatChannelState: Sendable {
    weak var bridge: (any WebRTCBridge)?
}

private final class ChatChannelStateBox: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: ChatChannelState())

    init(bridge: any WebRTCBridge) {
        state.withLock { $0.bridge = bridge }
    }

    func bridge() -> (any WebRTCBridge)? {
        state.withLock { $0.bridge }
    }
}

public final class ChatChannel: Sendable {

    public static let label = "chat"
    public static let protocolName = "chatV1"

    private let stateBox: ChatChannelStateBox

    public init(bridge: any WebRTCBridge) {
        self.stateBox = ChatChannelStateBox(bridge: bridge)
    }

    public func onChannelOpen() async {
        // Acknowledge chat channel with a basic ready message
        let msg = #"{"message":"chatReady"}"#
        try? await stateBox.bridge()?.sendString(channelKind: .chat, text: msg)
    }

    public func destroy() {}
}
