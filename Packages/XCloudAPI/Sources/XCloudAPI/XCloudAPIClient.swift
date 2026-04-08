// XCloudAPIClient.swift
// Defines the primary xCloud and xHome HTTP client used by the app and stream workflows.
//

import Foundation
import DiagnosticsKit
import StratixModels
import os.log

/// Normalizes an optional spoofed device OS override to the supported wire-format values.
fileprivate func normalizedDeviceOSNameOverride(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "android", "windows", "tizen":
        return normalized
    default:
        return nil
    }
}


public struct LoginRegion: Codable, Sendable, Equatable {
    public let name: String
    public let baseUri: String
    public let isDefault: Bool

    /// Creates a region entry returned by the login-region discovery API.
    public init(name: String, baseUri: String, isDefault: Bool) {
        self.name = name
        self.baseUri = baseUri
        self.isDefault = isDefault
    }
}

/// Chooses the preferred login region, honoring a pinned region name when one is valid.
public func preferredRegion(from regions: [LoginRegion], preference: String?) -> LoginRegion? {
    guard let preference, !preference.isEmpty else {
        return regions.first(where: { $0.isDefault }) ?? regions.first
    }
    return regions.first(where: { $0.name == preference })
        ?? regions.first(where: { $0.isDefault })
        ?? regions.first
}

// MARK: - Console / Home Streaming

public struct ConsoleListResponse: Decodable, Sendable {
    public let totalItems: Int
    public let results: [RemoteConsole]
    public let continuationToken: String?
}

public struct RemoteConsole: Decodable, Sendable {
    public let deviceName: String
    public let serverId: String
    public let powerState: String
    public let consoleType: String
    public let playPath: String
    public let outOfHomeWarning: Bool
    public let wirelessWarning: Bool
    public let isDevKit: Bool
}

// MARK: - SDP / ICE API Models

struct SDPOfferBody: Encodable {
    let messageType: String
    let sdp: String
    let requestId: String
    let configuration: SDPChannelConfig
}

struct SDPChannelConfig: Encodable {
    let chatConfiguration: ChatConfiguration
    let chat: VersionRange
    let control: VersionRange
    let input: VersionRange
    let message: VersionRange
    let reliableinput: VersionRange
    let unreliableinput: VersionRange
}

struct ChatConfiguration: Encodable {
    let bytesPerSample: Int
    let expectedClipDurationMs: Int
    let format: AudioFormat
    let numChannels: Int
    let sampleFrequencyHz: Int
}

struct AudioFormat: Encodable {
    let codec: String
    let container: String
}

struct VersionRange: Encodable {
    let minVersion: Int
    let maxVersion: Int
}

struct ICEOfferBody: Encodable {
    let candidates: [String]
}

struct IceCandidateWire: Encodable {
    let candidate: String
    let sdpMLineIndex: Int
    let sdpMid: String
    let usernameFragment: String?
}

// MARK: - Errors

public enum APIError: Error, LocalizedError, Sendable {
    case notReady
    case httpError(Int, String)
    case decodingError(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notReady: return "Client not configured. Authenticate first."
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .decodingError(let msg): return "Decode failed: \(msg)"
        case .timeout: return "Request timed out."
        }
    }
}

public struct CloudTitlesRawPayload: Sendable {
    public let response: XCloudTitlesResponse
    public let rawPayload: Data
    public let url: URL?

    /// Stores both the decoded titles response and the original payload for diagnostics.
    public init(response: XCloudTitlesResponse, rawPayload: Data, url: URL?) {
        self.response = response
        self.rawPayload = rawPayload
        self.url = url
    }

    /// Returns the raw library response as UTF-8 JSON when possible for debugging.
    public var rawJSON: String {
        String(data: rawPayload, encoding: .utf8) ?? "<binary>"
    }
}

// MARK: - XCloudAPIClient

