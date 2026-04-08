// StreamingSessionTests.swift
// Exercises streaming session behavior.
//

import Foundation
import os
import Testing
import DiagnosticsKit
import StratixModels
import XCloudAPI
@testable import StreamingCore

@Suite(.serialized)
struct StreamingSessionTests {
    @MainActor
    @Test
    func homeConnectAndDisconnect_usesRuntimeActorAndPreservesFacadeState() async {
        let bridge = RecordingBridge(
            offerSDP: makeLocalOfferSDP(),
            localCandidates: [
                IceCandidatePayload(
                    candidate: "a=candidate:1 1 udp 2122260223 10.0.0.1 5000 typ host",
                    sdpMLineIndex: 0,
                    sdpMid: "0"
                ),
                IceCandidatePayload(
                    candidate: "a=end-of-candidates",
                    sdpMLineIndex: 0,
                    sdpMid: "0"
                )
            ],
            connectionState: .connected
        )
        let client = makeClient(
            responses: [
                .json(statusCode: 200, pathSuffix: "/play", body: [
                    "sessionPath": "v5/sessions/home/test-session",
                    "sessionId": "session-1",
                    "state": "Provisioning"
                ]),
                .json(statusCode: 200, pathSuffix: "/state", body: [
                    "state": "ReadyToConnect"
                ]),
                .json(statusCode: 200, pathSuffix: "/sdp", body: [
                    "sdp": makeRemoteAnswerSDP()
                ]),
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: [
                    "iceCandidates": [
                        [
                            "candidate": "a=candidate:2 1 udp 2122260223 20.0.0.1 6000 typ host",
                            "sdpMLineIndex": 0,
                            "sdpMid": "0"
                        ]
                    ]
                ]),
                .empty(statusCode: 200, pathSuffix: "/test-session")
            ]
        )
        let session = StreamingSession(apiClient: client, bridge: bridge)

        await session.connect(type: .home, targetId: "console-1")

        #expect(session.lifecycle == .connected)
        #expect(bridge.createOfferCallCount == 1)
        #expect(bridge.didSetLocalDescription == true)
        #expect(bridge.didSetRemoteDescription == true)
        #expect(bridge.remoteIceCandidates.count == 1)

        await session.disconnect()

        #expect(session.lifecycle == .disconnected)
        #expect(bridge.didClose == true)

