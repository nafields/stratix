// StreamingCoreTestSupport.swift
// Provides shared support for the StreamingCore / StreamingCoreTests surface.
//

import Foundation
import Testing
import StratixModels
import XCloudAPI
import os
@testable import StreamingCore

final class SessionTestRecordingBridge: WebRTCBridge, @unchecked Sendable {
    var delegate: WebRTCBridgeDelegate?

    private let offerSDP: String
    private let localCandidatesStorage: [IceCandidatePayload]
    private let connectionStateStorage: PeerConnectionState
    private let delayStatsCollection: Bool
    private let state = OSAllocatedUnfairLock(initialState: SessionTestBridgeState())

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

private struct SessionTestBridgeState {
    var createOfferCallCount = 0
    var didSetLocalDescription = false
    var didSetRemoteDescription = false
    var remoteIceCandidates: [IceCandidatePayload] = []
    var didClose = false
    var collectStatsCallCount = 0
    var pendingStatsContinuations: [CheckedContinuation<StreamingStatsSnapshot, Never>] = []
}

final class SessionTestURLProtocolStub: URLProtocol, @unchecked Sendable {
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
        SessionTestURLProtocolStub.state.lock.lock()
        SessionTestURLProtocolStub.state.requests.append(request)
        next = SessionTestURLProtocolStub.state.handlers.isEmpty ? nil : SessionTestURLProtocolStub.state.handlers.removeFirst()
        SessionTestURLProtocolStub.state.lock.unlock()

        guard let next else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "SessionTestURLProtocolStub",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "No stubbed response for \(request.url?.absoluteString ?? "<nil>")"]
                )
            )
            return
        }

        do {
            if let suffix = next.pathSuffix, request.url?.path.hasSuffix(suffix) != true {
                throw NSError(
                    domain: "SessionTestURLProtocolStub",
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

struct SessionTestHTTPResponse {
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

func makeSessionTestClient(responses: [SessionTestHTTPResponse]) -> XCloudAPIClient {
    SessionTestURLProtocolStub.reset()
    for stub in responses {
        SessionTestURLProtocolStub.enqueue(pathSuffix: stub.pathSuffix) { request in
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
    config.protocolClasses = [SessionTestURLProtocolStub.self]
    let session = URLSession(configuration: config)
    return XCloudAPIClient(baseHost: "https://example.com", gsToken: "gs-token", session: session)
}

func makeSessionTestOfferSDP() -> String {
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

func makeSessionTestAnswerSDP() -> String {
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