/// HTTP API client mirroring xbox-xcloud-player's apiclient.ts.
public actor XCloudAPIClient {

    private let logger = GLogger(category: .api)
    private let session: URLSession
    private var baseHost: String
    private var gsToken: String
    private var currentPreferences = StreamPreferences()
    private var cachedDeviceInfo: String = ""
    private var didLogRawStartStreamRequest = false

    /// Builds the `X-MS-Device-Info` payload that advertises the chosen spoofed browser profile.
    public static func makeDeviceInfo(
        locale: String = "en-US",
        resolution: StreamResolutionMode = .p1080,
        osNameOverride: String? = nil
    ) -> String {
        let osName = normalizedDeviceOSNameOverride(osNameOverride) ?? resolution.osName
        // swiftlint:disable:next line_length
        let json = """
        {"appInfo":{"env":{"clientAppId":"www.xbox.com","clientAppType":"browser","clientAppVersion":"21.1.98","clientSdkVersion":"8.5.3","httpEnvironment":"prod","sdkInstallId":""}},"dev":{"hw":{"make":"Microsoft","model":"unknown","sdktype":"web"},"os":{"name":"\(osName)","ver":"22631.2715","platform":"desktop"},"displayInfo":{"dimensions":{"widthInPixels":\(resolution.displayWidth),"heightInPixels":\(resolution.displayHeight)},"pixelDensity":{"dpiX":2,"dpiY":2}},"browser":{"browserName":"chrome","browserVersion":"119.0"}}}
        """
        return json.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    /// Creates a URL session that routes requests through the repo's blocking test protocol.
    public static func makeBlockingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BlockingURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }

    /// Creates the client with the current region host and authenticated stream token.
    public init(baseHost: String, gsToken: String, session: URLSession = .shared) {
        self.baseHost = baseHost
        self.gsToken = gsToken
        self.session = session
    }

    /// Replaces the active region host and stream token after auth or region changes.
    public func updateCredentials(baseHost: String, gsToken: String) {
        self.baseHost = baseHost
        self.gsToken = gsToken
    }

    // MARK: - Console Discovery

    /// Loads the remote-console inventory for home-streaming surfaces.
    public func getConsoles() async throws -> ConsoleListResponse {
        try await get("/v6/servers/home", responseType: ConsoleListResponse.self)
    }

    /// Loads the main cloud-title library payload.
    public func getCloudTitles() async throws -> XCloudTitlesResponse {
        try await getLibrary("/v2/titles", responseType: XCloudTitlesResponse.self)
    }

    /// Loads the cloud-title library together with the undecoded payload for diagnostics.
    public func getCloudTitlesWithRawPayload() async throws -> CloudTitlesRawPayload {
        let (payload, response) = try await rawGetLibrary("/v2/titles")
        let decodedResponse = try decodeResponse(data: payload, response: response, as: XCloudTitlesResponse.self)
        return CloudTitlesRawPayload(response: decodedResponse, rawPayload: payload, url: response.url)
    }

    /// Loads the most-recently-used slice of the cloud-title library.
    public func getCloudTitlesMRU(limit: Int = 25) async throws -> XCloudTitlesResponse {
        try await getLibrary("/v2/titles/mru?mr=\(limit)", responseType: XCloudTitlesResponse.self)
    }

    // MARK: - Stream Lifecycle

    /// Starts a cloud or home stream session using the caller's launch preferences.
    public func startStream(type: StreamKind, targetId: String, preferences: StreamPreferences = StreamPreferences()) async throws -> StreamSessionStartResponse {
        currentPreferences = preferences
        cachedDeviceInfo = Self.makeDeviceInfo(
            locale: preferences.locale,
            resolution: preferences.resolution,
            osNameOverride: preferences.osNameOverride
        )
        let path = "/v5/sessions/\(type.rawValue)/play"
        let body = StartStreamBody(
            clientSessionId: "",
            titleId: type == .cloud ? targetId : "",
            systemUpdateGroup: "",
            settings: StreamSettings(preferences: preferences),
            serverId: type == .home ? targetId : "",
            fallbackRegionNames: preferences.fallbackRegionNames
        )
        logRawStartStreamRequestIfNeeded(
            path: path,
            preferences: preferences,
            body: body,
            deviceInfo: cachedDeviceInfo
        )
        return try await post(path, body: body, responseType: StreamSessionStartResponse.self)
    }

    /// Polls the current state of an existing stream session.
    public func getSessionState(sessionPath: String) async throws -> StreamStateResponse {
        try await get("\(sessionPath)/state", responseType: StreamStateResponse.self)
    }

    /// Loads wait-time information when the server exposes a queue state for the target title.
    public func getWaitTime(sessionPath: String, titleId: String) async throws -> WaitTimeResponse? {
        let path = "\(sessionPath)/waittime/\(titleId)"
        let (responseData, response) = try await rawGet(path)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard !responseData.isEmpty else { return nil }
        switch http.statusCode {
        case 204, 404:
            return nil
        case 200...299:
            return try JSONDecoder().decode(WaitTimeResponse.self, from: responseData)
        default:
            let responseBody = String(data: responseData, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, responseBody)
        }
    }

    /// Sends the local SDP offer and returns the server's SDP answer string.
    public func sendSDPOffer(sessionPath: String, sdp: String) async throws -> String {
        let body = SDPOfferBody(
            messageType: "offer",
            sdp: sdp,
            requestId: "1",
            configuration: SDPChannelConfig(
                chatConfiguration: ChatConfiguration(
                    bytesPerSample: 2,
                    expectedClipDurationMs: 20,
                    format: AudioFormat(codec: "opus", container: "webm"),
                    numChannels: 1,
                    sampleFrequencyHz: 24000
                ),
                chat: VersionRange(minVersion: 1, maxVersion: 1),
                control: VersionRange(minVersion: 1, maxVersion: 3),
                input: VersionRange(minVersion: 1, maxVersion: 9),
                message: VersionRange(minVersion: 1, maxVersion: 1),
                reliableinput: VersionRange(minVersion: 9, maxVersion: 9),
                unreliableinput: VersionRange(minVersion: 9, maxVersion: 9)
            )
        )
        let (postData, postResponse) = try await postRaw("\(sessionPath)/sdp", body: body)
        if let immediateAnswer = try parseSDPResponse(data: postData, response: postResponse) {
            return immediateAnswer
        }

        // Poll until answer is available
        return try await pollForSDP(sessionPath: sessionPath)
    }

    private func pollForSDP(sessionPath: String, maxAttempts: Int = 60) async throws -> String {
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 500_000_000)
            if let sdp = try await getSDPAnswer(sessionPath: sessionPath) {
                return sdp
            }
        }
        throw APIError.timeout
    }

    /// Reads the signaling endpoint after the offer POST when the server answers asynchronously.
    private func getSDPAnswer(sessionPath: String) async throws -> String? {
        let (data, response) = try await rawGet("\(sessionPath)/sdp")
        return try parseSDPResponse(data: data, response: response)
    }

    /// Normalizes and posts local ICE candidates, then polls for the remote candidate set.
    public func sendICECandidates(
        sessionPath: String,
        candidates: [IceCandidatePayload],
        preferIPv6: Bool = false,
        maxPollAttempts: Int = 30,
        pollIntervalSeconds: TimeInterval = 1.0
    ) async throws -> [IceCandidatePayload] {
        let normalizedCandidates = candidates.compactMap { candidate -> IceCandidatePayload? in
            guard let normalizedCandidate = normalizeOutboundICECandidate(candidate.candidate) else { return nil }
            return IceCandidatePayload(
                candidate: normalizedCandidate,
                sdpMLineIndex: candidate.sdpMLineIndex,
                sdpMid: candidate.sdpMid,
                usernameFragment: candidate.usernameFragment
            )
        }
        let dedupedCandidates = dedupeICECandidates(normalizedCandidates)
        let sortedCandidates = sortICECandidates(dedupedCandidates, preferIPv6: preferIPv6)
        let preferredCandidates = sortedCandidates.filter {
            isPreferredOutboundICECandidate($0.candidate, preferIPv6: preferIPv6)
        }
        let candidatesToSend = preferredCandidates.isEmpty ? sortedCandidates : preferredCandidates
        let wireCandidates = candidatesToSend.map {
            IceCandidateWire(
                candidate: $0.candidate,
                sdpMLineIndex: $0.sdpMLineIndex,
                sdpMid: $0.sdpMid,
                usernameFragment: $0.usernameFragment
            )
        }
        let encodedCandidates = try wireCandidates.map { try encodeICECandidateString($0) }
        print("ICE exchange posting \(encodedCandidates.count) candidate(s) (normalized \(dedupedCandidates.count) / gathered \(candidates.count), preferredIPv4UDP=\(!preferredCandidates.isEmpty), stringified=true)")
        try await postVoid("\(sessionPath)/ice", body: ICEOfferBody(candidates: encodedCandidates))
        return try await pollForICE(sessionPath: sessionPath, maxAttempts: maxPollAttempts, pollIntervalSeconds: pollIntervalSeconds)
    }

    /// Polls the ICE endpoint until the server publishes at least one usable remote candidate.
    private func pollForICE(
        sessionPath: String,
        maxAttempts: Int = 30,
        pollIntervalSeconds: TimeInterval = 1.0
    ) async throws -> [IceCandidatePayload] {
        for _ in 0..<maxAttempts {
            if pollIntervalSeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
            }
            if let candidates = try await getICEResponse(sessionPath: sessionPath) {
                return candidates
            }
        }
        return []
    }

    /// Fetches the remote ICE envelope once and returns nil while the server is still pending.
    private func getICEResponse(sessionPath: String) async throws -> [IceCandidatePayload]? {
        let (data, response) = try await rawGet("\(sessionPath)/ice")
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 204 { return nil }
        return try parseICEResponse(data: data)
    }

    public func sendMSALAuth(sessionPath: String, userToken: String) async throws {
        struct AuthBody: Encodable { let userToken: String }
        try await postVoid("\(sessionPath)/connect", body: AuthBody(userToken: userToken))
    }

    public func sendKeepalive(sessionPath: String) async throws {
        try await postVoid("\(sessionPath)/keepalive", body: EmptyBody())
    }

    public func stopSession(sessionPath: String) async throws {
        let url = URL(string: baseHost + sessionPath)!
        var request = makeRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await session.data(for: request)
    }

    // MARK: - Private HTTP Helpers

    private struct EmptyBody: Encodable {}

    /// Applies the shared auth and device headers required by xCloud and xHome endpoints.
    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XboxComBrowser", forHTTPHeaderField: "X-Gssv-Client")
        let deviceInfo = cachedDeviceInfo.isEmpty
            ? Self.makeDeviceInfo(
                locale: currentPreferences.locale,
                resolution: currentPreferences.resolution,
                osNameOverride: currentPreferences.osNameOverride
            )
            : cachedDeviceInfo
        request.setValue(deviceInfo, forHTTPHeaderField: "X-MS-Device-Info")
        request.setValue("Bearer \(gsToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(_ path: String, responseType: T.Type) async throws -> T {
        let (responseData, response) = try await rawGet(path)
        return try decodeResponse(data: responseData, response: response, as: responseType)
    }

    private func getLibrary<T: Decodable>(_ path: String, responseType: T.Type) async throws -> T {
        let (responseData, response) = try await rawGetLibrary(path)
        logFullLibraryPayloadIfNeeded(path: path, data: responseData, response: response)
        return try decodeResponse(data: responseData, response: response, as: responseType)
    }

    /// Enforces the common HTTP-status contract and wraps JSON decoding failures in APIError.
    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse, as responseType: T.Type) throws -> T {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func rawGet(_ path: String) async throws -> (Data, URLResponse) {
        let url = URL(string: baseHost + path)!
        var request = makeRequest(url: url)
        request.httpMethod = "GET"
        return try await session.data(for: request)
    }

    private func rawGetLibrary(_ path: String) async throws -> (Data, URLResponse) {
        let url = URL(string: baseHost + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(gsToken)", forHTTPHeaderField: "Authorization")
        return try await session.data(for: request)
    }

    private func logFullLibraryPayloadIfNeeded(path: String, data: Data, response: URLResponse) {
        guard AppLogConfiguration.isEnabled else { return }
        guard path == "/v2/titles" else { return }
        guard resolvedHost(for: response) == "xgpuwebf2p.gssv-play-prod.xboxlive.com" else { return }

        let body = String(data: data, encoding: .utf8) ?? "<binary>"
        logger.info("Logging raw /v2/titles payload for xgpuwebf2p.gssv-play-prod.xboxlive.com")
        print("XCloud F2P /v2/titles raw response (\(response.url?.absoluteString ?? baseHost + path)):\n\(body)")
    }

    private func logRawStartStreamRequestIfNeeded<Req: Encodable>(
        path: String,
        preferences: StreamPreferences,
        body: Req,
        deviceInfo: String
    ) {
        guard AppLogConfiguration.isEnabled else { return }
        guard !didLogRawStartStreamRequest else { return }
        didLogRawStartStreamRequest = true

        let bodyText: String
        if let bodyData = try? JSONEncoder().encode(body),
           let text = String(data: bodyData, encoding: .utf8) {
            bodyText = text
        } else {
            bodyText = "<encode-failed>"
        }

        let resolvedOSName = normalizedDeviceOSNameOverride(preferences.osNameOverride) ?? preferences.resolution.osName
        print("[XCloudAPI][RawStartStream] path=\(path)")
        print(
            "[XCloudAPI][RawStartStream] resolution=\(preferences.resolution.rawValue) osName=\(resolvedOSName) " +
            "display=\(preferences.resolution.displayWidth)x\(preferences.resolution.displayHeight) locale=\(preferences.locale)"
        )
        print("[XCloudAPI][RawStartStream] header[X-MS-Device-Info]=\(deviceInfo)")
        print("[XCloudAPI][RawStartStream] body=\(bodyText)")
    }

    private func post<Req: Encodable, Res: Decodable>(_ path: String, body: Req, responseType: Res.Type) async throws -> Res {
        let url = URL(string: baseHost + path)!
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let responseBody = String(data: responseData, encoding: .utf8) ?? ""
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, responseBody)
        }
        do {
            return try JSONDecoder().decode(Res.self, from: responseData)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func postRaw<Req: Encodable>(_ path: String, body: Req) async throws -> (Data, URLResponse) {
        let url = URL(string: baseHost + path)!
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let responseBody = String(data: responseData, encoding: .utf8) ?? ""
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, responseBody)
        }
        return (responseData, response)
    }

    private func postVoid<Req: Encodable>(_ path: String, body: Req) async throws {
        let url = URL(string: baseHost + path)!
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let responseBody = String(data: responseData, encoding: .utf8) ?? ""
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, responseBody)
        }
    }

    // MARK: - Signaling response parsing

    private func parseSDPResponse(data: Data, response: URLResponse) throws -> String? {
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 204 || data.isEmpty { return nil }

        let raw = try jsonObject(from: data)
        if let (code, message) = extractSignalingErrorDetails(from: raw) {
            throw APIError.decodingError("SDP server error \(code): \(message)")
        }
        if let sdp = extractSDP(from: raw) {
            return sdp
        }

        throw APIError.decodingError("Malformed SDP envelope: \(truncatedBody(data))")
    }

    private func parseICEResponse(data: Data) throws -> [IceCandidatePayload]? {
        if data.isEmpty { return nil }

        let raw = try jsonObject(from: data)
        if let (code, message) = extractSignalingErrorDetails(from: raw) {
            throw APIError.decodingError("ICE server error \(code): \(message)")
        }
        if let candidates = extractICECandidates(from: raw) {
            return candidates
        }

        throw APIError.decodingError("Malformed ICE envelope: \(truncatedBody(data))")
    }

    private func extractSDP(from raw: Any) -> String? {
        if let dict = raw as? [String: Any] {
            if let sdp = dict["sdp"] as? String, !sdp.isEmpty {
                return sdp
            }
            if let exchange = dict["exchangeResponse"] {
                return extractSDP(from: exchange)
            }
            return nil
        }

        if let text = raw as? String {
            if let nested = decodeJSONString(text) {
                return extractSDP(from: nested)
            }
        }

        return nil
    }

    private func extractICECandidates(from raw: Any) -> [IceCandidatePayload]? {
        if let array = raw as? [Any] {
            return decodeCandidateArray(array)
        }

        if let dict = raw as? [String: Any] {
            if let exchange = dict["exchangeResponse"] {
                return extractICECandidates(from: exchange)
            }
            if let candidates = dict["iceCandidates"] {
                return extractICECandidates(from: candidates)
            }
            if let candidates = dict["candidates"] {
                return extractICECandidates(from: candidates)
            }
            if let single = decodeCandidate(dict) {
                return [single]
            }
            return nil
        }

        if let text = raw as? String, let nested = decodeJSONString(text) {
            return extractICECandidates(from: nested)
        }

        return nil
    }

    private func decodeCandidateArray(_ array: [Any]) -> [IceCandidatePayload]? {
        var decoded: [IceCandidatePayload] = []
        decoded.reserveCapacity(array.count)
        for element in array {
            guard let dict = element as? [String: Any],
                  let candidate = decodeCandidate(dict) else {
                return nil
            }
            decoded.append(candidate)
        }
        return decoded
    }

    private func decodeCandidate(_ dict: [String: Any]) -> IceCandidatePayload? {
        guard let candidate = dict["candidate"] as? String,
              let lineIndex = intValue(dict["sdpMLineIndex"]) else {
            return nil
        }
        let sdpMid = (dict["sdpMid"] as? String) ?? "0"
        let usernameFragment = dict["usernameFragment"] as? String
        return IceCandidatePayload(candidate: candidate, sdpMLineIndex: lineIndex, sdpMid: sdpMid, usernameFragment: usernameFragment)
    }

    private func extractSignalingErrorDetails(from raw: Any) -> (code: String, message: String)? {
        guard let dict = raw as? [String: Any],
              let errorDetails = dict["errorDetails"] as? [String: Any],
              let code = errorDetails["code"] as? String,
              let message = errorDetails["message"] as? String else {
            return nil
        }
        return (code, message)
    }

    private func encodeICECandidateString(_ candidate: IceCandidateWire) throws -> String {
        let data = try JSONEncoder().encode(candidate)
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.decodingError("Failed to encode outbound ICE candidate")
        }
        return text
    }

    private func normalizeOutboundICECandidate(_ candidate: String) -> String? {
        var normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("a=") {
            normalized.removeFirst(2)
        }
        if normalized.isEmpty || normalized == "end-of-candidates" {
            return nil
        }
        guard normalized.hasPrefix("candidate:") else {
            return nil
        }
        return normalized
    }

    private func dedupeICECandidates(_ candidates: [IceCandidatePayload]) -> [IceCandidatePayload] {
        var seen: Set<String> = []
        var uniqueCandidates: [IceCandidatePayload] = []
        uniqueCandidates.reserveCapacity(candidates.count)
        for candidate in candidates {
            let key = "\(candidate.sdpMid)|\(candidate.sdpMLineIndex)|\(candidate.candidate)"
            if seen.insert(key).inserted {
                uniqueCandidates.append(candidate)
            }
        }
        return uniqueCandidates
    }

    private func isPreferredOutboundICECandidate(_ candidate: String, preferIPv6: Bool) -> Bool {
        let parts = candidate.split(separator: " ")
        guard parts.count >= 8 else { return false }
        let transport = parts[2].lowercased()
        guard transport == "udp" else { return false }
        let address = String(parts[4])
        if preferIPv6 {
            return address.contains(":")
        }
        return isLiteralIPv4(address)
    }

    private func isLiteralIPv4(_ address: String) -> Bool {
        let octets = address.split(separator: ".")
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard let value = Int(octet), (0...255).contains(value) else { return false }
            return String(value) == octet || (octet == "0")
        }
    }

    private func sortICECandidates(_ candidates: [IceCandidatePayload], preferIPv6: Bool) -> [IceCandidatePayload] {
        let indexed = candidates.enumerated().map { ($0.offset, $0.element) }
        return indexed.sorted { lhs, rhs in
            let left = iceSortScore(lhs.1.candidate, preferIPv6: preferIPv6)
            let right = iceSortScore(rhs.1.candidate, preferIPv6: preferIPv6)
            if left == right { return lhs.0 < rhs.0 }
            return left < right
        }.map(\.1)
    }

    private func iceSortScore(_ candidate: String, preferIPv6: Bool) -> Int {
        let parts = candidate.split(separator: " ")
        guard parts.count >= 8 else { return 100 }
        let transport = parts[2].lowercased()
        let address = String(parts[4])
        let isUDP = transport == "udp"
        let isIPv4 = isLiteralIPv4(address)
        let isIPv6 = address.contains(":")

        if isUDP {
            if preferIPv6 {
                if isIPv6 { return 0 }
                if isIPv4 { return 1 }
            } else {
                if isIPv4 { return 0 }
                if isIPv6 { return 1 }
            }
            return 2
        }
        return 3
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func decodeJSONString(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func truncatedBody(_ data: Data, maxChars: Int = 256) -> String {
        let body = String(data: data, encoding: .utf8) ?? "<binary>"
        if body.count <= maxChars { return body }
        return String(body.prefix(maxChars)) + "…"
    }

    private func resolvedHost(for response: URLResponse) -> String? {
        if let host = response.url?.host?.lowercased(), !host.isEmpty {
            return host
        }
        return URL(string: baseHost)?.host?.lowercased()
    }
}

// MARK: - StartStream body helpers

private struct StartStreamBody: Encodable {
    let clientSessionId: String
    let titleId: String
    let systemUpdateGroup: String
    let settings: StreamSettings
    let serverId: String
    let fallbackRegionNames: [String]
}

private struct StreamSettings: Encodable {
    let nanoVersion = "V3;WebrtcTransport.dll"
    let enableOptionalDataCollection = false
    let enableTextToSpeech = false
    let highContrast = 0
    let locale: String
    let useIceConnection = false
    let timezoneOffsetMinutes = 120
    let sdkType = "web"
    let osName: String

    init(preferences: StreamPreferences) {
        self.locale = preferences.locale
        self.osName = normalizedDeviceOSNameOverride(preferences.osNameOverride) ?? preferences.resolution.osName
    }
}
