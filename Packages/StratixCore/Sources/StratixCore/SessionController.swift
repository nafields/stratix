// SessionController.swift
// Defines the session controller that owns sign-in, token refresh, and session auth state.
//

import DiagnosticsKit
import Foundation
import StratixModels
import Observation
import StreamingCore
import XCloudAPI

public enum SessionAuthState: Sendable {
    case unknown
    case unauthenticated
    case authenticating(DeviceCodeInfo)
    case authenticated(StreamTokens)
}

/// Abstracts the auth/token operations that back `SessionController`.
protocol SessionAuthServing: Sendable {
    func restoreStreamTokens() async -> StreamTokens?
    func refreshStreamTokens() async throws -> StreamTokens
    func requestDeviceCode() async throws -> DeviceCodeInfo
    func pollForMSAToken(deviceCode: String, interval: Int) async throws -> String
    func exchangeForStreamTokens(msaAccessToken: String) async throws -> StreamTokens
    func fetchLPTForCloudConnect() async throws -> String
    func signOut() async throws
}

/// Wraps the Microsoft auth service behind the controller-facing auth interface.
private actor MicrosoftSessionAuthClient: SessionAuthServing {
    private let service: MicrosoftAuthService

    init(tokenStore: TokenStore = TokenStore()) {
        service = MicrosoftAuthService(tokenStore: tokenStore)
    }

    func restoreStreamTokens() async -> StreamTokens? {
        await service.restoreStreamTokens()
    }

    func refreshStreamTokens() async throws -> StreamTokens {
        try await service.refreshStreamTokens()
    }

    func requestDeviceCode() async throws -> DeviceCodeInfo {
        try await service.requestDeviceCode()
    }

    func pollForMSAToken(deviceCode: String, interval: Int) async throws -> String {
        try await service.pollForMSAToken(deviceCode: deviceCode, interval: interval)
    }

    func exchangeForStreamTokens(msaAccessToken: String) async throws -> StreamTokens {
        try await service.exchangeForStreamTokens(msaAccessToken: msaAccessToken)
    }

    func fetchLPTForCloudConnect() async throws -> String {
        try await service.fetchLPTForCloudConnect()
    }

    func signOut() async throws {
        try await service.signOut()
    }
}

enum SessionTokenApplyMode {
    case full
    case streamRefresh
}

private enum SessionTaskID {
    static let tokenRefresh = "tokenRefresh"
}

private enum SessionControllerError: Error {
    case unauthenticated
}

@Observable
@MainActor
/// Owns app auth state, token refresh orchestration, and session-facing credential access.
public final class SessionController {
    struct CloudConnectAuth: Sendable {
        let tokens: StreamTokens
        let userToken: String
    }

    public private(set) var authState: SessionAuthState = .unknown
    public private(set) var lastAuthError: String?
    public private(set) var xcloudRegions: [LoginRegion] = []

    let taskRegistry = TaskRegistry()
    private weak var eventSink: (any SessionControllerEventSink)?
    private let defaults: UserDefaults
    private let authClient: any SessionAuthServing
    private let logger = GLogger(category: .auth)
    private let xcloudRegionsDefaultsKey = "stratix.stream.xcloudRegions"
    private var lastTokenRefreshAttemptAt: Date?

    /// Creates the session controller with overridable defaults and auth client dependencies.
    init(
        defaults: UserDefaults = .standard,
        authClient: (any SessionAuthServing)? = nil
    ) {
        self.defaults = defaults
        self.authClient = authClient ?? MicrosoftSessionAuthClient()
    }

    /// Attaches the app coordinator sink for sign-out and authentication side effects.
    func attach(_ eventSink: any SessionControllerEventSink) {
        self.eventSink = eventSink
    }

    /// Restores cached auth state on boot or falls back to a refresh-token sign-in flow.
    public func onAppear() async {
        if let tokens = await authClient.restoreStreamTokens() {
            await applyTokens(tokens, mode: .full)
            await refreshStreamTokensInBackground(reason: "startup_cached_tokens", minimumInterval: 0)
            return
        }

        do {
            logger.info("No cached stream tokens — attempting refresh token flow…")
            let tokens = try await authClient.refreshStreamTokens()
            await applyTokens(tokens, mode: .full)
            logger.info("Silently re-authenticated via refresh token.")
        } catch {
            logger.info("Refresh token unavailable or expired — user must sign in.")
            authState = .unauthenticated
        }
    }