        let requests = URLProtocolStub.recordedRequests()
        #expect(requests.contains(where: { $0.url?.path.hasSuffix("/play") == true }))
        #expect(requests.contains(where: { $0.url?.path.hasSuffix("/state") == true }))
        #expect(requests.contains(where: { $0.url?.path.hasSuffix("/sdp") == true }))
        #expect(requests.contains(where: { $0.url?.path.hasSuffix("/ice") == true }))
        #expect(requests.contains(where: { $0.httpMethod == "DELETE" && $0.url?.path.hasSuffix("/test-session") == true }))
    }

    @MainActor
    @Test
    func cloudConnect_missingMSATokenFailsBeforeWebRTCStarts() async {
        let bridge = RecordingBridge(
            offerSDP: makeLocalOfferSDP(),
            localCandidates: [],
            connectionState: .connected
        )
        let client = makeClient(
            responses: [
                .json(statusCode: 200, pathSuffix: "/play", body: [
                    "sessionPath": "v5/sessions/cloud/test-session",
                    "sessionId": "session-2",
                    "state": "Provisioning"
                ]),
                .json(statusCode: 200, pathSuffix: "/state", body: [
                    "state": "ReadyToConnect"
                ])
            ]
        )
        let session = StreamingSession(apiClient: client, bridge: bridge)

        await session.connect(type: .cloud, targetId: "title-1", msaUserToken: nil)

        switch session.lifecycle {
        case .failed(let error):
            #expect(error.code == .authentication)
            #expect(error.message.contains("Missing MSA token"))
        default:
            Issue.record("Expected authentication failure, got \(session.lifecycle)")
        }
        #expect(bridge.createOfferCallCount == 0)
        #expect(bridge.didSetLocalDescription == false)
    }

    @MainActor
    @Test
    func failedConnect_tearsDownBridgeAndSessionResources() async {
        let bridge = RecordingBridge(
            offerSDP: makeLocalOfferSDP(),
            localCandidates: [
                IceCandidatePayload(
                    candidate: "a=candidate:1 1 udp 2122260223 10.0.0.1 5000 typ host",
                    sdpMLineIndex: 0,
                    sdpMid: "0"
                )
            ],
            connectionState: .connected
        )
        let client = makeClient(
            responses: [
                .json(statusCode: 200, pathSuffix: "/play", body: [
                    "sessionPath": "v5/sessions/home/test-session",
                    "sessionId": "session-3",
                    "state": "Provisioning"
                ]),
                .json(statusCode: 200, pathSuffix: "/state", body: [
                    "state": "ReadyToConnect"
                ]),
                .json(statusCode: 500, pathSuffix: "/sdp", body: [
                    "error": "signaling failed"
                ]),
                .empty(statusCode: 200, pathSuffix: "/test-session")
            ]
        )
        let session = StreamingSession(apiClient: client, bridge: bridge)

        await session.connect(type: .home, targetId: "console-1")

        switch session.lifecycle {
        case .failed(let error):
            #expect(error.code == .signaling)
            #expect(error.message.contains("HTTP 500"))
        default:
            Issue.record("Expected signaling failure, got \(session.lifecycle)")
        }

        #expect(bridge.createOfferCallCount == 1)
        #expect(bridge.didSetLocalDescription == true)
        #expect(bridge.didSetRemoteDescription == false)
        #expect(bridge.didClose == true)

        let requests = URLProtocolStub.recordedRequests()
        #expect(requests.contains(where: { $0.url?.path.hasSuffix("/play") == true }))
        #expect(requests.contains(where: { $0.url?.path.hasSuffix("/state") == true }))
        #expect(requests.contains(where: { $0.url?.path.hasSuffix("/sdp") == true }))
        #expect(requests.contains(where: { $0.httpMethod == "DELETE" && $0.url?.path.hasSuffix("/test-session") == true }))
    }

    @MainActor
    @Test
    func currentGenerationTrackCallbacks_deliverOnceAndCacheForReplay() async {
        let bridge = RecordingBridge(
            offerSDP: makeLocalOfferSDP(),
            localCandidates: [
                IceCandidatePayload(
                    candidate: "a=candidate:1 1 udp 2122260223 10.0.0.1 5000 typ host",
                    sdpMLineIndex: 0,
                    sdpMid: "0"
                )
            ],
            connectionState: .connected
        )
        let client = makeClient(
            responses: [
                .json(statusCode: 200, pathSuffix: "/play", body: [
                    "sessionPath": "v5/sessions/home/test-session",
                    "sessionId": "session-4a",
                    "state": "Provisioning"
                ]),
                .json(statusCode: 200, pathSuffix: "/state", body: [
                    "state": "ReadyToConnect"
                ]),
                .json(statusCode: 200, pathSuffix: "/sdp", body: [
                    "sdp": makeRemoteAnswerSDP()
                ]),
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: [
                    "iceCandidates": [
                        [
                            "candidate": "a=candidate:2 1 udp 2122260223 20.0.0.1 6000 typ host",
                            "sdpMLineIndex": 0,
                            "sdpMid": "0"
                        ]
                    ]
                ]),
                .empty(statusCode: 200, pathSuffix: "/test-session")
            ]
        )
        let session = StreamingSession(apiClient: client, bridge: bridge)
        let deliveredTrackIDs = OSAllocatedUnfairLock(initialState: [ObjectIdentifier]())
        let liveTrack = NSObject()

        await session.connect(type: .home, targetId: "console-1")
        #expect(session.lifecycle == .connected)

        session.onVideoTrack = { track in
            let trackID = ObjectIdentifier(track)
            deliveredTrackIDs.withLock { $0.append(trackID) }
        }

        bridge.delegate?.webRTC(bridge, didReceiveVideoTrack: liveTrack)
        await Task.yield()
        await Task.yield()

        #expect(deliveredTrackIDs.withLock { $0.count } == 1)
        #expect(deliveredTrackIDs.withLock { $0.first } == ObjectIdentifier(liveTrack))

        session.onVideoTrack = { track in
            let trackID = ObjectIdentifier(track)
            deliveredTrackIDs.withLock { $0.append(trackID) }
        }

        #expect(deliveredTrackIDs.withLock { $0.count } == 2)
        #expect(deliveredTrackIDs.withLock { $0.last } == ObjectIdentifier(liveTrack))
    }

    @MainActor
    @Test
    func staleBridgeCallbacks_doNotMutateResetRuntimeAfterGenerationChange() async {
        let bridge = RecordingBridge(
            offerSDP: makeLocalOfferSDP(),
            localCandidates: [
                IceCandidatePayload(
                    candidate: "a=candidate:1 1 udp 2122260223 10.0.0.1 5000 typ host",
                    sdpMLineIndex: 0,
                    sdpMid: "0"
                )
            ],
            connectionState: .connected
        )
        let client = makeClient(
            responses: [
                .json(statusCode: 200, pathSuffix: "/play", body: [
                    "sessionPath": "v5/sessions/home/test-session",
                    "sessionId": "session-4",
                    "state": "Provisioning"
                ]),
                .json(statusCode: 200, pathSuffix: "/state", body: [
                    "state": "ReadyToConnect"
                ]),
                .json(statusCode: 200, pathSuffix: "/sdp", body: [
                    "sdp": makeRemoteAnswerSDP()
                ]),
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: [
                    "iceCandidates": [
                        [
                            "candidate": "a=candidate:2 1 udp 2122260223 20.0.0.1 6000 typ host",
                            "sdpMLineIndex": 0,
                            "sdpMid": "0"
                        ]
                    ]
                ]),
                .empty(statusCode: 200, pathSuffix: "/test-session")
            ]
        )
        let session = StreamingSession(apiClient: client, bridge: bridge)
        let renderedVideoTracks = OSAllocatedUnfairLock(initialState: 0)
        let staleTrack = NSObject()

        await session.connect(type: .home, targetId: "console-1")
        #expect(session.lifecycle == .connected)

        session.onVideoTrack = { _ in
            renderedVideoTracks.withLock { $0 += 1 }
        }

        await session.disconnect()
        bridge.delegate?.webRTC(bridge, didReceiveVideoTrack: staleTrack)
        await Task.yield()
        await Task.yield()

        #expect(session.lifecycle == .disconnected)
        #expect(renderedVideoTracks.withLock { $0 } == 0)

        session.onVideoTrack = { _ in
            renderedVideoTracks.withLock { $0 += 1 }
        }

        #expect(renderedVideoTracks.withLock { $0 } == 0)
    }

    @MainActor
    @Test
    func disconnect_cancelsInFlightStatsPollingBeforeLateSnapshotPublishes() async {
        let bridge = RecordingBridge(
            offerSDP: makeLocalOfferSDP(),
            localCandidates: [
                IceCandidatePayload(
                    candidate: "a=candidate:1 1 udp 2122260223 10.0.0.1 5000 typ host",
                    sdpMLineIndex: 0,
                    sdpMid: "0"
                )
            ],
            connectionState: .connected,
            delayStatsCollection: true
        )
        let client = makeClient(
            responses: [
                .json(statusCode: 200, pathSuffix: "/play", body: [
                    "sessionPath": "v5/sessions/home/test-session",
                    "sessionId": "session-5",
                    "state": "Provisioning"
                ]),
                .json(statusCode: 200, pathSuffix: "/state", body: [
                    "state": "ReadyToConnect"
                ]),
                .json(statusCode: 200, pathSuffix: "/sdp", body: [
                    "sdp": makeRemoteAnswerSDP()
                ]),
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: [
                    "iceCandidates": [
                        [
                            "candidate": "a=candidate:2 1 udp 2122260223 20.0.0.1 6000 typ host",
                            "sdpMLineIndex": 0,
                            "sdpMid": "0"
                        ]
                    ]
                ]),
                .empty(statusCode: 200, pathSuffix: "/test-session")
            ]
        )
        let session = StreamingSession(apiClient: client, bridge: bridge)
        session.setDiagnosticsPollingEnabled(true)

        await session.connect(type: .home, targetId: "console-1")
        #expect(session.lifecycle == .connected)

        for _ in 0..<50 where !bridge.hasPendingStatsRequest {
            await Task.yield()
        }
        #expect(bridge.collectStatsCallCount > 0)
        #expect(bridge.hasPendingStatsRequest == true)

        await session.disconnect()
        bridge.resumePendingStats(
            with: StreamingStatsSnapshot(
                timestamp: .now,
                bitrateKbps: 999,
                framesPerSecond: 60
            )
        )
        await Task.yield()
        await Task.yield()

        #expect(session.lifecycle == .disconnected)
        #expect(session.stats.bitrateKbps == nil)
        #expect(session.stats.framesPerSecond == nil)
    }

    @MainActor
    @Test
    func rendererTelemetry_updatesCollectorSnapshotAndMetricsPipeline() async {
        let bridge = RecordingBridge(
            offerSDP: makeLocalOfferSDP(),
            localCandidates: [],
            connectionState: .connected
        )
        let client = makeClient(responses: [])
        let session = StreamingSession(apiClient: client, bridge: bridge)

        session.setRendererMode("metal")
        session.setRendererTelemetry(
            framesReceived: 180,
            framesDrawn: 177,
            framesDroppedByCoalescing: 3,
            drawQueueDepthMax: 1,
            framesFailed: 0,
            processingStatus: "metalFXSpatial",
            processingInputWidth: 1280,
            processingInputHeight: 720,
            processingOutputWidth: 1920,
            processingOutputHeight: 1080,
            renderLatencyMs: 12.5,
            outputFamily: "metal",
            eligibleRungs: ["sampleBuffer", "metalFXSpatial"],
            deadRungs: [],
            lastError: nil
        )

        let collectorSnapshot = session.statsCollector.snapshot
        #expect(collectorSnapshot.rendererMode == "metal")
        #expect(collectorSnapshot.rendererFramesReceived == 180)
        #expect(collectorSnapshot.rendererFramesDrawn == 177)
        #expect(collectorSnapshot.rendererProcessingStatus == "metalFXSpatial")
        #expect(collectorSnapshot.rendererOutputFamily == "metal")

        let pipelineSnapshot = session.statsCollector.pipelineSnapshot
        #expect(pipelineSnapshot.latestStatsSnapshot?.rendererMode == "metal")
        #expect(pipelineSnapshot.latestStatsSnapshot?.rendererFramesDrawn == 177)
        #expect(pipelineSnapshot.recentRecords.last?.source == .statsSnapshot)
    }
}

