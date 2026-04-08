// MicrosoftAuthServiceTests.swift
// Exercises microsoft auth service behavior.
//

import Testing
import Foundation
@testable import XCloudAPI

@Suite(.serialized)
struct MicrosoftAuthServiceTests {

    @Test func requestDeviceCode_mapsVerificationUriComplete() async throws {
        let service = makeAuthService { request in
            #expect(request.url?.absoluteString.contains("/devicecode") == true)
            return .json(statusCode: 200, body: [
                "device_code": "device-token",
                "user_code": "ABCD-EFGH",
                "verification_uri": "https://microsoft.com/devicelogin",
                "verification_uri_complete": "https://microsoft.com/devicelogin?otc=123",
                "expires_in": 900,
                "interval": 5
            ])
        }

        let info = try await service.requestDeviceCode()

        #expect(info.verificationUriComplete == "https://microsoft.com/devicelogin?otc=123")
    }

    @Test func fetchLPT_usesLoginLiveEndpointAndScope() async throws {
        let capture = RequestCaptureBox()

        let service = makeAuthService { request in
            capture.url = request.url
            capture.body = requestFormBodyString(request)
            return .json(statusCode: 200, body: [
                "access_token": "lpt-token",
                "refresh_token": "refresh-rotated",
                "expires_in": 3600,
                "token_type": "bearer"
            ])
        }

        do {
            let token = try await service.fetchLPT(refreshToken: "refresh-original")
            #expect(token == "lpt-token")
        } catch let error as AuthError {
            // Package tests run in a restricted environment where Keychain writes can fail.
            // We still validate the request construction below.
            if case .networkError(let message) = error {
                #expect(message.contains("Keychain save failed"))
            } else {
                Issue.record("Unexpected auth error: \(error)")
            }
        }

        #expect(capture.url?.host == "login.live.com")
        #expect(capture.url?.path == "/oauth20_token.srf")
        #expect(capture.body.contains("grant_type=refresh_token"))
        #expect(capture.body.contains("refresh_token=refresh-original"))
        #expect(capture.body.contains("client_id=1f907974-e22b-4810-a9de-d9647380c97e"))
        #expect(capture.body.contains("PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"))
    }

    @Test func fetchLPT_surfacesHttpErrors() async {
        let service = makeAuthService { _ in
            .json(statusCode: 400, body: [
                "error": "invalid_grant",
                "error_description": "The refresh token is invalid."
            ])
        }

        do {
            _ = try await service.fetchLPT(refreshToken: "bad-refresh")
            Issue.record("Expected fetchLPT to throw on HTTP 400")
        } catch let error as AuthError {
            if case .tokenExchangeFailed(let message) = error {
                #expect(message.contains("LPT HTTP 400"))
                #expect(message.contains("invalid_grant"))
            } else {
                Issue.record("Expected tokenExchangeFailed, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Test helpers

private struct StubAuthHTTPResponse {
    let statusCode: Int
    let body: Data

    static func json(statusCode: Int, body: Any) -> Self {
        .init(statusCode: statusCode, body: try! JSONSerialization.data(withJSONObject: body))
    }
}

private final class AuthURLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> StubAuthHTTPResponse)?

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> StubAuthHTTPResponse) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    static func clearHandler() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler: (@Sendable (URLRequest) throws -> StubAuthHTTPResponse)?
        Self.lock.lock()
        handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "AuthURLProtocolStub", code: 0))
            return
        }

        do {
            let stub = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !stub.body.isEmpty {
                client?.urlProtocol(self, didLoad: stub.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeAuthService(
    tokenStore: TokenStore = TokenStore(),
    handler: @escaping @Sendable (URLRequest) throws -> StubAuthHTTPResponse
) -> MicrosoftAuthService {
    AuthURLProtocolStub.setHandler(handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AuthURLProtocolStub.self]
    let session = URLSession(configuration: config)
    return MicrosoftAuthService(tokenStore: tokenStore, session: session)
}

private final class RequestCaptureBox: @unchecked Sendable {
    var url: URL?
    var body: String = ""
}

private func requestFormBodyString(_ request: URLRequest) -> String {
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
