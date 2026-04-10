// StreamTestSupport.swift
// Provides shared support for the StratixCore / StratixCoreTests surface.
//

import Foundation
@testable import StratixCore
import StratixModels
import InputBridge
import StreamingCore
import XCloudAPI

@MainActor
func makeStreamingSession() -> StreamingSession {
    StreamingSession(
        apiClient: XCloudAPIClient(baseHost: "example.com", gsToken: "test"),
        bridge: TestWebRTCBridge()
    )
}

func makeTitleID(_ rawValue: String = "1234") -> TitleID {
    TitleID(rawValue)
}

@MainActor
func makeRemoteConsole(serverId: String = "console-1") -> RemoteConsole {
    try! JSONDecoder().decode(
        RemoteConsole.self,
        from: Data("""
        {
          "deviceName": "Xbox",
          "serverId": "\(serverId)",
          "powerState": "ConnectedStandby",
          "consoleType": "XboxSeriesX",
          "playPath": "/play",
          "outOfHomeWarning": false,
          "wirelessWarning": false,
          "isDevKit": false
        }
        """.utf8)
    )
}

func makeStreamLaunchEnvironment(
    streamSettings: SettingsStore.StreamSettings = SettingsStore.StreamSettings(),
    diagnosticsSettings: SettingsStore.DiagnosticsSettings = SettingsStore.DiagnosticsSettings(),
    controllerSettings: SettingsStore.ControllerSettings = SettingsStore.ControllerSettings(),
    availableRegions: [LoginRegion] = []
) -> StreamLaunchEnvironment {
    StreamLaunchEnvironment(
        streamSettings: streamSettings,
        diagnosticsSettings: diagnosticsSettings,
        controllerSettings: controllerSettings,
        availableRegions: availableRegions
    )
}

func makeHeroArtworkEnvironment(
    cachedItem: @escaping @Sendable (TitleID) async -> CloudLibraryItem? = { _ in nil },
    xboxWebCredentials: @escaping @Sendable (String) async -> XboxWebCredentials? = { _ in nil },
    urlSession: URLSession = .shared,
    fetchProductDetails: @escaping @Sendable (String, XboxWebCredentials, URLSession) async throws -> XboxComProductDetails = { productId, credentials, session in
        try await XboxComProductDetailsClient(
            credentials: credentials,
            session: session
        ).getProductDetails(productId: productId)
    }
) -> StreamHeroArtworkEnvironment {
    StreamHeroArtworkEnvironment(
        cachedItem: cachedItem,
        xboxWebCredentials: xboxWebCredentials,
        urlSession: urlSession,
        fetchProductDetails: fetchProductDetails
    )
}

func makeRuntimeAttachmentEnvironment(
    setupControllerObservation: @escaping @MainActor (any StreamingSessionFacade) -> Void = { _ in },
    clearStreamingInputBindings: @escaping @MainActor () -> Void = {},
    routeVibration: @escaping @MainActor (VibrationReport) -> Void = { _ in }
) -> StreamRuntimeAttachmentEnvironment {
    StreamRuntimeAttachmentEnvironment(
        input: StreamRuntimeInputEnvironment(
            setupControllerObservation: setupControllerObservation,
            clearStreamingInputBindings: clearStreamingInputBindings,
            routeVibration: routeVibration
        )
    )
}

actor ArrayRecorder<Element: Sendable> {
    private var values: [Element] = []

    func append(_ value: Element) {
        values.append(value)
    }

    func append(contentsOf newValues: [Element]) {
        values.append(contentsOf: newValues)
    }

    func snapshot() -> [Element] {
        values
    }
}

final class TestWebRTCBridge: WebRTCBridge, @unchecked Sendable {
    var delegate: WebRTCBridgeDelegate?

    func createOffer() async -> SessionDescription {
        fatalError("not used")
    }

    func applyH264CodecPreferences() {}

    func setLocalDescription(_ _: SessionDescription) async {}

    func setRemoteDescription(_ _: SessionDescription) async {}

    func addRemoteIceCandidate(_ _: IceCandidatePayload) async {}

    var localIceCandidates: [IceCandidatePayload] {
        get async { [] }
    }

    var connectionState: PeerConnectionState {
        get async { .connected }
    }

    func send(channelKind _: DataChannelKind, data _: Data) async {}

    func sendString(channelKind _: DataChannelKind, text _: String) async {}

    func dataChannelRuntimeStats(channelKind: DataChannelKind) -> DataChannelRuntimeStats? {
        nil
    }

    func close() async {}

    func collectStats() async -> StreamingStatsSnapshot {
        StreamingStatsSnapshot()
    }
}
