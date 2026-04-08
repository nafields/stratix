// StreamController.swift
// Defines the stream controller.
//

import Foundation
import Observation
import StratixModels
import StreamingCore
import XCloudAPI
import DiagnosticsKit

// MARK: - StreamController

@Observable
@MainActor
public final class StreamController {
    public private(set) var state: StreamState

    public var isReconnecting: Bool { state.isReconnecting }
    public var streamingSession: (any StreamingSessionFacade)? { state.streamingSession }
    public var isStreamOverlayVisible: Bool { state.isStreamOverlayVisible }
    public var currentStreamAchievementSnapshot: TitleAchievementSnapshot? { state.currentStreamAchievementSnapshot }
    public var lastStreamAchievementError: String? { state.lastStreamAchievementError }
    public var launchHeroURL: URL? { state.launchHeroURL }
    public var runtimePhase: StreamRuntimePhase { state.runtimePhase }
    public var shellRestoredAfterStreamExit: Bool { state.shellRestoredAfterStreamExit }
    public var activeRuntimeContext: StreamRuntimeContext? { state.activeRuntimeContext }

    public var isStreamPriorityModeActive: Bool {
        state.runtimePhase != .shellActive
    }

    @ObservationIgnored let taskRegistry = TaskRegistry()
    @ObservationIgnored private weak var dependencies: (any StreamControllerDependencies)?
    @ObservationIgnored private let logger = GLogger(category: .auth)

    @ObservationIgnored private let overlayController: StreamOverlayController
    @ObservationIgnored private let regionDiagnosticsResolver: StreamRegionDiagnosticsResolver
    @ObservationIgnored private let overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator
    @ObservationIgnored private let runtimeAttachmentService: StreamRuntimeAttachmentService
    @ObservationIgnored private let priorityModeCoordinator: StreamPriorityModeCoordinator
    @ObservationIgnored private let launchWorkflow: StreamLaunchWorkflow
    @ObservationIgnored private let stopStreamWorkflow: StreamStopWorkflow
    @ObservationIgnored private let streamReconnectCoordinator: StreamReconnectCoordinator

    @ObservationIgnored private let startHomeWorkflow: (@MainActor (RemoteConsole, any WebRTCBridge) async -> Void)?
    @ObservationIgnored private let startCloudWorkflow: (@MainActor (TitleID, any WebRTCBridge) async -> Void)?
    @ObservationIgnored private let stopWorkflow: (@MainActor () async -> Void)?
    @ObservationIgnored private let overlayVisibilityWorkflow: (@MainActor (Bool) -> Void)?