private final class RecordingBridge: WebRTCBridge, @unchecked Sendable {
    var delegate: WebRTCBridgeDelegate?

    private let offerSDP: String
    private let localCandidatesStorage: [IceCandidatePayload]
    private let connectionStateStorage: PeerConnectionState
    private let delayStatsCollection: Bool
    private let state = OSAllocatedUnfairLock(initialState: BridgeState())

    init(
        offerSDP: String,
        localCandidates: [IceCandidatePayload],
        connectionState: PeerConnectionState,
        delayStatsCollection: Bool = false
    ) {
        self.offerSDP = offerSDP
        self.localCandidatesStorage = localCandidates
        self.connectionStateStorage = connectionState
        self.delayStatsCollection = delayStatsCollection
    }

    var createOfferCallCount: Int {
        state.withLock { $0.createOfferCallCount }
    }

    var didSetLocalDescription: Bool {
        state.withLock { $0.didSetLocalDescription }
    }

    var didSetRemoteDescription: Bool {
        state.withLock { $0.didSetRemoteDescription }
    }

    var remoteIceCandidates: [IceCandidatePayload] {
        state.withLock { $0.remoteIceCandidates }
    }

    var didClose: Bool {
        state.withLock { $0.didClose }
    }

    var collectStatsCallCount: Int {
        state.withLock { $0.collectStatsCallCount }
    }

