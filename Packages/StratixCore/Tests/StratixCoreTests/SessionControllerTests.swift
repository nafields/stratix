// SessionControllerTests.swift
// Exercises session controller behavior.
//

import Foundation
import Testing
import DiagnosticsKit
import os
@testable import StratixCore
import XCloudAPI

@MainActor
@Suite(.serialized)
struct SessionControllerTests {
    @Test
    func onAppear_restoresCachedTokensAndRegionFallback() async {
        let suiteName = "SessionControllerTests.onAppear.restoresCachedTokensAndRegionFallback"
        let defaults = makeDefaults(suiteName: suiteName)
        let cachedRegion = LoginRegion(name: "weu", baseUri: "https://weu.example.com", isDefault: true)
        let stub = SessionAuthClientStub()
        await stub.setRestoreTokens(makeTokens(xcloudRegions: []))
        await stub.setRefreshResult(.failure(StubError.expected))

        if let data = try? JSONEncoder().encode([cachedRegion]) {
            defaults.set(data, forKey: "stratix.stream.xcloudRegions")
        }

        let controller = SessionController(defaults: defaults, authClient: stub)
        await controller.onAppear()

        #expect(isAuthenticated(controller.authState))
        #expect(controller.lastAuthError == nil)
        #expect(controller.xcloudRegions.map(\.name) == ["weu"])
    }

    @Test
    func beginSignIn_successPublishesAuthenticatedState() async {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.beginSignIn.successPublishesAuthenticatedState")
        let stub = SessionAuthClientStub()
        await stub.setRequestDeviceCodeResult(.success(makeDeviceCodeInfo()))
        await stub.setPollForMSATokenResult(.success("msa-access-token"))
        await stub.setExchangeResult(.success(makeTokens(
            webToken: "web-token",
            webTokenUHS: "uhs",
            xcloudRegions: [LoginRegion(name: "eus", baseUri: "https://eus.example.com", isDefault: true)]
        )))

        let controller = SessionController(defaults: defaults, authClient: stub)
        await controller.beginSignIn()

        #expect(isAuthenticated(controller.authState))
        #expect(controller.lastAuthError == nil)
        #expect(controller.xcloudRegions.map(\.name) == ["eus"])
    }

