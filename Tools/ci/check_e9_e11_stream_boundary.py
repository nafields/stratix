#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, assert_contains, assert_not_contains, fail

errors: list[str] = []

required_paths = [
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamState.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamAction.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamReducer.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamOverlayController.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamOverlayVisibilityCoordinator.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamLaunchConfigurationService.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamHeroArtworkService.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamAchievementRefreshCoordinator.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamReconnectCoordinator.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamReconnectPolicy.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamOfferProfilePolicy.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamRegionSelectionPolicy.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamHomeLaunchWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamCloudLaunchWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamStopWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamRuntimeAttachmentService.swift"),
]
errors.extend(require_paths(required_paths))

stream_controller = rel("Packages/StratixCore/Sources/StratixCore/StreamController.swift")
stream_state = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamState.swift")
stream_action = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamAction.swift")
stream_reducer = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamReducer.swift")
home_launch = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamHomeLaunchWorkflow.swift")
cloud_launch = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamCloudLaunchWorkflow.swift")

errors.extend(assert_contains(stream_controller, [
    "public private(set) var state: StreamState",
    "private let overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator",
    "private let runtimeAttachmentService: StreamRuntimeAttachmentService",
    "private let priorityModeCoordinator: StreamPriorityModeCoordinator",
    "private let launchWorkflow: StreamLaunchWorkflow",
    "private let stopStreamWorkflow: StreamStopWorkflow",
    "private let streamReconnectCoordinator: StreamReconnectCoordinator",
    "private func makeLaunchEnvironment() -> StreamLaunchEnvironment?",
    "private func makeHeroArtworkEnvironment() -> StreamHeroArtworkEnvironment?",
    "private func makeAchievementLoadEnvironment(",
    "private func makeOverlayEnvironment(",
    "private func makeRuntimeAttachmentEnvironment() -> StreamRuntimeAttachmentEnvironment",
    "private func makePriorityModeEnvironment() -> StreamPriorityModeEnvironment",
    "await launchWorkflow.startHome(",
    "await launchWorkflow.startCloud(",
    "await stopStreamWorkflow.stop(",
    "await priorityModeCoordinator.enter(",
    "await priorityModeCoordinator.exit(",
    "await streamReconnectCoordinator.handleLifecycleChange(",
    "let actions = await overlayVisibilityCoordinator.setVisibility(",
]))

errors.extend(assert_not_contains(stream_controller, [
    "resolvedHomeLaunchConfiguration(",
    "resolvedCloudLaunchConfiguration(",
    "resolveLaunchHeroURL(",
    "loadAchievements(",
    "startPeriodicRefresh(",
    "scheduleReconnectIfNeeded(",
    "decision(",
    "resolvedCloudOfferProfile(",
    "effectiveSelection(",
    "XCloudAPIClient(",
    "await session.connect(",
    "state.streamingSession?.disconnect(",
    "StreamControllerEnvironmentFactory",
]))

errors.extend(assert_contains(stream_state, [
    "public var isReconnecting: Bool",
    "public var sessionAttachmentState: StreamSessionAttachmentState",
    "public var activeLaunchTarget: StreamLaunchTarget?",
    "public var reconnectAttemptCount: Int",
    "public var streamingSession: (any StreamingSessionFacade)?",
]))

errors.extend(assert_contains(stream_action, [
    "case reconnectScheduled(attempt: Int, trigger: StreamReconnectTrigger)",
    "case overlayVisibilityChanged(Bool, trigger: StreamOverlayTrigger)",
    "case activeLaunchTargetSet(StreamLaunchTarget?)",
    "case streamDisconnected(StreamingDisconnectIntent)",
]))

errors.extend(assert_contains(stream_reducer, [
    "case .reconnectScheduled(let attempt, let trigger):",
    "case .overlayVisibilityChanged(let visible, _):",
    "case .activeLaunchTargetSet(let target):",
    "case .streamDisconnected(let intent):",
]))

errors.extend(assert_contains(home_launch, [
    "launchConfigurationService: StreamLaunchConfigurationService",
    "overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator",
    "runtimeAttachmentService: StreamRuntimeAttachmentService",
    "priorityModeCoordinator: StreamPriorityModeCoordinator",
]))

errors.extend(assert_contains(cloud_launch, [
    "launchConfigurationService: StreamLaunchConfigurationService",
    "overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator",
    "runtimeAttachmentService: StreamRuntimeAttachmentService",
    "priorityModeCoordinator: StreamPriorityModeCoordinator",
]))

legacy_guard = rel("Tools/ci/check_stage5_stream_split.py")
if legacy_guard.exists():
    errors.append(f"{legacy_guard}: duplicate weaker Stage 5 guard must not remain.")

fail(errors)
print("Stage 5 stream boundary guard passed.")