    var hasPendingStatsRequest: Bool {
        state.withLock { !$0.pendingStatsContinuations.isEmpty }
    }

    func createOffer() async -> SessionDescription {
        state.withLock { $0.createOfferCallCount += 1 }
        return SessionDescription(type: .offer, sdp: offerSDP)
    }

    func applyH264CodecPreferences() {}

    func setLocalDescription(_ _: SessionDescription) async {
        state.withLock { $0.didSetLocalDescription = true }
    }

    func setRemoteDescription(_ _: SessionDescription) async {
        state.withLock { $0.didSetRemoteDescription = true }
    }

    func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async {
        state.withLock { $0.remoteIceCandidates.append(candidate) }
    }

    var localIceCandidates: [IceCandidatePayload] {
        get async { localCandidatesStorage }
    }

    var connectionState: PeerConnectionState {
        get async { connectionStateStorage }
    }

    func send(channelKind _: DataChannelKind, data _: Data) async {}

    func sendString(channelKind _: DataChannelKind, text _: String) async {}

    func dataChannelRuntimeStats(channelKind: DataChannelKind) -> DataChannelRuntimeStats? {
        nil
    }

    func close() async {
        state.withLock { $0.didClose = true }
    }

    func collectStats() async -> StreamingStatsSnapshot {
        let immediateSnapshot = state.withLock { state -> StreamingStatsSnapshot? in
            state.collectStatsCallCount += 1
            return delayStatsCollection ? nil : StreamingStatsSnapshot()
        }
        if let immediateSnapshot {
            return immediateSnapshot
        }
        return await withCheckedContinuation { continuation in
            state.withLock { $0.pendingStatsContinuations.append(continuation) }
        }
    }

