// StreamingRuntime.swift
// Defines streaming runtime.
//

import Foundation
import StratixModels
import InputBridge
import XCloudAPI

/// Owns the full actor-isolated stream bring-up and teardown pipeline: signaling, SDP/ICE,
/// data-channel startup, and runtime snapshots that are mirrored back to the main-actor session.
actor StreamingRuntime {
    private let delegateBox: StreamingRuntimeDelegateBox
    private let generationBox: StreamingRuntimeGenerationBox
    private let apiClient: XCloudAPIClient
    private let bridge: any WebRTCBridge
    private let sdpProcessor = SDPProcessor()
    private let iceProcessor = ICEProcessor()
    private let inputQueue: InputQueue
    private let streamingConfig: StreamingConfig
    private let streamPreferences: StreamPreferences

    private var session: StreamSession?
    private var controlChannel: ControlChannel?
    private var inputChannel: InputChannel?
    private var chatChannel: ChatChannel?
    private var messageChannel: MessageChannel?
    private var messageHandshakeCompleted = false
    private var controlDataChannelOpen = false
    private var inputDataChannelOpen = false
    private var controlStartupCompleted = false
    private var desiredGamepadConnectionState: [Int: Bool] = [:]
    private var sentGamepadConnectionState: [Int: Bool] = [:]
    private var controlPreferredDimensions: StreamDimensions
    private var messagePreferredDimensions: StreamDimensions
    private var negotiatedDimensions: StreamDimensions?
    private var inputFlushHz: Double?
    private var inputFlushJitterMs: Double?
    private var didSendPostHandshakeDimensionsUpdate = false
    private let startupPayloadLogWindow = StartupPayloadLogWindow()
    private var callbackGeneration: UInt64 = 0

    init(
        apiClient: XCloudAPIClient,
        bridge: any WebRTCBridge,
        inputQueue: InputQueue,
        config: StreamingConfig,
        preferences: StreamPreferences,
        delegateBox: StreamingRuntimeDelegateBox,
        generationBox: StreamingRuntimeGenerationBox
    ) {
        self.delegateBox = delegateBox
        self.generationBox = generationBox
        self.apiClient = apiClient
        self.bridge = bridge
        self.inputQueue = inputQueue
        self.streamingConfig = config
        self.streamPreferences = preferences
        self.controlPreferredDimensions = StreamDimensions(
            width: Int(config.videoDimensionsHint.width),
            height: Int(config.videoDimensionsHint.height)
        )
        self.messagePreferredDimensions = config.messageChannelDimensions
    }

    func handleVideoTrack(_ token: RetainedTrackToken, generation: UInt64) async {
        guard generation == callbackGeneration else {
            releaseRetainedTrack(token)
            return
        }
        await MainActor.run {
            delegateBox.currentDelegate()?.runtimeDidReceiveVideoTrack(takeRetainedTrack(token))
        }
    }

    func handleAudioTrack(_ token: RetainedTrackToken, generation: UInt64) async {
        guard generation == callbackGeneration else {
            releaseRetainedTrack(token)
            return
        }
        await MainActor.run {
            delegateBox.currentDelegate()?.runtimeDidReceiveAudioTrack(takeRetainedTrack(token))
        }
    }

    /// Performs the complete signaling and WebRTC startup sequence for one stream session.
    func connect(type: StreamKind, targetId: String, msaUserToken: String?) async {
        resetForConnect()
        await publishSnapshot()

        do {
            let startResp = try await apiClient.startStream(type: type, targetId: targetId, preferences: streamPreferences)
            let streamSession = StreamSession(apiClient: apiClient, response: startResp)
            session = streamSession

            await notifyLifecycle(.provisioning)

            if type == .cloud {
                let delegateBox = self.delegateBox
                let waitingHandler: @Sendable (String, Int?) -> Void = { _, secs in
                    Task { @MainActor in
                        delegateBox.currentDelegate()?.runtimeDidUpdateLifecycle(.waitingForResources(estimatedWaitSeconds: secs))
                    }
                }
                let initialCloudState = try await streamSession.waitUntilReadyOrProvisioned(
                    timeout: 300,
                    titleId: targetId,
                    onIntermediateState: waitingHandler
                )
                if initialCloudState == .readyToConnect {
                    await notifyLifecycle(.readyToConnect)
                } else {
                    streamLogger.info("xCloud session already provisioned before /connect auth step; skipping redundant /connect")
                    await notifyLifecycle(.provisioning)
                }

                if initialCloudState == .readyToConnect {
                    guard let connectUserToken = msaUserToken, !connectUserToken.isEmpty else {
                        throw StreamError(code: .authentication, message: "Missing MSA token for xCloud /connect auth step")
                    }
                    await notifyLifecycle(.provisioning)
                    try await streamSession.sendMSALAuth(userToken: connectUserToken)
                    try await streamSession.waitUntilProvisioned(
                        titleId: targetId,
                        onIntermediateState: waitingHandler
                    )
                }
            } else {
                try await streamSession.waitUntilReady()
                await notifyLifecycle(.readyToConnect)
            }

            await notifyLifecycle(.connectingWebRTC)

            bridge.applyH264CodecPreferences()
            let offer = try await bridge.createOffer()

            let processedSDP = sdpProcessor.processLocalSDP(
                sdp: offer.sdp,
                maxVideoBitrateKbps: streamingConfig.maxVideoBitrateKbps,
                maxAudioBitrateKbps: streamingConfig.maxAudioBitrateKbps,
                stereoAudio: streamingConfig.stereoAudioEnabled,
                preferredVideoCodec: streamingConfig.preferredSdpCodec,
                maxVideoFrameRate: streamingConfig.requestedVideoMaxFrameRate,
                h264ProfileLevelIdOverride: streamingConfig.h264FallbackProfileLevelId
            )
            logActualLocalSDPOfferIfEnabled(processedSDP)
            let processedOffer = SessionDescription(type: .offer, sdp: processedSDP)

            try await bridge.setLocalDescription(processedOffer)

            let answerSDP = try await streamSession.exchangeSDP(localSDP: processedSDP)
            let remoteSDP = sdpProcessor.processRemoteSDP(sdp: answerSDP)
            logRemoteSDPAnswerSummary(remoteSDP)
            let answer = SessionDescription(type: .answer, sdp: remoteSDP)
            try await bridge.setRemoteDescription(answer)
            streamLogger.info("Remote SDP applied successfully")

            let localCandidates = try await waitForStableLocalICECandidates()
            streamLogger.info("Local ICE candidates gathered: \(localCandidates.count, privacy: .public)")
            let localICEUsernameFragment = extractLocalIceUsernameFragment(from: processedSDP)
            if let localICEUsernameFragment {
                streamLogger.info("Local ICE username fragment detected: \(localICEUsernameFragment, privacy: .public)")
            } else {
                streamLogger.warning("Local ICE username fragment not found in SDP; sending ICE without usernameFragment")
            }

            let outboundLocalCandidates = localCandidates.map { candidate in
                IceCandidatePayload(
                    candidate: candidate.candidate,
                    sdpMLineIndex: candidate.sdpMLineIndex,
                    sdpMid: candidate.sdpMid,
                    usernameFragment: candidate.usernameFragment ?? localICEUsernameFragment
                )
            }
            let remoteCandidates = try await streamSession.exchangeICE(
                localCandidates: outboundLocalCandidates,
                preferIPv6: streamPreferences.preferIPv6
            )
            streamLogger.info("Remote ICE candidates received: \(remoteCandidates.count, privacy: .public)")

            if remoteCandidates.isEmpty {
                streamLogger.warning("No remote ICE candidates returned by server; continuing with SDP-only/embedded candidates path")
            } else {
                let expandedCandidates = iceProcessor.expandCandidates(remoteCandidates)
                streamLogger.info("Expanded remote ICE candidates: \(expandedCandidates.count, privacy: .public)")
                for (index, candidate) in expandedCandidates.enumerated() {
                    do {
                        try await bridge.addRemoteIceCandidate(candidate)
                    } catch {
                        streamLogger.error(
                            "Failed adding remote ICE candidate \(index + 1)/\(expandedCandidates.count, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        throw error
                    }
                }
                streamLogger.info("Applied all remote ICE candidates")
            }

            await streamSession.startKeepalive()
            streamLogger.info("Stream keepalive started")

            try await waitForPeerConnectionConnected()
            await notifyLifecycle(.connected)
        } catch let error as StreamError {
            await teardownActiveConnection()
            streamLogger.error("Stream failed [\(error.code.rawValue, privacy: .public)]: \(error.message, privacy: .public)")
            await notifyLifecycle(.failed(error))
        } catch let error as APIError {
            await teardownActiveConnection()
            let streamError = StreamError(code: .signaling, message: error.localizedDescription)
            streamLogger.error("Stream failed [\(streamError.code.rawValue, privacy: .public)]: \(streamError.message, privacy: .public)")
            await notifyLifecycle(.failed(streamError))
        } catch {
            await teardownActiveConnection()
            streamLogger.error("Stream failed [unknown]: \(error.localizedDescription, privacy: .public)")
            await notifyLifecycle(.failed(StreamError(code: .unknown, message: error.localizedDescription)))
        }
    }

    /// Tears down the active signaling/WebRTC session and clears runtime-owned connection state.
    func disconnect() async {
        await teardownActiveConnection()
    }

    /// Stores desired gamepad state immediately and flushes it once the control channel is ready.
    func setGamepadConnectionState(index: Int, connected: Bool) async {
        desiredGamepadConnectionState[index] = connected
        if controlStartupCompleted {
            await flushPendingGamepadConnectionState()
        } else {
            streamLogger.info(
                "Queued gamepad state index=\(index, privacy: .public) connected=\(connected, privacy: .public) until control channel startup completes"
            )
        }
    }

    func handleConnectionStateChange(_ state: PeerConnectionState, generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        streamLogger.info("Peer connection callback state: \(state.rawValue, privacy: .public)")
        switch state {
        case .connected:
            await notifyLifecycle(.connected)
        case .failed, .disconnected:
            let shouldFail = await MainActor.run {
                delegateBox.currentDelegate()?.lifecycle == .connected
            }
            if shouldFail {
                await notifyLifecycle(.failed(StreamError(code: .webrtc, message: "Connection lost: \(state)")))
            }
        case .closed:
            await notifyLifecycle(.disconnected)
        default:
            break
        }
    }

    func handleChannelOpen(_ kind: DataChannelKind, generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        streamLogger.info("Data channel opened: \(kind.rawValue, privacy: .public)")
        switch kind {
        case .control:
            controlDataChannelOpen = true
            controlStartupCompleted = false
            let channel = controlChannel ?? ControlChannel(
                bridge: bridge,
                keyframeIntervalSeconds: streamingConfig.keyframeRequestIntervalSeconds ?? 5
            )
            await channel.configureVideoPreference(
                width: controlPreferredDimensions.width,
                height: controlPreferredDimensions.height,
                framesPerSecond: max(streamingConfig.preferredFrameRate, 1),
                colorRange: streamingConfig.preferredColorRange
            )
            controlChannel = channel
            await startDeferredChannelsIfReady()

        case .input:
            inputDataChannelOpen = true
            let channel = inputChannel ?? InputChannel(bridge: bridge, queue: inputQueue)
            let callbackGeneration = self.callbackGeneration
            channel.configure(
                onVibration: { [self] report in
                    Task {
                        await self.handleVibration(report, generation: callbackGeneration)
                    }
                },
                onServerMetadata: { [self] width, height in
                    Task {
                        await self.handleServerMetadata(width: width, height: height, generation: callbackGeneration)
                    }
                },
                onFlushTelemetry: { [self] hz, jitterMs in
                    Task {
                        await self.handleInputFlushTelemetry(hz: hz, jitterMs: jitterMs, generation: callbackGeneration)
                    }
                },
                shouldLogRawInboundMetadata: { [startupPayloadLogWindow] in
                    startupPayloadLogWindow.shouldLog()
                },
                shouldLogRawOutboundPackets: { [startupPayloadLogWindow] in
                    startupPayloadLogWindow.shouldLog()
                }
            )
            inputChannel = channel
            await startDeferredChannelsIfReady()

        case .chat:
            let channel = chatChannel ?? ChatChannel(bridge: bridge)
            chatChannel = channel
            await channel.onChannelOpen()

        case .message:
            let channel = messageChannel ?? MessageChannel(
                bridge: bridge,
                initialDimensions: messagePreferredDimensions
            )
            let callbackGeneration = self.callbackGeneration
            await channel.configure(
                onHandshakeCompleted: { [self] in
                    Task {
                        await self.handleMessageHandshakeCompleted(generation: callbackGeneration)
                    }
                },
                onProtocolMessage: { event in
                    streamLogger.info("Message channel event: \(event.target, privacy: .public)")
                },
                onServerInitiatedDisconnect: { [self] in
                    Task {
                        await self.handleServerInitiatedDisconnect(generation: callbackGeneration)
                    }
                },
                onFirstOutboundMessage: { [startupPayloadLogWindow] in
                    if startupPayloadLogWindow.markFirstOutboundMessage(window: 30) {
                        streamLogger.info("Startup raw payload logging armed for 30 seconds after first outbound message")
                    }
                },
                shouldLogRawInboundMessages: { [startupPayloadLogWindow] in
                    startupPayloadLogWindow.shouldLog()
                }
            )
            messageChannel = channel
            await channel.onChannelOpen()
        }
    }

    func handleDataReceived(channel: DataChannelKind, data: Data, generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        if channel == .input {
            inputChannel?.onMessage(data: data)
        }
    }

    func handleTextReceived(channel: DataChannelKind, text: String, generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        if channel == .message {
            await messageChannel?.onTextMessage(text: text)
        }
    }

    private func handleVibration(_ report: VibrationReport, generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        await MainActor.run {
            delegateBox.currentDelegate()?.runtimeDidReceiveVibration(report)
        }
    }

    private func handleServerMetadata(width: UInt32, height: UInt32, generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        negotiatedDimensions = StreamDimensions(width: Int(width), height: Int(height))
        await publishSnapshot()
        await maybeSendPostHandshakeDimensionsUpdateIfNeeded()
    }

    private func handleInputFlushTelemetry(hz: Double, jitterMs: Double, generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        inputFlushHz = hz
        inputFlushJitterMs = jitterMs
        await publishSnapshot()
    }

    private func handleMessageHandshakeCompleted(generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        guard !messageHandshakeCompleted else { return }
        messageHandshakeCompleted = true
        streamLogger.info("Message channel handshake completed")
        await maybeSendPostHandshakeDimensionsUpdateIfNeeded()
        await startDeferredChannelsIfReady()
    }

    private func handleServerInitiatedDisconnect(generation: UInt64) async {
        guard generation == callbackGeneration else { return }
        streamLogger.warning("Server initiated disconnect received on message channel")
        await MainActor.run {
            delegateBox.currentDelegate()?.runtimeDidRequestDisconnect(.serverInitiated)
        }
    }

    private func startDeferredChannelsIfReady() async {
        if messageHandshakeCompleted, controlDataChannelOpen, let controlChannel {
            await controlChannel.onOpen()
            controlStartupCompleted = true
            await flushPendingGamepadConnectionState()
        } else if controlDataChannelOpen, !messageHandshakeCompleted {
            streamLogger.info("Deferring control channel startup until message handshake completes")
        }

        if messageHandshakeCompleted, inputDataChannelOpen, let inputChannel {
            await inputChannel.onOpen()
        } else if inputDataChannelOpen, !messageHandshakeCompleted {
            streamLogger.info("Deferring input channel startup until message handshake completes")
        }
    }

    private func flushPendingGamepadConnectionState() async {
        guard controlStartupCompleted, let controlChannel else { return }

        let pendingUpdates = desiredGamepadConnectionState
            .sorted { $0.key < $1.key }
            .filter { sentGamepadConnectionState[$0.key] != $0.value }

        guard !pendingUpdates.isEmpty else { return }

        streamLogger.info(
            "Flushing pending gamepad registration updates count=\(pendingUpdates.count, privacy: .public)"
        )

        for (index, connected) in pendingUpdates {
            await controlChannel.sendGamepadChanged(index: index, wasAdded: connected)
            sentGamepadConnectionState[index] = connected
        }
    }

    private func maybeSendPostHandshakeDimensionsUpdateIfNeeded() async {
        guard messageHandshakeCompleted,
              !didSendPostHandshakeDimensionsUpdate,
              let negotiatedDimensions,
              let messageChannel else {
            return
        }
        guard negotiatedDimensions != messagePreferredDimensions else { return }
        didSendPostHandshakeDimensionsUpdate = true
        messagePreferredDimensions = negotiatedDimensions
        await publishSnapshot()
        await messageChannel.sendDimensionsChanged(negotiatedDimensions)
    }

    private func resetForConnect() {
        let desiredGamepadConnectionState = self.desiredGamepadConnectionState
        resetTransientState(clearDesiredGamepadConnectionState: false)
        self.desiredGamepadConnectionState = desiredGamepadConnectionState
        startupPayloadLogWindow.reset()
        controlPreferredDimensions = StreamDimensions(
            width: Int(streamingConfig.videoDimensionsHint.width),
            height: Int(streamingConfig.videoDimensionsHint.height)
        )
        messagePreferredDimensions = streamingConfig.messageChannelDimensions
    }

    private func resetTransientState(clearDesiredGamepadConnectionState: Bool = true) {
        callbackGeneration &+= 1
        generationBox.set(callbackGeneration)
        controlChannel = nil
        inputChannel = nil
        chatChannel = nil
        messageChannel = nil
        messageHandshakeCompleted = false
        controlDataChannelOpen = false
        inputDataChannelOpen = false
        controlStartupCompleted = false
        if clearDesiredGamepadConnectionState {
            desiredGamepadConnectionState = [:]
        }
        sentGamepadConnectionState = [:]
        negotiatedDimensions = nil
        inputFlushHz = nil
        inputFlushJitterMs = nil
        didSendPostHandshakeDimensionsUpdate = false
    }

    private func teardownActiveConnection() async {
        let activeControlChannel = controlChannel
        let activeInputChannel = inputChannel
        let activeMessageChannel = messageChannel
        let activeChatChannel = chatChannel
        let activeSession = session
        resetTransientState()
        if let activeControlChannel {
            await activeControlChannel.destroy()
        }
        activeInputChannel?.destroy()
        if let activeMessageChannel {
            await activeMessageChannel.destroy()
        }
        activeChatChannel?.destroy()
        await bridge.close()
        if let activeSession {
            try? await activeSession.stop()
        }
        session = nil
    }

    private func publishSnapshot() async {
        let snapshot = StreamingRuntimeSnapshot(
            negotiatedDimensions: negotiatedDimensions,
            controlPreferredDimensions: controlPreferredDimensions,
            messagePreferredDimensions: messagePreferredDimensions,
            inputFlushHz: inputFlushHz,
            inputFlushJitterMs: inputFlushJitterMs
        )
        await MainActor.run {
            delegateBox.currentDelegate()?.runtimeDidUpdateSnapshot(snapshot)
        }
    }

    private func notifyLifecycle(_ lifecycle: StreamLifecycleState) async {
        await MainActor.run {
            delegateBox.currentDelegate()?.runtimeDidUpdateLifecycle(lifecycle)
        }
    }

    private func logActualLocalSDPOfferIfEnabled(_ sdp: String) {
        guard streamingConfig.logLocalSDPOffer else { return }
        let formatted = sdpProcessor.formatSDPForLogging(sdp: sdp, redactSensitive: true)
        print("[STREAM SDP OFFER] ==========================================")
        print(formatted)
        print("[STREAM SDP OFFER] ==========================================")
    }

    private func logRemoteSDPAnswerSummary(_ sdp: String) {
        let normalized = sdp.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let videoStart = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else {
            streamLogger.warning("[STREAM SDP ANSWER] Missing m=video section")
            return
        }

        var videoEnd = lines.count
        if videoStart + 1 < lines.count {
            for idx in (videoStart + 1)..<lines.count where lines[idx].hasPrefix("m=") {
                videoEnd = idx
                break
            }
        }

        let videoMLine = lines[videoStart]
        streamLogger.info("[STREAM SDP ANSWER] \(videoMLine, privacy: .public)")

        var codecByPayload: [String: String] = [:]
        var fmtpByPayload: [String: String] = [:]

        for line in lines[videoStart..<videoEnd] {
            if line.hasPrefix("a=rtpmap:") {
                let rest = String(line.dropFirst("a=rtpmap:".count))
                let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    let payload = String(parts[0])
                    let codecToken = String(parts[1]).split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
                    if let codecToken {
                        codecByPayload[payload] = codecToken
                    }
                }
            } else if line.hasPrefix("a=fmtp:") {
                let rest = String(line.dropFirst("a=fmtp:".count))
                let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    fmtpByPayload[String(parts[0])] = String(parts[1])
                }
            }
        }

        let mLineTokens = videoMLine.split(separator: " ", omittingEmptySubsequences: true)
        let payloads = mLineTokens.dropFirst(3).map(String.init)
        let selectedPayload = payloads.first(where: { payload in
            guard let codec = codecByPayload[payload]?.uppercased() else { return false }
            return codec != "RTX" && codec != "RED" && codec != "ULPFEC" && codec != "FLEXFEC-03"
        }) ?? payloads.first

        guard let selectedPayload else {
            streamLogger.warning("[STREAM SDP ANSWER] Unable to determine selected video payload from m=video")
            return
        }

        let selectedCodec = codecByPayload[selectedPayload] ?? "unknown"
        let selectedFmtp = fmtpByPayload[selectedPayload] ?? "none"
        streamLogger.info(
            "[STREAM SDP ANSWER] selected-video pt=\(selectedPayload, privacy: .public) codec=\(selectedCodec, privacy: .public) fmtp=\(selectedFmtp, privacy: .public)"
        )
    }

    private func waitForStableLocalICECandidates(
        maxWaitSeconds: TimeInterval = 5.0,
        pollIntervalSeconds: TimeInterval = 0.25
    ) async throws -> [IceCandidatePayload] {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        var stablePolls = 0
        var previousCount = -1
        var latest: [IceCandidatePayload] = []

        while Date() < deadline {
            latest = await bridge.localIceCandidates
            if latest.contains(where: { $0.candidate.localizedCaseInsensitiveContains("end-of-candidates") }) {
                return latest
            }

            if latest.count == previousCount {
                stablePolls += 1
                if stablePolls >= 2 {
                    return latest
                }
            } else {
                stablePolls = 0
                previousCount = latest.count
            }

            try await Task.sleep(for: .seconds(pollIntervalSeconds))
        }

        return latest
    }

    private func waitForPeerConnectionConnected(timeoutSeconds: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastLoggedState: PeerConnectionState?

        while Date() < deadline {
            let state = await bridge.connectionState
            if lastLoggedState != state {
                streamLogger.info("Peer connection state during startup: \(state.rawValue, privacy: .public)")
                lastLoggedState = state
            }
            switch state {
            case .connected:
                return
            case .failed:
                throw StreamError(code: .webrtc, message: "Peer connection failed during startup")
            case .closed:
                throw StreamError(code: .webrtc, message: "Peer connection closed before connecting")
            case .disconnected:
                throw StreamError(code: .webrtc, message: "Peer connection disconnected before connecting")
            case .new, .connecting:
                break
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        throw StreamError(code: .webrtc, message: "Timed out waiting for peer connection after signaling")
    }

    private func extractLocalIceUsernameFragment(from sdp: String) -> String? {
        for rawLine in sdp.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("a=ice-ufrag:") {
                let value = String(line.dropFirst("a=ice-ufrag:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