    @Test
    func applyTokens_recordsAuthReadyMilestoneInSharedPipeline() async {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.applyTokens.recordsAuthReadyMilestoneInSharedPipeline")
        let controller = SessionController(defaults: defaults, authClient: SessionAuthClientStub())
        let records = OSAllocatedUnfairLock(initialState: [StreamMetricsRecord]())
        let token = StreamMetricsPipeline.shared.registerSink(
            StreamMetricsSink(name: #function) { record in
                records.withLock { $0.append(record) }
            }
        )
        defer { StreamMetricsPipeline.shared.unregisterSink(token) }

        await controller.applyTokensFromCoordinator(makeTokens(), mode: .full)

        let authReadyRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone.milestone == .authReady ? milestone : nil
            }
        }
        #expect(authReadyRecords.contains { $0.metadata["mode"] == "full" })
    }

    @Test
    func beginSignIn_failurePublishesErrorAndUnauthenticatedState() async {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.beginSignIn.failurePublishesErrorAndUnauthenticatedState")
        let stub = SessionAuthClientStub()
        await stub.setRequestDeviceCodeResult(.failure(StubError.expected))

        let controller = SessionController(defaults: defaults, authClient: stub)
        await controller.beginSignIn()

        #expect(isUnauthenticated(controller.authState))
        #expect(controller.lastAuthError == StubError.expected.localizedDescription)
    }

    @Test
    func signOut_clearsSessionStateAndPersistedRegions() async {
        let suiteName = "SessionControllerTests.signOut.clearsSessionStateAndPersistedRegions"
        let defaults = makeDefaults(suiteName: suiteName)
        let stub = SessionAuthClientStub()
        let region = LoginRegion(name: "centralus", baseUri: "https://centralus.example.com", isDefault: false)
        let controller = SessionController(defaults: defaults, authClient: stub)

        await controller.applyTokensFromCoordinator(
            makeTokens(xcloudRegions: [region]),
            mode: .full
        )
        await controller.signOut()

        #expect(isUnauthenticated(controller.authState))
        #expect(controller.lastAuthError == nil)
        #expect(controller.xcloudRegions.isEmpty)
        #expect(defaults.data(forKey: "stratix.stream.xcloudRegions") == nil)
        #expect(await stub.signOutCallCount == 1)
    }

    @Test
    func refreshStreamTokensInBackground_deduplicatesInflightRequests() async {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.refreshStreamTokensInBackground.deduplicatesInflightRequests")
        let stub = SessionAuthClientStub()
        await stub.setRefreshDelayNanoseconds(150_000_000)
        await stub.setRefreshResult(.success(makeTokens()))
        let controller = SessionController(defaults: defaults, authClient: stub)

        await controller.applyTokensFromCoordinator(makeTokens(), mode: .full)
        await controller.refreshStreamTokensInBackground(reason: "test", minimumInterval: 0)
        await controller.refreshStreamTokensInBackground(reason: "test", minimumInterval: 0)
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(await stub.refreshCallCount == 1)
    }

    @Test
    func refreshStreamTokensInBackground_respectsMinimumInterval() async {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.refreshStreamTokensInBackground.respectsMinimumInterval")
        let stub = SessionAuthClientStub()
        await stub.setRefreshResult(.success(makeTokens()))
        let controller = SessionController(defaults: defaults, authClient: stub)

        await controller.applyTokensFromCoordinator(makeTokens(), mode: .full)
        controller.testingSetLastTokenRefreshAttemptAt(Date())
        await controller.refreshStreamTokensInBackground(reason: "throttle", minimumInterval: 60)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(await stub.refreshCallCount == 0)
    }

    @Test
    func refreshStreamTokens_joinsInflightBackgroundRefresh() async throws {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.refreshStreamTokens.joinsInflightBackgroundRefresh")
        let stub = SessionAuthClientStub()
        await stub.setRefreshDelayNanoseconds(150_000_000)
        await stub.setRefreshResult(.success(makeTokens(
            webToken: "web-token",
            webTokenUHS: "uhs",
            xcloudRegions: [LoginRegion(name: "eus", baseUri: "https://eus.example.com", isDefault: true)]
        )))
        let controller = SessionController(defaults: defaults, authClient: stub)

        await controller.applyTokensFromCoordinator(makeTokens(), mode: .full)
        await controller.refreshStreamTokensInBackground(reason: "foreground_resume", minimumInterval: 0)
        let refreshed = try await controller.refreshStreamTokens(logContext: "cloud stream start")

        #expect(await stub.refreshCallCount == 1)
        #expect(refreshed.webToken == "web-token")
        #expect(refreshed.webTokenUHS == "uhs")
        #expect(controller.xcloudRegions.map(\.name) == ["eus"])
    }

    @Test
    func cloudConnectAuth_usesFreshTokensAndFreshLPT() async throws {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.cloudConnectAuth.usesFreshTokensAndFreshLPT")
        let stub = SessionAuthClientStub()
        let refreshedTokens = makeTokens(
            webToken: "web-token",
            webTokenUHS: "uhs",
            xcloudRegions: [LoginRegion(name: "eus", baseUri: "https://eus.example.com", isDefault: true)]
        )
        await stub.setRefreshResult(.success(refreshedTokens))
        await stub.setFetchLPTResult(.success("fresh-lpt"))
        let controller = SessionController(defaults: defaults, authClient: stub)

        await controller.applyTokensFromCoordinator(makeTokens(), mode: .full)
        let auth = try await controller.cloudConnectAuth(logContext: "cloud stream start")

        #expect(await stub.refreshCallCount == 1)
        #expect(await stub.fetchLPTCallCount == 1)
        #expect(auth.tokens.webToken == "web-token")
        #expect(auth.tokens.webTokenUHS == "uhs")
        #expect(auth.userToken == "fresh-lpt")
        #expect(controller.xcloudRegions.map(\.name) == ["eus"])
    }

    @Test
    func cloudConnectAuth_throwsWhenTokenRefreshFails() async {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.cloudConnectAuth.throwsWhenTokenRefreshFails")
        let stub = SessionAuthClientStub()
        await stub.setRefreshResult(.failure(StubError.expected))
        await stub.setFetchLPTResult(.success("fresh-lpt"))
        let controller = SessionController(defaults: defaults, authClient: stub)

        await controller.applyTokensFromCoordinator(makeTokens(), mode: .full)

        do {
            _ = try await controller.cloudConnectAuth(logContext: "cloud stream start")
            Issue.record("Expected cloudConnectAuth to throw when token refresh fails")
        } catch {
            #expect(await stub.refreshCallCount == 1)
            #expect(await stub.fetchLPTCallCount == 0)
        }
    }

    @Test
    func cloudConnectAuth_throwsWhenLPTFetchFailsAfterRefreshSucceeds() async {
        let defaults = makeDefaults(suiteName: "SessionControllerTests.cloudConnectAuth.throwsWhenLPTFetchFailsAfterRefreshSucceeds")
        let stub = SessionAuthClientStub()
        await stub.setRefreshResult(.success(makeTokens()))
        await stub.setFetchLPTResult(.failure(StubError.expected))
        let controller = SessionController(defaults: defaults, authClient: stub)

        await controller.applyTokensFromCoordinator(makeTokens(), mode: .full)

        do {
            _ = try await controller.cloudConnectAuth(logContext: "cloud stream start")
            Issue.record("Expected cloudConnectAuth to throw when LPT fetch fails")
        } catch {
            #expect(await stub.refreshCallCount == 1)
            #expect(await stub.fetchLPTCallCount == 1)
        }
    }

    private func makeDefaults(suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTokens(
        webToken: String? = nil,
        webTokenUHS: String? = nil,
        xcloudRegions: [LoginRegion] = []
    ) -> StreamTokens {
        StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: "https://xcloud.example.com",
            webToken: webToken,
            webTokenUHS: webTokenUHS,
            xcloudRegions: xcloudRegions
        )
    }

    private func makeDeviceCodeInfo() -> DeviceCodeInfo {
        DeviceCodeInfo(
            userCode: "ABCD-1234",
            verificationUri: "https://microsoft.com/link",
            verificationUriComplete: nil,
            expiresIn: 900,
            interval: 5,
            deviceCode: "device-code"
        )
    }

    private func isAuthenticated(_ state: SessionAuthState) -> Bool {
        if case .authenticated = state {
            return true
        }
        return false
    }

    private func isUnauthenticated(_ state: SessionAuthState) -> Bool {
        if case .unauthenticated = state {
            return true
        }
        return false
    }
}