    func resumePendingStats(with snapshot: StreamingStatsSnapshot) {
        let continuation = state.withLock { state -> CheckedContinuation<StreamingStatsSnapshot, Never>? in
            guard !state.pendingStatsContinuations.isEmpty else { return nil }
            return state.pendingStatsContinuations.removeFirst()
        }
        continuation?.resume(returning: snapshot)
    }
}

private struct BridgeState {
    var createOfferCallCount = 0
    var didSetLocalDescription = false
    var didSetRemoteDescription = false
    var remoteIceCandidates: [IceCandidatePayload] = []
    var didClose = false
    var collectStatsCallCount = 0
    var pendingStatsContinuations: [CheckedContinuation<StreamingStatsSnapshot, Never>] = []
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    private struct StubbedHandler {
        let pathSuffix: String?
        let handler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var handlers: [StubbedHandler] = []
        var requests: [URLRequest] = []
    }

    private static let state = State()

    static func reset() {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.handlers.removeAll()
        state.requests.removeAll()
    }

    static func enqueue(pathSuffix: String?, handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.handlers.append(StubbedHandler(pathSuffix: pathSuffix, handler: handler))
    }

    static func recordedRequests() -> [URLRequest] {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let next: StubbedHandler?
        URLProtocolStub.state.lock.lock()
        URLProtocolStub.state.requests.append(request)
        next = URLProtocolStub.state.handlers.isEmpty ? nil : URLProtocolStub.state.handlers.removeFirst()
        URLProtocolStub.state.lock.unlock()

        guard let next else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "URLProtocolStub",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "No stubbed response for \(request.url?.absoluteString ?? "<nil>")"]
                )
            )
            return
        }

        do {
            if let suffix = next.pathSuffix, request.url?.path.hasSuffix(suffix) != true {
                throw NSError(
                    domain: "URLProtocolStub",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected path \(request.url?.path ?? "<nil>"), expected suffix \(suffix)"]
                )
            }
            let (response, data) = try next.handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct StubHTTPResponse {
    let statusCode: Int
    let pathSuffix: String?
    let body: Data

    static func empty(statusCode: Int, pathSuffix: String? = nil) -> Self {
        .init(statusCode: statusCode, pathSuffix: pathSuffix, body: Data())
    }

    static func json(statusCode: Int, pathSuffix: String? = nil, body: Any) -> Self {
        let data = try! JSONSerialization.data(withJSONObject: body)
        return .init(statusCode: statusCode, pathSuffix: pathSuffix, body: data)
    }
}

private func makeClient(responses: [StubHTTPResponse]) -> XCloudAPIClient {
    URLProtocolStub.reset()
    for stub in responses {
        URLProtocolStub.enqueue(pathSuffix: stub.pathSuffix) { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, stub.body)
        }
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLProtocolStub.self]
    let session = URLSession(configuration: config)
    return XCloudAPIClient(baseHost: "https://example.com", gsToken: "gs-token", session: session)
}

private func makeLocalOfferSDP() -> String {
    """
    v=0\r
    o=- 0 0 IN IP4 127.0.0.1\r
    s=-\r
    t=0 0\r
    a=ice-ufrag:localfrag\r
    m=video 9 UDP/TLS/RTP/SAVPF 96\r
    a=rtpmap:96 H264/90000\r
    a=fmtp:96 profile-level-id=640c1f\r
    """
}

private func makeRemoteAnswerSDP() -> String {
    """
    v=0\r
    o=- 0 0 IN IP4 127.0.0.1\r
    s=-\r
    t=0 0\r
    m=video 9 UDP/TLS/RTP/SAVPF 96\r
    a=rtpmap:96 H264/90000\r
    a=fmtp:96 profile-level-id=640c1f\r
    """
}