    init(
        startHomeWorkflow: (@MainActor (RemoteConsole, any WebRTCBridge) async -> Void)? = nil,
        startCloudWorkflow: (@MainActor (TitleID, any WebRTCBridge) async -> Void)? = nil,
        stopWorkflow: (@MainActor () async -> Void)? = nil,
        overlayVisibilityWorkflow: (@MainActor (Bool) -> Void)? = nil,
        overlayController: StreamOverlayController = StreamOverlayController(),
        overlayInputPolicy: StreamOverlayInputPolicy = StreamOverlayInputPolicy(),
        achievementRefreshCoordinator: StreamAchievementRefreshCoordinator = StreamAchievementRefreshCoordinator(),
        heroArtworkService: StreamHeroArtworkService = StreamHeroArtworkService(),
        launchConfigurationService: StreamLaunchConfigurationService = StreamLaunchConfigurationService(),
        reconnectCoordinator: StreamReconnectCoordinator = StreamReconnectCoordinator(),
        streamSessionLifecycleObserver: StreamSessionLifecycleObserver = StreamSessionLifecycleObserver(),
        regionDiagnosticsResolver: StreamRegionDiagnosticsResolver? = nil,
        initialState: StreamState = .empty
    ) {
        self.startHomeWorkflow = startHomeWorkflow
        self.startCloudWorkflow = startCloudWorkflow
        self.stopWorkflow = stopWorkflow
        self.overlayVisibilityWorkflow = overlayVisibilityWorkflow
        self.overlayController = overlayController
        let regionDiagnosticsResolver = regionDiagnosticsResolver ?? StreamRegionDiagnosticsResolver(
            launchConfigurationService: launchConfigurationService
        )
        let overlayVisibilityCoordinator = StreamOverlayVisibilityCoordinator(
            overlayInputPolicy: overlayInputPolicy,
            achievementRefreshCoordinator: achievementRefreshCoordinator,
            heroArtworkService: heroArtworkService
        )
        let runtimeAttachmentService = StreamRuntimeAttachmentService(
            lifecycleObserver: streamSessionLifecycleObserver
        )
        let priorityModeCoordinator = StreamPriorityModeCoordinator()
        self.regionDiagnosticsResolver = regionDiagnosticsResolver
        self.overlayVisibilityCoordinator = overlayVisibilityCoordinator
        self.runtimeAttachmentService = runtimeAttachmentService
        self.priorityModeCoordinator = priorityModeCoordinator
        let homeLaunchWorkflow = StreamHomeLaunchWorkflow(
            launchConfigurationService: launchConfigurationService,
            overlayVisibilityCoordinator: overlayVisibilityCoordinator,
            runtimeAttachmentService: runtimeAttachmentService,
            priorityModeCoordinator: priorityModeCoordinator
        )
        let cloudLaunchWorkflow = StreamCloudLaunchWorkflow(
            launchConfigurationService: launchConfigurationService,
            overlayVisibilityCoordinator: overlayVisibilityCoordinator,
            runtimeAttachmentService: runtimeAttachmentService,
            priorityModeCoordinator: priorityModeCoordinator
        )
        self.launchWorkflow = StreamLaunchWorkflow(
            homeLaunchWorkflow: homeLaunchWorkflow,
            cloudLaunchWorkflow: cloudLaunchWorkflow
        )
        self.stopStreamWorkflow = StreamStopWorkflow(
            overlayVisibilityCoordinator: overlayVisibilityCoordinator,
            runtimeAttachmentService: runtimeAttachmentService,
            priorityModeCoordinator: priorityModeCoordinator
        )
        self.streamReconnectCoordinator = reconnectCoordinator
        self.state = initialState
    }

    func attach(_ dependencies: any StreamControllerDependencies) {
        self.dependencies = dependencies
    }

    func apply(_ action: StreamAction) {
        state = StreamReducer.reduce(state: state, action: action)
    }

    func apply(_ actions: [StreamAction]) {
        for action in actions {
            state = StreamReducer.reduce(state: state, action: action)
        }
    }

    public func startHomeStream(console: RemoteConsole, bridge: any WebRTCBridge) async {
        if let startHomeWorkflow {
            await startHomeWorkflow(console, bridge)
        } else {
            await performStartHomeStream(console: console, bridge: bridge)
        }
    }

    public func startCloudStream(titleId: TitleID, bridge: any WebRTCBridge) async {
        if let startCloudWorkflow {
            await startCloudWorkflow(titleId, bridge)
        } else {
            await performStartCloudStream(titleId: titleId, bridge: bridge)
        }
    }

    public func stopStreaming() async {
        if let stopWorkflow {
            await stopWorkflow()
        } else {
            await performStopStreaming()
        }
    }

    public func setOverlayVisible(_ visible: Bool) async {
        await setOverlayVisible(visible, trigger: .automatic)
    }

    public func setOverlayVisible(_ visible: Bool, trigger: StreamOverlayTrigger) async {
        if let overlayVisibilityWorkflow {
            overlayVisibilityWorkflow(visible)
        } else {
            await performSetOverlayVisible(visible, trigger: trigger)
        }
    }

