// MicrosoftAuthService.swift
// Defines the Microsoft and Xbox token-exchange service used to authenticate stream sessions.
//

import Foundation


// MARK: - Device Code Auth Response

/// Decodes the Microsoft device-code response used to start browser-based sign-in.
struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let verificationUriComplete: String?
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case verificationUriComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

// MARK: - Token Response

/// Decodes the Microsoft access-token response returned by device-code polling.
struct MSATokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

/// Decodes Microsoft device-code polling errors such as authorization pending or expiry.
struct MSATokenErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// Decodes the long-lived token response used for downstream Xbox token exchange.
struct LPTTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Xbox Live Token Structures

/// Encodes an Xbox authentication request for user or XSTS token exchange.
struct XboxAuthRequest: Encodable {
    let relyingParty: String
    let tokenType: String
    let properties: XboxAuthProperties

    enum CodingKeys: String, CodingKey {
        case relyingParty = "RelyingParty"
        case tokenType = "TokenType"
        case properties = "Properties"
    }
}

/// Encodes the properties payload nested under an Xbox authentication request.
struct XboxAuthProperties: Encodable {
    let authMethod: String?
    let siteName: String?
    let rpsTicket: String?
    let userTokens: [String]?
    let sandboxId: String?

    enum CodingKeys: String, CodingKey {
        case authMethod = "AuthMethod"
        case siteName = "SiteName"
        case rpsTicket = "RpsTicket"
        case userTokens = "UserTokens"
        case sandboxId = "SandboxId"
    }
}

/// Decodes the token payload returned by Xbox auth endpoints.
struct XboxTokenResponse: Decodable {
    let token: String
    let displayClaims: XboxDisplayClaims?

    enum CodingKeys: String, CodingKey {
        case token = "Token"
        case displayClaims = "DisplayClaims"
    }
}

/// Decodes Xbox display claims such as the user hash needed by downstream requests.
struct XboxDisplayClaims: Decodable {
    let xui: [XboxXui]?

    enum CodingKeys: String, CodingKey {
        case xui
    }
}

/// Decodes the XUI claim records that carry the user hash.
struct XboxXui: Decodable {
    let uhs: String?

    enum CodingKeys: String, CodingKey {
        case uhs
    }
}

// MARK: - Stream Token

/// Encodes the GSSV login request that exchanges Xbox auth for a stream token.
struct GssvLoginRequest: Encodable {
    let token: String
    let offeringId: String
}

/// Decodes the GSSV login response, including available cloud regions.
struct GssvLoginResponse: Decodable {
    let gsToken: String
    let offeringSettings: OfferingSettings?

    struct OfferingSettings: Decodable {
        let regions: [Region]?
    }

    struct Region: Decodable {
        let name: String?
        let baseUri: String?
        let isDefault: Bool?
    }

    /// Returns the default region URI, falling back to the first available region.
    var defaultRegionBaseURI: String? {
        let region = offeringSettings?.regions?.first(where: { $0.isDefault == true })
            ?? offeringSettings?.regions?.first
        return region?.baseUri
    }

    /// Converts raw offering regions into the client's `LoginRegion` value type.
    func allLoginRegions() -> [LoginRegion] {
        guard let regions = offeringSettings?.regions else { return [] }
        return regions.compactMap { r in
            guard let uri = r.baseUri, !uri.isEmpty else { return nil }
            let name = r.name
                ?? uri.replacingOccurrences(of: "https://", with: "").components(separatedBy: ".").first
                ?? uri
            return LoginRegion(name: name, baseUri: uri, isDefault: r.isDefault ?? false)
        }
    }

    enum CodingKeys: String, CodingKey {
        case gsToken
        case offeringSettings
    }
}

// MARK: - Errors

/// Describes the user-facing authentication and token-exchange failures surfaced by the service.
public enum AuthError: Error, LocalizedError, Sendable {
    case networkError(String)
    case deviceCodeExpired
    case authorizationPending
    case invalidResponse(String)
    case tokenExchangeFailed(String)
    case noStreamToken

    public var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .deviceCodeExpired: return "Device code expired. Please start over."
        case .authorizationPending: return "Waiting for user to authorize."
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .noStreamToken: return "No stream token available."
        }
    }
}

// MARK: - Public Auth Credentials

/// Carries the authenticated token bundle used by stream launch and Xbox web requests.
public struct StreamTokens: Sendable {
    public let xhomeToken: String
    public let xhomeHost: String
    public let xcloudToken: String?
    public let xcloudHost: String?
    /// F2P/owned-games offering token (xgpuwebf2p). Separate from xcloudToken (xgpuweb)
    /// because each offering returns a different game catalog from `/v2/titles`.
    public let xcloudF2PToken: String?
    public let xcloudF2PHost: String?
    public let webToken: String?
    public let webTokenUHS: String?
    /// All cloud stream regions from the login offering response.
    /// Empty when restored from keychain (populated fresh on each login/refresh).
    public let xcloudRegions: [LoginRegion]

