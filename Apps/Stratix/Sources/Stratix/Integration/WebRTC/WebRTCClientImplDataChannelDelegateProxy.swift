// WebRTCClientImplDataChannelDelegateProxy.swift
// Defines web rtc client impl data channel delegate proxy for the Integration / WebRTC surface.
//

import Foundation
import StratixModels

#if WEBRTC_AVAILABLE

/// Bridges `RTCDataChannelDelegate` callbacks back through the existing
/// generation-fenced `WebRTCClientImpl` callback surface.
final class DataChannelDelegateProxy: NSObject, RTCDataChannelDelegate {
    let kind: DataChannelKind
    weak var owner: WebRTCClientImpl?

    init(kind: DataChannelKind, owner: WebRTCClientImpl) {
        self.kind = kind
        self.owner = owner
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        guard dataChannel.readyState == .open, let owner else { return }
        guard let context = owner.activeDataChannelContext(for: dataChannel) else { return }
        owner.markDataChannelOpened(dataChannel)
        owner.callbackDelegate(for: context.generation)?.webRTC(owner, channelDidOpen: context.kind)
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let owner else { return }
        guard let context = owner.activeDataChannelContext(for: dataChannel) else { return }
        if buffer.isBinary {
            owner.callbackDelegate(for: context.generation)?.webRTC(owner, channel: context.kind, didReceiveData: buffer.data)
        } else if let text = String(data: buffer.data, encoding: .utf8) {
            owner.callbackDelegate(for: context.generation)?.webRTC(owner, channel: context.kind, didReceiveText: text)
        }
    }
}

#endif