    public func enterStreamPriorityMode(context: StreamRuntimeContext) async {
        await priorityModeCoordinator.enter(
            context: context,
            state: state,
            environment: makePriorityModeEnvironment(),
            publish: { [weak self] actions in
                self?.apply(actions)
            }
        )
    }

    public func exitStreamPriorityMode() async {
        await priorityModeCoordinator.exit(
            state: state,
            environment: makePriorityModeEnvironment(),
            publish: { [weak self] actions in
                self?.apply(actions)
            }
        )
    }

    public func requestOverlayToggle() {
        overlayController.requestOverlayToggle()
    }

    public func requestDisconnect() {
        overlayController.requestDisconnect()
    }

    public func toggleStatsHUD() {
        overlayController.toggleStatsHUD()
    }

    public func makeCommandStream() -> AsyncStream<StreamUICommand> {
        overlayController.makeCommandStream()
    }

    public func regionOverrideDiagnostics(for rawValue: String) -> String? {
        regionDiagnosticsResolver.regionOverrideDiagnostics(
            rawValue: rawValue,
            availableRegions: dependencies?.sessionController.xcloudRegions ?? []
        )
    }

    func resetForSignOut() async {
        await overlayVisibilityCoordinator.stopPresentationRefresh()
        await streamReconnectCoordinator.reset()
        overlayController.reset()
        runtimeAttachmentService.reset(
            environment: makeRuntimeAttachmentEnvironment()
        )
        apply([
            .reconnectStateReset,
            .signedOutReset
        ])
    }

    func performStartHomeStream(console: RemoteConsole, bridge: any WebRTCBridge) async {
        guard let dependencies,
              let launchEnvironment = makeLaunchEnvironment(),
              case .authenticated(let tokens) = dependencies.sessionController.authState else { return }
        await launchWorkflow.startHome(
            console: console,
            bridge: bridge,
            state: { [weak self] in self?.state ?? .empty },
            reconnectCoordinator: streamReconnectCoordinator,
            environment: StreamHomeLaunchWorkflowEnvironment(
                launchEnvironment: launchEnvironment,
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: makePriorityModeEnvironment(),
                logger: logger,
                tokens: tokens,
                updateControllerSettings: { [weak dependencies] in dependencies?.updateControllerSettings() },
                prepareVideoCapabilities: { [weak dependencies] in dependencies?.prepareStreamVideoCapabilitiesIfNeeded() },
                apiSession: dependencies.apiSession(),
                publish: { [weak self] actions in self?.apply(actions) },
                onLifecycleChange: { [weak self] event in
                    Task { @MainActor in
                        await self?.handleLifecycleEvent(event)
                    }
                }
            )
        )
    }

    func performStartCloudStream(titleId: TitleID, bridge: any WebRTCBridge) async {
        guard let dependencies,
              let launchEnvironment = makeLaunchEnvironment(),
              case .authenticated = dependencies.sessionController.authState else {
            logger.error("No xCloud token available")
            return
        }
        await launchWorkflow.startCloud(
            titleId: titleId,
            bridge: bridge,
            state: { [weak self] in self?.state ?? .empty },
            reconnectCoordinator: streamReconnectCoordinator,
            environment: StreamCloudLaunchWorkflowEnvironment(
                launchEnvironment: launchEnvironment,
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: makePriorityModeEnvironment(),
                overlayEnvironment: makeOverlayEnvironment(
                    activeTitleProvider: { [weak self] in
                        self?.state.activeLaunchTarget?.titleId
                    },
                    shouldContinuePresentationRefresh: { [weak self] in
                        guard let self else { return false }
                        return self.state.isStreamOverlayVisible && self.state.streamingSession != nil
                    },
                    publish: { [weak self] actions in
                        self?.apply(actions)
                    }
                ),
                logger: logger,
                updateControllerSettings: { [weak dependencies] in dependencies?.updateControllerSettings() },
                prepareVideoCapabilities: { [weak dependencies] in dependencies?.prepareStreamVideoCapabilitiesIfNeeded() },
                cloudConnectAuth: { [weak dependencies] in
                    guard let dependencies else { throw APIError.decodingError("Missing stream dependencies") }
                    return try await dependencies.sessionController.cloudConnectAuth(logContext: "cloud stream start")
                },
                setLastAuthError: { [weak dependencies] message in
                    dependencies?.sessionController.setLastAuthError(message)
                },
                cachedHeroURL: { [weak dependencies] requestedTitleId in
                    dependencies?.libraryController.item(titleID: requestedTitleId)?.heroImageURL
                        ?? dependencies?.libraryController.item(titleID: requestedTitleId)?.posterImageURL
                        ?? dependencies?.libraryController.item(titleID: requestedTitleId)?.artURL
                },
                apiSession: dependencies.apiSession(),
                publish: { [weak self] actions in self?.apply(actions) },
                onLifecycleChange: { [weak self] event in
                    Task { @MainActor in
                        await self?.handleLifecycleEvent(event)
                    }
                }
            )
        )
    }