    /// Creates a token bundle from the current xHome, xCloud, and optional web-token fields.
    public init(
        xhomeToken: String,
        xhomeHost: String,
        xcloudToken: String?,
        xcloudHost: String?,
        xcloudF2PToken: String? = nil,
        xcloudF2PHost: String? = nil,
        webToken: String? = nil,
        webTokenUHS: String? = nil,
        xcloudRegions: [LoginRegion] = []
    ) {
        self.xhomeToken = xhomeToken
        self.xhomeHost = xhomeHost
        self.xcloudToken = xcloudToken
        self.xcloudHost = xcloudHost
        self.xcloudF2PToken = xcloudF2PToken
        self.xcloudF2PHost = xcloudF2PHost
        self.xcloudRegions = xcloudRegions
        self.webToken = webToken
        self.webTokenUHS = webTokenUHS
    }
}

/// Carries the user-facing and polling-facing values needed for device-code sign-in.
public struct DeviceCodeInfo: Sendable {
    public let userCode: String
    public let verificationUri: String
    public let verificationUriComplete: String?
    public let expiresIn: Int
    public let interval: Int
    /// Opaque token required by the polling endpoint — NOT the human-readable `userCode`.
    public let deviceCode: String

    /// Creates a device-code value object from the Microsoft device-code response payload.
    public init(
        userCode: String,
        verificationUri: String,
        verificationUriComplete: String?,
        expiresIn: Int,
        interval: Int,
        deviceCode: String
    ) {
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.verificationUriComplete = verificationUriComplete
        self.expiresIn = expiresIn
        self.interval = interval
        self.deviceCode = deviceCode
    }
}

// MARK: - Microsoft Auth Service