    /// Starts the interactive device-code sign-in flow and applies the resulting tokens.
    public func beginSignIn() async {
        lastAuthError = nil
        do {
            logger.info("Requesting device code…")
            let deviceCodeInfo = try await authClient.requestDeviceCode()
            authState = .authenticating(deviceCodeInfo)
            logger.info("Device code obtained — polling for MSA token…")

            let msaToken = try await authClient.pollForMSAToken(
                deviceCode: deviceCodeInfo.deviceCode,
                interval: deviceCodeInfo.interval
            )
            logger.info("MSA token received — exchanging for stream tokens…")

            let tokens = try await authClient.exchangeForStreamTokens(msaAccessToken: msaToken)
            await applyTokens(tokens, mode: .full)
            logger.info("Authentication complete. xhome host: \(tokens.xhomeHost)")
        } catch {
            logger.error("Auth failed: \(error.localizedDescription)")
            lastAuthError = error.localizedDescription
            authState = .unauthenticated
        }
    }

    /// Clears auth state, cancels outstanding token work, and notifies the app coordinator.
    public func signOut() async {
        try? await authClient.signOut()
        await taskRegistry.cancelAll()
        lastTokenRefreshAttemptAt = nil
        authState = .unauthenticated
        lastAuthError = nil
        clearCachedRegions()
        await eventSink?.handleSessionDidSignOutFromController()
    }

    /// Refreshes stream tokens opportunistically while respecting throttling and in-flight work.
    public func refreshStreamTokensInBackground(reason: String, minimumInterval: TimeInterval) async {
        if let lastAttempt = lastTokenRefreshAttemptAt,
           Date().timeIntervalSince(lastAttempt) < minimumInterval {
            logger.info("Token refresh skipped (\(reason)): throttled")
            return
        }

        let (_, inserted) = await tokenRefreshTask(reason: reason)

        guard inserted else {
            logger.info("Token refresh skipped (\(reason)): request already in flight")
            return
        }

        lastTokenRefreshAttemptAt = Date()
    }

    /// Returns refreshed stream tokens, joining an existing refresh task when one is already running.
    func refreshStreamTokens(logContext: String? = nil) async throws -> StreamTokens {
        guard case .authenticated = authState else {
            throw SessionControllerError.unauthenticated
        }
        let reason = logContext ?? "interactive"
        let (task, inserted) = await tokenRefreshTask(reason: reason)
        if inserted {
            lastTokenRefreshAttemptAt = Date()
        } else if let logContext {
            logger.info("Joining in-flight stream token refresh (\(logContext))")
        }
        let refreshResult = await task.value
        switch refreshResult {
        case .success(let refreshedTokens):
            return refreshedTokens
        case .failure(let error):
            throw error
        }
    }

    /// Returns Xbox web credentials, refreshing tokens first when the cached bundle lacks them.
    func xboxWebCredentials(logContext: String) async -> XboxWebCredentials? {
        guard let tokens = await authenticatedTokensWithWebToken(logContext: logContext) else { return nil }
        guard let webToken = tokens.webToken, !webToken.isEmpty,
              let webTokenUHS = tokens.webTokenUHS, !webTokenUHS.isEmpty else {
            return nil
        }
        return XboxWebCredentials(token: webToken, uhs: webTokenUHS)
    }