    func performStopStreaming() async {
        await stopStreamWorkflow.stop(
            state: state,
            reconnectCoordinator: streamReconnectCoordinator,
            environment: StreamStopWorkflowEnvironment(
                runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
                priorityModeEnvironment: makePriorityModeEnvironment(),
                publish: { [weak self] actions in self?.apply(actions) }
            )
        )
    }

    func performSetOverlayVisible(_ visible: Bool, trigger: StreamOverlayTrigger) async {
        let actions = await overlayVisibilityCoordinator.setVisibility(
            visible,
            trigger: trigger,
            state: state,
            environment: makeOverlayEnvironment(
                activeTitleProvider: { [weak self] in
                    self?.state.activeLaunchTarget?.titleId
                },
                shouldContinuePresentationRefresh: { [weak self] in
                    guard let self else { return false }
                    return self.state.isStreamOverlayVisible && self.state.streamingSession != nil
                },
                publish: { [weak self] actions in
                    self?.apply(actions)
                }
            )
        )
        apply(actions)
        logger.info("Stream overlay visible: \(visible)")
    }

#if DEBUG
    func testingSetIsStartingStream(_ value: Bool) {
        // The launch-in-progress guard moved into StreamLaunchWorkflow.
        if value {
            apply(.runtimePhaseSet(.preparingStream))
        } else {
            apply(.runtimePhaseSet(.shellActive))
        }
    }
#endif

    private func handleLifecycleEvent(_ event: StreamSessionLifecycleEvent) async {
        await streamReconnectCoordinator.handleLifecycleChange(
            event: event,
            environment: StreamReconnectEnvironment(
                autoReconnectEnabled: dependencies?.settingsStore.stream.autoReconnect ?? false,
                launcher: StreamReconnectLauncher(
                    disconnectCurrentSession: { [weak self] in
                        guard let self else { return }
                        await self.runtimeAttachmentService.disconnect(
                            session: self.state.streamingSession,
                            reason: .reconnectTransition
                        )
                        self.apply(
                            self.runtimeAttachmentService.detach(
                                environment: self.makeRuntimeAttachmentEnvironment()
                            )
                        )
                    },
                    relaunch: { [weak self] target, bridge in
                        guard let self else { return }
                        switch target {
                        case .cloud(let titleId):
                            await self.performStartCloudStream(titleId: titleId, bridge: bridge)
                        case .home(let consoleId):
                            guard
                                let console = self.dependencies?.consoleController.consoles.first(where: { $0.serverId == consoleId })
                            else { return }
                            await self.performStartHomeStream(console: console, bridge: bridge)
                        }
                    }
                ),
                publish: { [weak self] actions in
                    self?.apply(actions)
                }
            )
        )
    }

