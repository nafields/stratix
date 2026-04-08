// WebRTCClientImplDataChannels.swift
// Defines web rtc client impl data channels for the Integration / WebRTC surface.
//

import Foundation
import StratixModels
import StreamingCore

#if WEBRTC_AVAILABLE

extension WebRTCClientImpl {
    func configureDataChannels(for peerConnection: RTCPeerConnection) {
        dataChannels = [:]
        dataChannelDelegateProxies = [:]

        for kind in DataChannelKind.allCases {
            let configuration = RTCDataChannelConfiguration()
            configuration.isOrdered = true
            configuration.`protocol` = channelProtocol(for: kind)
            guard let channel = peerConnection.dataChannel(forLabel: kind.rawValue, configuration: configuration) else {
                continue
            }
            let proxy = DataChannelDelegateProxy(kind: kind, owner: self)
            dataChannelDelegateProxies[kind] = proxy
            channel.delegate = proxy
            dataChannels[kind] = channel
        }

        callbackStateBox.refreshRuntime(
            peerConnection: peerConnection,
            dataChannels: dataChannels.mapValues { $0 as AnyObject }
        )
    }

    public func send(channelKind: DataChannelKind, data: Data) async throws {
        guard let channel = dataChannels[channelKind] else {
            throw WebRTCError.dataChannelUnavailable(channelKind: channelKind.rawValue)
        }

        let bufferedAmount = dataChannelBufferedAmountDescription(channel: channel)
        let sent = channel.sendData(RTCDataBuffer(data: data, isBinary: true))
        guard sent else {
            recordDataChannelSendFailure(
                channelKind: channelKind,
                bytes: data.count,
                readyStateRawValue: channel.readyState.rawValue,
                bufferedAmount: bufferedAmount
            )
            throw WebRTCError.dataChannelSendRejected(
                channelKind: channelKind.rawValue,
                readyStateRawValue: channel.readyState.rawValue,
                bufferedAmount: bufferedAmount
            )
        }
    }

    public func sendString(channelKind: DataChannelKind, text: String) async throws {
        guard let channel = dataChannels[channelKind],
              let data = text.data(using: .utf8) else { return }
        _ = channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    public func dataChannelRuntimeStats(channelKind: DataChannelKind) -> DataChannelRuntimeStats? {
        guard let channel = dataChannels[channelKind] else { return nil }
        return DataChannelRuntimeStats(
            readyStateRawValue: channel.readyState.rawValue,
            bufferedAmountBytes: dataChannelBufferedAmount(channel: channel)
        )
    }

    func markDataChannelOpened(_ dataChannel: RTCDataChannel) {
        if let kind = callbackStateBox.activeDataChannelContext(for: dataChannel)?.kind {
            stateBox.markDataChannelOpened(kind)
        }
    }

    func activeDataChannelContext(for dataChannel: RTCDataChannel) -> (generation: UInt64, kind: DataChannelKind)? {
        callbackStateBox.activeDataChannelContext(for: dataChannel)
    }

    func callbackDelegate(for generation: UInt64) -> (any WebRTCBridgeDelegate)? {
        callbackStateBox.delegate(for: generation)
    }

    func publishOpenDataChannelsIfNeeded(reason: String) {
        let generation = callbackStateBox.currentGeneration()
        for kind in DataChannelKind.allCases {
            guard let channel = dataChannels[kind],
                  channel.readyState == .open else { continue }
            guard stateBox.markOpenDataChannelIfNeeded(kind) else { continue }
            print("[WebRTC] synthesizing local data channel open: \(kind.rawValue) (\(reason))")
            callbackStateBox.delegate(for: generation)?.webRTC(self, channelDidOpen: kind)
        }
    }

    private func channelProtocol(for kind: DataChannelKind) -> String {
        switch kind {
        case .control: return "controlV1"
        case .input:   return "1.0"
        case .message: return "messageV1"
        case .chat:    return "chatV1"
        }
    }

    private func dataChannelBufferedAmount(channel: RTCDataChannel) -> UInt64? {
        let selector = NSSelectorFromString("bufferedAmount")
        let object = channel as NSObject
        guard object.responds(to: selector),
              let value = object.value(forKey: "bufferedAmount") else {
            return nil
        }
        return numericUInt64ForDataChannel(value)
    }

    private func dataChannelBufferedAmountDescription(channel: RTCDataChannel) -> String {
        guard let bufferedAmount = dataChannelBufferedAmount(channel: channel) else {
            return "n/a"
        }
        return String(bufferedAmount)
    }

    private func recordDataChannelSendFailure(
        channelKind: DataChannelKind,
        bytes: Int,
        readyStateRawValue: Int,
        bufferedAmount: String
    ) {
        let nowMs = Date().timeIntervalSince1970 * 1000
        dataChannelSendFailureQueue.async { [weak self] in
            guard let self else { return }
            if self.dataChannelSendFailureWindowStartMs == 0
                || (nowMs - self.dataChannelSendFailureWindowStartMs) >= 1_000 {
                self.dataChannelSendFailureWindowStartMs = nowMs
                self.dataChannelSendFailureWindowCount = 0
            }
            self.dataChannelSendFailureWindowCount += 1
            print(
                "[WebRTC] data channel send rejected channel=\(channelKind.rawValue) bytes=\(bytes) readyState=\(readyStateRawValue) bufferedAmount=\(bufferedAmount) failuresInLastSecond=\(self.dataChannelSendFailureWindowCount)"
            )
        }
    }

    func logDataChannelStates(reason: String) {
        for kind in DataChannelKind.allCases {
            guard let channel = dataChannels[kind] else {
                print("[WebRTC] data channel \(kind.rawValue) missing (\(reason))")
                continue
            }
            print("[WebRTC] data channel \(kind.rawValue) state=\(channel.readyState.rawValue) id=\(channel.channelId) negotiated=\(channel.isNegotiated) protocol=\(channel.`protocol`) (\(reason))")
        }
    }

    private func numericUInt64ForDataChannel(_ raw: Any?) -> UInt64? {
        switch raw {
        case let value as UInt64:
            return value
        case let value as Int:
            return value >= 0 ? UInt64(value) : nil
        case let value as Int64:
            return value >= 0 ? UInt64(value) : nil
        case let value as Double:
            return value >= 0 ? UInt64(value) : nil
        case let value as NSNumber:
            return value.int64Value >= 0 ? value.uint64Value : nil
        case let value as String:
            return UInt64(value)
        default:
            return nil
        }
    }
}

#endif