    /// Ensures the caller has an authenticated token bundle that includes web-token fields.
    func authenticatedTokensWithWebToken(logContext: String) async -> StreamTokens? {
        guard case .authenticated(let currentTokens) = authState else { return nil }
        if let webToken = currentTokens.webToken, !webToken.isEmpty,
           let webTokenUHS = currentTokens.webTokenUHS, !webTokenUHS.isEmpty {
            return currentTokens
        }

        do {
            return try await refreshStreamTokens(logContext: logContext)
        } catch {
            logger.warning("Could not refresh tokens for \(logContext): \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches the long-lived token needed by the xCloud `/connect` flow.
    func fetchLPTForCloudConnect() async throws -> String {
        try await authClient.fetchLPTForCloudConnect()
    }

    /// Refreshes stream tokens and fetches the connect user token for a cloud-stream launch.
    func cloudConnectAuth(logContext: String) async throws -> CloudConnectAuth {
        guard case .authenticated = authState else {
            throw SessionControllerError.unauthenticated
        }

        logger.info("Refreshing stream tokens before cloud stream…")
        let refreshedTokens = try await refreshStreamTokens(logContext: logContext)
        logger.info("Stream tokens refreshed successfully.")
        logger.info("Fetching LPT for xCloud /connect...")
        let connectUserToken = try await fetchLPTForCloudConnect()
        logger.info("LPT obtained for /connect auth step.")
        return CloudConnectAuth(tokens: refreshedTokens, userToken: connectUserToken)
    }

    /// Overrides the visible auth error string, primarily for controller-owned error handling.
    func setLastAuthError(_ message: String?) {
        lastAuthError = message
    }

    /// Applies a coordinator-provided token bundle using the requested propagation mode.
    func applyTokensFromCoordinator(_ tokens: StreamTokens, mode: SessionTokenApplyMode) async {
        await applyTokens(tokens, mode: mode)
    }

    func testingSetLastTokenRefreshAttemptAt(_ value: Date?) {
        lastTokenRefreshAttemptAt = value
    }

    var testingLastTokenRefreshAttemptAt: Date? {
        lastTokenRefreshAttemptAt
    }

    func testingSetXCloudRegions(_ regions: [LoginRegion]) {
        xcloudRegions = regions
        persistXCloudRegionsIfNeeded(regions)
    }

    private func applyTokens(_ tokens: StreamTokens, mode: SessionTokenApplyMode) async {
        authState = .authenticated(tokens)
        lastAuthError = nil
        updateXCloudRegions(with: tokens)
        StreamMetricsPipeline.shared.recordMilestone(
            .authReady,
            metadata: ["mode": mode == .full ? "full" : "stream_refresh"]
        )
        await eventSink?.handleSessionDidAuthenticateFromController(tokens: tokens, mode: mode)
    }

    private func tokenRefreshTask(
        reason: String
    ) async -> (task: Task<Result<StreamTokens, Error>, Never>, inserted: Bool) {
        let registry = taskRegistry
        return await taskRegistry.taskOrRegister(id: SessionTaskID.tokenRefresh) {
            Task { [weak self, registry] in
                guard let self else {
                    await registry.remove(id: SessionTaskID.tokenRefresh)
                    return .failure(SessionControllerError.unauthenticated)
                }
                guard await MainActor.run(body: {
                    if case .authenticated = self.authState {
                        return true
                    }
                    return false
                }) else {
                    await registry.remove(id: SessionTaskID.tokenRefresh)
                    return .failure(SessionControllerError.unauthenticated)
                }

                do {
                    await MainActor.run {
                        self.logger.info("Refreshing stream tokens (\(reason))")
                    }
                    let refreshedTokens = try await self.authClient.refreshStreamTokens()
                    await self.applyTokens(refreshedTokens, mode: .streamRefresh)
                    await MainActor.run {
                        self.logger.info("Stream token refresh complete (\(reason))")
                    }
                    await registry.remove(id: SessionTaskID.tokenRefresh)
                    return .success(refreshedTokens)
                } catch {
                    await MainActor.run {
                        self.logger.warning("Stream token refresh failed (\(reason)): \(error.localizedDescription)")
                    }
                    await registry.remove(id: SessionTaskID.tokenRefresh)
                    return .failure(error)
                }
            }
        }
    }

    private func updateXCloudRegions(with tokens: StreamTokens) {
        if !tokens.xcloudRegions.isEmpty {
            xcloudRegions = tokens.xcloudRegions
            persistXCloudRegionsIfNeeded(tokens.xcloudRegions)
        } else if xcloudRegions.isEmpty,
                  let cachedRegionsData = defaults.data(forKey: xcloudRegionsDefaultsKey),
                  let cached = try? JSONDecoder().decode([LoginRegion].self, from: cachedRegionsData) {
            xcloudRegions = cached
        }
    }

    private func persistXCloudRegionsIfNeeded(_ regions: [LoginRegion]) {
        guard let encodedRegions = try? JSONEncoder().encode(regions) else { return }
        defaults.set(encodedRegions, forKey: xcloudRegionsDefaultsKey)
    }

    private func clearCachedRegions() {
        xcloudRegions = []
        defaults.removeObject(forKey: xcloudRegionsDefaultsKey)
    }
}