    private func makeLaunchEnvironment() -> StreamLaunchEnvironment? {
        guard let dependencies else { return nil }
        return StreamLaunchEnvironment(
            streamSettings: dependencies.settingsStore.stream,
            diagnosticsSettings: dependencies.settingsStore.diagnostics,
            controllerSettings: dependencies.settingsStore.controller,
            availableRegions: dependencies.sessionController.xcloudRegions
        )
    }

    private func makeHeroArtworkEnvironment() -> StreamHeroArtworkEnvironment? {
        guard let dependencies else { return nil }
        return StreamHeroArtworkEnvironment(
            cachedItem: { requestedTitleId in
                await MainActor.run {
                    dependencies.libraryController.item(titleID: requestedTitleId)
                }
            },
            xboxWebCredentials: { logContext in
                await dependencies.sessionController.xboxWebCredentials(logContext: logContext)
            },
            urlSession: dependencies.apiSession(),
            fetchProductDetails: { productId, credentials, session in
                try await XboxComProductDetailsClient(
                    credentials: credentials,
                    session: session
                ).getProductDetails(productId: productId)
            }
        )
    }

    private func makeAchievementLoadEnvironment(
        activeTitleProvider: @escaping @MainActor () -> TitleID?
    ) -> StreamAchievementLoadEnvironment? {
        guard let dependencies else { return nil }
        return StreamAchievementLoadEnvironment(
            activeTitleId: {
                await activeTitleProvider()
            },
            loadSnapshot: { requestedTitleId, forceRefresh in
                await dependencies.achievementsController.loadTitleAchievements(
                    titleID: requestedTitleId,
                    forceRefresh: forceRefresh
                )
                return await MainActor.run {
                    dependencies.achievementsController.titleAchievementSnapshot(titleID: requestedTitleId)
                }
            },
            loadError: { requestedTitleId in
                await MainActor.run {
                    dependencies.achievementsController.lastTitleAchievementsError(titleID: requestedTitleId)
                }
            }
        )
    }

    private func makeOverlayEnvironment(
        activeTitleProvider: @escaping @MainActor () -> TitleID?,
        shouldContinuePresentationRefresh: @escaping @MainActor () -> Bool,
        publish: @escaping @MainActor ([StreamAction]) -> Void
    ) -> StreamOverlayEnvironment {
        StreamOverlayEnvironment(
            heroArtworkEnvironment: makeHeroArtworkEnvironment(),
            achievementEnvironment: makeAchievementLoadEnvironment(activeTitleProvider: activeTitleProvider),
            shouldContinuePresentationRefresh: {
                await shouldContinuePresentationRefresh()
            },
            publishRefreshResult: publish,
            injectNeutralFrame: { [weak self] in
                self?.dependencies?.inputController.injectNeutralGamepadFrame()
            },
            injectPauseMenuTap: { [weak self] in
                self?.dependencies?.inputController.injectPauseMenuTap()
            }
        )
    }

    private func makeRuntimeAttachmentEnvironment() -> StreamRuntimeAttachmentEnvironment {
        StreamRuntimeAttachmentEnvironment(
            input: StreamRuntimeInputEnvironment(
                setupControllerObservation: { [weak self] inputQueue in
                    self?.dependencies?.inputController.setupControllerObservation(inputQueue: inputQueue)
                },
                clearStreamingInputBindings: { [weak self] in
                    self?.dependencies?.inputController.clearStreamingInputBindings()
                },
                routeVibration: { [weak self] report in
                    guard let self, let dependencies = self.dependencies else { return }
                    dependencies.inputController.routeVibration(
                        report,
                        settingsStore: dependencies.settingsStore
                    )
                }
            )
        )
    }

    private func makePriorityModeEnvironment() -> StreamPriorityModeEnvironment {
        StreamPriorityModeEnvironment(
            enterPriorityMode: { [weak self] in
                await self?.dependencies?.enterStreamPriorityMode()
            },
            exitPriorityMode: { [weak self] in
                await self?.dependencies?.exitStreamPriorityMode()
            }
        )
    }
}