/// Owns Microsoft device-code sign-in, Xbox token exchange, and stream-token acquisition.
public actor MicrosoftAuthService {
    // Client ID for the Entra-registered public client used by xal-node / Stratix v2.
    // The legacy "000000004C12AE6F" Xbox app client is rejected by the /devicecode endpoint.
    private static let clientId = "1f907974-e22b-4810-a9de-d9647380c97e"
    // Scopes required by xal-node: openid + profile for the id_token; offline_access for refresh token.
    private static let scope = "xboxlive.signin openid profile offline_access"
    // Passport console-transfer scoped token required by xCloud /connect ("LPT" in xal-node).
    private static let lptScope = "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"

    private let tokenStore: TokenStore
    private let session: URLSession

    public init(tokenStore: TokenStore, session: URLSession = .shared) {
        self.tokenStore = tokenStore
        self.session = session
    }

    // MARK: - Step 1: Request Device Code

    public func requestDeviceCode() async throws -> DeviceCodeInfo {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "scope", value: Self.scope)
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw AuthError.invalidResponse("Failed to encode device code request body")
        }

        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let responseBody = String(data: responseData, encoding: .utf8) ?? "<empty>"
            throw AuthError.invalidResponse("Device code request failed HTTP \(http.statusCode): \(responseBody)")
        }

        let decoded = try JSONDecoder().decode(DeviceCodeResponse.self, from: responseData)
        return DeviceCodeInfo(
            userCode: decoded.userCode,
            verificationUri: decoded.verificationUri+"?otc="+decoded.userCode,
            verificationUriComplete: decoded.verificationUriComplete,
            expiresIn: decoded.expiresIn,
            interval: decoded.interval,
            deviceCode: decoded.deviceCode
        )
    }

    // MARK: - Step 2: Poll for MSA Token

    public func pollForMSAToken(deviceCode: String, interval: Int = 5, maxWaitSeconds: Int = 900) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(maxWaitSeconds))
        let pollInterval = max(1, interval)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            do {
                let msaToken = try await exchangeDeviceCode(deviceCode: deviceCode)
                return msaToken
            } catch AuthError.authorizationPending {
                continue
            } catch AuthError.deviceCodeExpired {
                throw AuthError.deviceCodeExpired
            }
        }
        throw AuthError.deviceCodeExpired
    }

    private func exchangeDeviceCode(deviceCode: String) async throws -> String {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "device_code", value: deviceCode)
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw AuthError.invalidResponse("Failed to encode token request body")
        }

        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        // Check for pending / expired before checking HTTP status.
        // The response can include non-string fields, so decode only the keys we care about.
        if let errorResponse = try? JSONDecoder().decode(MSATokenErrorResponse.self, from: responseData) {
            switch errorResponse.error {
            case "authorization_pending":
                throw AuthError.authorizationPending
            case "expired_token", "authorization_declined":
                throw AuthError.deviceCodeExpired
            default:
                break
            }
        }

        guard httpResponse?.statusCode == 200 else {
            let responseBody = String(data: responseData, encoding: .utf8) ?? "<empty>"
            throw AuthError.invalidResponse("HTTP \(httpResponse?.statusCode ?? 0): \(responseBody)")
        }

        let tokenResponse = try JSONDecoder().decode(MSATokenResponse.self, from: responseData)
        try await tokenStore.saveMSAToken(tokenResponse.accessToken)
        if let refresh = tokenResponse.refreshToken {
            try await tokenStore.saveRefreshToken(refresh)
        }
        return tokenResponse.accessToken
    }

    // MARK: - Refresh Token Flow (used on startup)

    /// Re-derive stream tokens using a stored MSA refresh token.
    /// Call this on startup when cached gsTokens are absent or expired.
    public func refreshStreamTokens() async throws -> StreamTokens {
        guard let refreshToken = await tokenStore.loadRefreshToken() else {
            throw AuthError.noStreamToken
        }
        let newAccessToken = try await refreshMSAToken(refreshToken: refreshToken)
        return try await exchangeForStreamTokens(msaAccessToken: newAccessToken)
    }

    /// Fetch the xCloud /connect "Long Play Token" (Passport console transfer token).
    public func fetchLPTForCloudConnect() async throws -> String {
        guard let refreshToken = await tokenStore.loadRefreshToken() else {
            throw AuthError.noStreamToken
        }
        return try await fetchLPT(refreshToken: refreshToken)
    }

    /// Mirrors xal-node's getMsalToken() path: exchange the MSA refresh token for a Passport
    /// console-transfer scoped token and use that token as /connect userToken.
    public func fetchLPT(refreshToken: String) async throws -> String {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "scope", value: Self.lptScope)
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw AuthError.invalidResponse("Failed to encode LPT request body")
        }

        var request = URLRequest(url: URL(string: "https://login.live.com/oauth20_token.srf")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errorPayload = (try? JSONDecoder().decode(MSATokenErrorResponse.self, from: responseData))
                .map { "\($0.error): \($0.errorDescription ?? "")" }
            let responseBody = errorPayload?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? errorPayload!
                : (String(data: responseData, encoding: .utf8) ?? "<empty>")
            throw AuthError.tokenExchangeFailed("LPT HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(responseBody)")
        }

        let tokenResponse = try JSONDecoder().decode(LPTTokenResponse.self, from: responseData)
        let expiresAt = tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        try await tokenStore.saveLPTToken(tokenResponse.accessToken, expiresAt: expiresAt)
        if let newRefresh = tokenResponse.refreshToken, !newRefresh.isEmpty {
            try await tokenStore.saveRefreshToken(newRefresh)
        }
        return tokenResponse.accessToken
    }

    private func refreshMSAToken(refreshToken: String) async throws -> String {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "scope", value: Self.scope)
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw AuthError.invalidResponse("Failed to encode refresh token request body")
        }

        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let responseBody = String(data: responseData, encoding: .utf8) ?? "<empty>"
            throw AuthError.tokenExchangeFailed("Refresh HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(responseBody)")
        }

        let tokenResponse = try JSONDecoder().decode(MSATokenResponse.self, from: responseData)
        try await tokenStore.saveMSAToken(tokenResponse.accessToken)
        // Rotate the stored refresh token if Microsoft issued a new one
        if let newRefresh = tokenResponse.refreshToken {
            try await tokenStore.saveRefreshToken(newRefresh)
        }
        return tokenResponse.accessToken
    }

    // MARK: - Step 3: MSA Token → Xbox User Token

    private func getXboxUserToken(msaAccessToken: String) async throws -> (token: String, uhs: String) {
        let body = XboxAuthRequest(
            relyingParty: "http://auth.xboxlive.com",
            tokenType: "JWT",
            properties: XboxAuthProperties(
                authMethod: "RPS",
                siteName: "user.auth.xboxlive.com",
                rpsTicket: "d=\(msaAccessToken)",
                userTokens: nil,
                sandboxId: nil
            )
        )
        let response = try await postXboxJSON(
            url: "https://user.auth.xboxlive.com/user/authenticate",
            body: body,
            responseType: XboxTokenResponse.self
        )
        let uhs = response.displayClaims?.xui?.first?.uhs ?? ""
        return (response.token, uhs)
    }

    // MARK: - Step 4: Xbox User Token → XSTS Token (GSSV)

    private func getXSTSToken(
        userToken: String,
        relyingParty: String = "http://gssv.xboxlive.com/"
    ) async throws -> (token: String, uhs: String) {
        let body = XboxAuthRequest(
            relyingParty: relyingParty,
            tokenType: "JWT",
            properties: XboxAuthProperties(
                authMethod: nil,
                siteName: nil,
                rpsTicket: nil,
                userTokens: [userToken],
                sandboxId: "RETAIL"
            )
        )
        let response = try await postXboxJSON(
            url: "https://xsts.auth.xboxlive.com/xsts/authorize",
            body: body,
            responseType: XboxTokenResponse.self
        )
        let uhs = response.displayClaims?.xui?.first?.uhs ?? ""
        return (response.token, uhs)
    }

    private func getWebToken(userToken: String) async throws -> (token: String, uhs: String) {
        try await getXSTSToken(userToken: userToken, relyingParty: "http://xboxlive.com")
    }

    // MARK: - Step 5: XSTS Token → Stream Token (xhome / xcloud)

    /// Obtain a gsToken from the GSSV login endpoint.
    ///
    /// Body format matches xal-node: `{ "token": <xstsToken>, "offeringId": <offering> }`
    /// The XSTS token is placed in the body — NOT in an `Authorization: XBL3.0` header.
    private func getStreamToken(xstsToken: String, offering: String) async throws -> (gsToken: String, host: String, regions: [LoginRegion]) {
        let host = "\(offering).gssv-play-prod.xboxlive.com"
        var request = URLRequest(url: URL(string: "https://\(host)/v2/login/user")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XboxComBrowser", forHTTPHeaderField: "x-gssv-client")
        request.httpBody = try JSONEncoder().encode(GssvLoginRequest(token: xstsToken, offeringId: offering))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AuthError.tokenExchangeFailed("Stream token HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(bodyStr)")
        }
        let loginResponse = try JSONDecoder().decode(GssvLoginResponse.self, from: data)
        let resolvedHost = loginResponse.defaultRegionBaseURI ?? "https://\(host)"
        return (
            loginResponse.gsToken,
            resolvedHost.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            loginResponse.allLoginRegions()
        )
    }

    // MARK: - Full Token Exchange Flow

    public func exchangeForStreamTokens(msaAccessToken: String) async throws -> StreamTokens {
        let (userToken, _) = try await getXboxUserToken(msaAccessToken: msaAccessToken)
        let (xstsToken, _) = try await getXSTSToken(userToken: userToken)
        let webTokenResult = try? await getWebToken(userToken: userToken)

        let (xhomeGsToken, xhomeHost, _) = try await getStreamToken(xstsToken: xstsToken, offering: "xhome")

        // Fetch both xgpuweb (Game Pass subscription) and xgpuwebf2p (F2P/owned games)
        // concurrently. Each offering returns a different game catalog from /v2/titles,
        // so we need both to show the full library. (Ref: Stratix #918)
        var xcloudGsToken: String?
        var xcloudHost: String?
        var xcloudRegions: [LoginRegion] = []
        var f2pGsToken: String?
        var f2pHost: String?

        async let xgpuwebTask: (gsToken: String, host: String, regions: [LoginRegion])? = {
            try? await self.getStreamToken(xstsToken: xstsToken, offering: "xgpuweb")
        }()
        async let f2pTask: (gsToken: String, host: String, regions: [LoginRegion])? = {
            try? await self.getStreamToken(xstsToken: xstsToken, offering: "xgpuwebf2p")
        }()

        let xgpuwebResult = await xgpuwebTask
        let f2pResult = await f2pTask

        if let result = xgpuwebResult {
            xcloudGsToken = result.gsToken
            xcloudHost = result.host
            xcloudRegions = result.regions
        }
        if let result = f2pResult {
            f2pGsToken = result.gsToken
            f2pHost = result.host
            // Use F2P regions as fallback if xgpuweb had none
            if xcloudRegions.isEmpty {
                xcloudRegions = result.regions
            }
        }

        let tokens = StreamTokens(
            xhomeToken: xhomeGsToken,
            xhomeHost: xhomeHost,
            xcloudToken: xcloudGsToken,
            xcloudHost: xcloudHost,
            xcloudF2PToken: f2pGsToken,
            xcloudF2PHost: f2pHost,
            webToken: webTokenResult?.token,
            webTokenUHS: webTokenResult?.uhs,
            xcloudRegions: xcloudRegions
        )
        try await tokenStore.saveStreamTokens(tokens)
        return tokens
    }

    // MARK: - Restore from Keychain

    public func restoreStreamTokens() async -> StreamTokens? {
        await tokenStore.loadStreamTokens()
    }

    // MARK: - Sign Out

    public func signOut() async throws {
        try await tokenStore.clearAll()
    }

    // MARK: - Helpers

    /// POST JSON with Xbox Live contract headers.
    /// `x-xbl-contract-version: 1` is required by the Xbox auth endpoints.
    private func postXboxJSON<Req: Encodable, Res: Decodable>(
        url: String,
        body: Req,
        responseType: Res.Type
    ) async throws -> Res {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AuthError.tokenExchangeFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(bodyStr)")
        }
        return try JSONDecoder().decode(responseType, from: data)
    }
}