private actor SessionAuthClientStub: SessionAuthServing {
    var restoreTokens: StreamTokens?
    var refreshResult: Result<StreamTokens, Error> = .failure(StubError.expected)
    var requestDeviceCodeResult: Result<DeviceCodeInfo, Error> = .failure(StubError.expected)
    var pollForMSATokenResult: Result<String, Error> = .failure(StubError.expected)
    var exchangeResult: Result<StreamTokens, Error> = .failure(StubError.expected)
    var fetchLPTResult: Result<String, Error> = .failure(StubError.expected)
    var refreshDelayNanoseconds: UInt64 = 0
    var refreshCallCount = 0
    var fetchLPTCallCount = 0
    var signOutCallCount = 0

    func setRestoreTokens(_ value: StreamTokens?) {
        restoreTokens = value
    }

    func setRefreshResult(_ value: Result<StreamTokens, Error>) {
        refreshResult = value
    }

    func setRequestDeviceCodeResult(_ value: Result<DeviceCodeInfo, Error>) {
        requestDeviceCodeResult = value
    }

    func setPollForMSATokenResult(_ value: Result<String, Error>) {
        pollForMSATokenResult = value
    }

    func setExchangeResult(_ value: Result<StreamTokens, Error>) {
        exchangeResult = value
    }

    func setFetchLPTResult(_ value: Result<String, Error>) {
        fetchLPTResult = value
    }

    func setRefreshDelayNanoseconds(_ value: UInt64) {
        refreshDelayNanoseconds = value
    }

    func restoreStreamTokens() async -> StreamTokens? {
        restoreTokens
    }

    func refreshStreamTokens() async throws -> StreamTokens {
        refreshCallCount += 1
        if refreshDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: refreshDelayNanoseconds)
        }
        return try refreshResult.get()
    }

    func requestDeviceCode() async throws -> DeviceCodeInfo {
        try requestDeviceCodeResult.get()
    }

    func pollForMSAToken(deviceCode _: String, interval _: Int) async throws -> String {
        try pollForMSATokenResult.get()
    }

    func exchangeForStreamTokens(msaAccessToken _: String) async throws -> StreamTokens {
        try exchangeResult.get()
    }

    func fetchLPTForCloudConnect() async throws -> String {
        fetchLPTCallCount += 1
        return try fetchLPTResult.get()
    }

    func signOut() async {
        signOutCallCount += 1
    }
}

private enum StubError: LocalizedError {
    case expected

    var errorDescription: String? {
        "Expected stub failure"
    }
}
