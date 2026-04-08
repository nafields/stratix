// XCloudAPIClientTests.swift
// Exercises x cloud api client behavior.
//

import Testing
import Foundation
@testable import XCloudAPI
import StratixModels

// MARK: - XCloudAPIClient Tests
//
// Uses URLProtocol stubbing to test HTTP request construction and response parsing.

@Suite(.serialized)
struct XCloudAPIClientTests {

    // MARK: - Device info header

    @Test func deviceInfo_containsWindowsOSName() {
        let info = XCloudAPIClient.makeDeviceInfo()
        #expect(info.contains("\"name\":\"windows\""), "Device info must spoof Windows OS")
    }

    @Test func deviceInfo_containsChromeUserAgent() {
        let info = XCloudAPIClient.makeDeviceInfo()
        #expect(info.contains("chrome"), "Device info must include Chrome browser")
    }

    @Test func deviceInfo_is1080p() {
        let info = XCloudAPIClient.makeDeviceInfo()
        #expect(info.contains("1920"), "Device info must report 1920 width")
        #expect(info.contains("1080"), "Device info must report 1080 height")
    }

    @Test func deviceInfo_isValidJSON() throws {
        let info = XCloudAPIClient.makeDeviceInfo()
        let data = info.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data)
        #expect(parsed is [String: Any], "Device info must be valid JSON")
    }

    // MARK: - Session start body

    @Test func startStreamBody_homeType_usesServerId() {
        let startBody = StartStreamBodyTestHelper(type: .home, targetId: "server-123")
        #expect(startBody.serverId == "server-123")
        #expect(startBody.titleId == "")
    }

    @Test func startStreamBody_cloudType_usesTitleId() {
        let startBody = StartStreamBodyTestHelper(type: .cloud, targetId: "title-456")
        #expect(startBody.titleId == "title-456")
        #expect(startBody.serverId == "")
    }

    @Test func startStreamBody_settingsMatchNanoVersion() {
        let startBody = StartStreamBodyTestHelper(type: .home, targetId: "x")
        #expect(startBody.settings.nanoVersion == "V3;WebrtcTransport.dll")
        #expect(startBody.settings.osName == "windows")
        #expect(startBody.settings.sdkType == "web")
    }

    // MARK: - SDP signaling parsing

    @Test func sendSDPOffer_usesImmediatePostResponseBody() async throws {
        let client = makeClient(
            responses: [
                .json(statusCode: 200, pathSuffix: "/sdp", body: ["sdp": "answer-immediate"])
            ]
        )

        let answer = try await client.sendSDPOffer(sessionPath: "/v5/sessions/cloud/test", sdp: "offer")

        #expect(answer == "answer-immediate")
        let requests = URLProtocolStub.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "POST")
    }

    @Test func sendSDPOffer_parsesExchangeResponseStringEnvelope() async throws {
        let inner = #"{"sdp":"answer-from-string-envelope"}"#
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/sdp"),
                .json(statusCode: 200, pathSuffix: "/sdp", body: ["exchangeResponse": inner])
            ]
        )

        let answer = try await client.sendSDPOffer(sessionPath: "/v5/sessions/cloud/test", sdp: "offer")

        #expect(answer == "answer-from-string-envelope")
    }

    @Test func sendSDPOffer_parsesExchangeResponseObjectEnvelope() async throws {
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/sdp"),
                .json(statusCode: 200, pathSuffix: "/sdp", body: ["exchangeResponse": ["sdp": "answer-from-object-envelope"]])
            ]
        )

        let answer = try await client.sendSDPOffer(sessionPath: "/v5/sessions/cloud/test", sdp: "offer")

        #expect(answer == "answer-from-object-envelope")
    }

    // MARK: - ICE signaling parsing

    @Test func sendICECandidates_parsesDirectIceCandidatesKey() async throws {
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: [
                    "iceCandidates": [
                        ["candidate": "a=candidate:1", "sdpMLineIndex": 0, "sdpMid": "0"]
                    ]
                ])
            ]
        )

        let result = try await client.sendICECandidates(
            sessionPath: "/v5/sessions/cloud/test",
            candidates: [IceCandidatePayload(candidate: "a=local", sdpMLineIndex: 0, sdpMid: "0")],
            maxPollAttempts: 2,
            pollIntervalSeconds: 0
        )

        #expect(result.count == 1)
        #expect(result[0].candidate == "a=candidate:1")
    }

    @Test func sendICECandidates_stripsLeadingAPrefixOnOutboundCandidates() async throws {
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .empty(statusCode: 204, pathSuffix: "/ice")
            ]
        )

        _ = try await client.sendICECandidates(
            sessionPath: "/v5/sessions/cloud/test",
            candidates: [
                IceCandidatePayload(candidate: "a=candidate:123 1 udp 2122260223 10.0.0.1 5000 typ host", sdpMLineIndex: 0, sdpMid: "0"),
                IceCandidatePayload(candidate: "a=candidate:124 1 tcp 1518280447 10.0.0.1 9 typ host tcptype active", sdpMLineIndex: 0, sdpMid: "0"),
                IceCandidatePayload(candidate: "a=candidate:125 1 udp 2122260223 host-abc.local 5001 typ host", sdpMLineIndex: 0, sdpMid: "0"),
                IceCandidatePayload(candidate: "a=candidate:126 1 udp 2122260223 fe80::1 5002 typ host", sdpMLineIndex: 0, sdpMid: "0"),
                IceCandidatePayload(candidate: "a=end-of-candidates", sdpMLineIndex: 0, sdpMid: "0"),
                IceCandidatePayload(candidate: "a=candidate:127 1 udp 2122260223 10.0.0.2 5003 typ host", sdpMLineIndex: 0, sdpMid: "0", usernameFragment: "ufrag123")
            ],
            maxPollAttempts: 1,
            pollIntervalSeconds: 0
        )

        let requests = URLProtocolStub.recordedRequests()
        let postICE = try #require(requests.first(where: { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/ice") == true }))
        let bodyString = requestBodyString(postICE)
        #expect(bodyString.contains("\"candidates\":["))
        #expect(bodyString.contains("\\\"candidate\\\":\\\"candidate:123 1 udp"))
        #expect(bodyString.contains("\\\"usernameFragment\\\":\\\"ufrag123\\\""))
        #expect(!bodyString.contains("\\\"candidate\\\":\\\"a=candidate:"))
        #expect(!bodyString.contains(" tcp "))
        #expect(!bodyString.contains(".local"))
        #expect(!bodyString.contains("fe80::"))
        #expect(!bodyString.contains("end-of-candidates"))
    }

    @Test func sendICECandidates_parsesExchangeResponseStringWrappedObject() async throws {
        let inner = #"{"candidates":[{"candidate":"a=candidate:2","sdpMLineIndex":0,"sdpMid":"0"}]}"#
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: ["exchangeResponse": inner])
            ]
        )

        let result = try await client.sendICECandidates(
            sessionPath: "/v5/sessions/cloud/test",
            candidates: [],
            maxPollAttempts: 2,
            pollIntervalSeconds: 0
        )

        #expect(result.count == 1)
        #expect(result[0].candidate == "a=candidate:2")
    }

    @Test func sendICECandidates_parsesExchangeResponseObjectWrappedArray() async throws {
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: [
                    "exchangeResponse": [
                        ["candidate": "a=candidate:3", "sdpMLineIndex": 0, "sdpMid": "audio"]
                    ]
                ])
            ]
        )

        let result = try await client.sendICECandidates(
            sessionPath: "/v5/sessions/cloud/test",
            candidates: [],
            maxPollAttempts: 2,
            pollIntervalSeconds: 0
        )

        #expect(result.count == 1)
        #expect(result[0].sdpMid == "audio")
    }

    @Test func sendICECandidates_returnsEmptyArrayWhenNoRemoteICEArrives() async throws {
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .empty(statusCode: 204, pathSuffix: "/ice")
            ]
        )

        let result = try await client.sendICECandidates(
            sessionPath: "/v5/sessions/cloud/test",
            candidates: [],
            maxPollAttempts: 1,
            pollIntervalSeconds: 0
        )

        #expect(result.isEmpty)
    }

    @Test func sendICECandidates_throwsOnMalformedEnvelope() async {
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: ["exchangeResponse": ["unexpected": true]])
            ]
        )

        do {
            _ = try await client.sendICECandidates(
                sessionPath: "/v5/sessions/cloud/test",
                candidates: [],
                maxPollAttempts: 1,
                pollIntervalSeconds: 0
            )
            Issue.record("Expected malformed ICE envelope to throw")
        } catch let error as APIError {
            if case .decodingError(let message) = error {
                #expect(message.contains("Malformed ICE envelope"))
            } else {
                Issue.record("Expected decodingError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func sendICECandidates_throwsServerErrorDetailsFromICEEnvelope() async {
        let client = makeClient(
            responses: [
                .empty(statusCode: 204, pathSuffix: "/ice"),
                .json(statusCode: 200, pathSuffix: "/ice", body: [
                    "exchangeResponse": NSNull(),
                    "errorDetails": [
                        "code": "ConnectionExchangeFailed",
                        "message": "PerformIceExchangeV1Command failed"
                    ]
                ])
            ]
        )

        do {
            _ = try await client.sendICECandidates(
                sessionPath: "/v5/sessions/cloud/test",
                candidates: [],
                maxPollAttempts: 1,
                pollIntervalSeconds: 0
            )
            Issue.record("Expected ICE errorDetails envelope to throw")
        } catch let error as APIError {
            if case .decodingError(let message) = error {
                #expect(message.contains("ICE server error ConnectionExchangeFailed"))
            } else {
                Issue.record("Expected decodingError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func getCloudTitlesWithRawPayload_returnsDecodedResponseAndRawBytes() async throws {
        let client = makeClient(
            responses: [
                .json(statusCode: 200, pathSuffix: "/v2/titles", body: [
                    "results": [
                        [
                            "titleId": "abc",
                            "details": [
                                "productId": "xyz",
                                "hasEntitlement": true
                            ]
                        ]
                    ]
                ])
            ]
        )

        let payload = try await client.getCloudTitlesWithRawPayload()

        #expect(payload.response.results.count == 1)
        #expect(payload.rawPayload.count > 0)
        #expect(payload.rawJSON.contains("\"titleId\""))
    }
}

// MARK: - URLProtocol Stub

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    private struct StubbedHandler {
        let pathSuffix: String?
        let handler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [StubbedHandler] = []
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
        requests.removeAll()
    }

    static func enqueue(pathSuffix: String?, handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        handlers.append(StubbedHandler(pathSuffix: pathSuffix, handler: handler))
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let next: StubbedHandler?
        URLProtocolStub.lock.lock()
        URLProtocolStub.requests.append(request)
        next = URLProtocolStub.handlers.isEmpty ? nil : URLProtocolStub.handlers.removeFirst()
        URLProtocolStub.lock.unlock()

        guard let next else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "URLProtocolStub", code: 0, userInfo: [NSLocalizedDescriptionKey: "No stubbed response for \(request.url?.absoluteString ?? "<nil>")"]))
            return
        }

        do {
            if let suffix = next.pathSuffix,
               request.url?.path.hasSuffix(suffix) != true {
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

// MARK: - Test helpers

private struct StubHTTPResponse {
    let statusCode: Int
    let pathSuffix: String?
    let body: Data

    static func empty(statusCode: Int, pathSuffix: String? = nil) -> Self {
        .init(statusCode: statusCode, pathSuffix: pathSuffix, body: Data())
    }

    static func raw(statusCode: Int, pathSuffix: String? = nil, body: String) -> Self {
        .init(statusCode: statusCode, pathSuffix: pathSuffix, body: Data(body.utf8))
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

private func requestBodyString(_ request: URLRequest) -> String {
    if let body = request.httpBody {
        return String(data: body, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return String(data: data, encoding: .utf8) ?? ""
}

private struct StartStreamBodyTestHelper {
    let clientSessionId = ""
    let titleId: String
    let systemUpdateGroup = ""
    let settings = SettingsHelper()
    let serverId: String
    let fallbackRegionNames: [String] = []

    init(type: StreamKind, targetId: String) {
        titleId = type == .cloud ? targetId : ""
        serverId = type == .home ? targetId : ""
    }
}

private struct SettingsHelper {
    let nanoVersion = "V3;WebrtcTransport.dll"
    let osName = "windows"
    let sdkType = "web"
}


@Suite
struct RegionSelectionTests {
    @Test func preferredRegion_returnsPinnedWhenAvailable() {
        let regions = [
            LoginRegion(name: "eus", baseUri: "https://eus.core.gssv-play-prod.xboxlive.com", isDefault: true),
            LoginRegion(name: "weu", baseUri: "https://weu.core.gssv-play-prod.xboxlive.com", isDefault: false)
        ]
        let chosen = preferredRegion(from: regions, preference: "weu")
        #expect(chosen?.name == "weu")
    }

    @Test func preferredRegion_fallsBackToDefault() {
        let regions = [
            LoginRegion(name: "eus", baseUri: "https://eus.core.gssv-play-prod.xboxlive.com", isDefault: true),
            LoginRegion(name: "weu", baseUri: "https://weu.core.gssv-play-prod.xboxlive.com", isDefault: false)
        ]
        let chosen = preferredRegion(from: regions, preference: "missing")
        #expect(chosen?.name == "eus")
    }
}
