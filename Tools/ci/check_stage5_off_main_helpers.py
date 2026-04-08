#!/usr/bin/env python3
from __future__ import annotations

import re

from common import rel, assert_contains, assert_not_contains, fail, read_text

errors: list[str] = []

hero_service = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamHeroArtworkService.swift")
achievement_coordinator = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamAchievementRefreshCoordinator.swift")
overlay_coordinator = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamOverlayVisibilityCoordinator.swift")
reconnect_coordinator = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamReconnectCoordinator.swift")
home_workflow = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamHomeLaunchWorkflow.swift")
cloud_workflow = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamCloudLaunchWorkflow.swift")
launch_workflow = rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamLaunchWorkflow.swift")

errors.extend(assert_contains(hero_service, [
    "struct StreamHeroArtworkEnvironment: Sendable",
    "let cachedItem: @Sendable (TitleID) async -> CloudLibraryItem?",
    "let xboxWebCredentials: @Sendable (String) async -> XboxWebCredentials?",
    "let urlSession: URLSession",
]))
errors.extend(assert_contains(achievement_coordinator, [
    "actor StreamAchievementRefreshCoordinator",
    "activeTitleProvider: @escaping @Sendable () async -> TitleID?",
    "shouldContinue: @escaping @Sendable () async -> Bool",
    "refresh: @escaping @Sendable () async -> Void",
]))
errors.extend(assert_contains(overlay_coordinator, [
    "actor StreamOverlayVisibilityCoordinator",
    "struct StreamAchievementLoadEnvironment: Sendable",
    "let activeTitleId: @Sendable () async -> TitleID?",
    "let shouldContinuePresentationRefresh: @Sendable () async -> Bool",
]))
errors.extend(assert_contains(reconnect_coordinator, [
    "actor StreamReconnectCoordinator",
    "struct StreamReconnectEnvironment: Sendable",
    "let disconnectCurrentSession: @Sendable @MainActor () async -> Void",
    "let relaunch: @Sendable @MainActor (StreamLaunchTarget, any WebRTCBridge) async -> Void",
]))
errors.extend(assert_contains(home_workflow, [
    "final class StreamHomeLaunchWorkflow {",
    "typealias SessionFactory = @Sendable (XCloudAPIClient, any WebRTCBridge, StreamingConfig, StreamPreferences) async -> any StreamingSessionFacade",
    "typealias HomeConnect = @Sendable (any StreamingSessionFacade, String) async -> Void",
]))
errors.extend(assert_contains(cloud_workflow, [
    "final class StreamCloudLaunchWorkflow {",
    "typealias SessionFactory = @Sendable (XCloudAPIClient, any WebRTCBridge, StreamingConfig, StreamPreferences) async -> any StreamingSessionFacade",
    "typealias CloudConnect = @Sendable (any StreamingSessionFacade, String, String) async -> Void",
]))
errors.extend(assert_contains(launch_workflow, [
    "private actor StreamLaunchStartGate",
    "final class StreamLaunchWorkflow {",
]))

for path in [
    hero_service,
    achievement_coordinator,
    overlay_coordinator,
    reconnect_coordinator,
    home_workflow,
    cloud_workflow,
    launch_workflow,
]:
    text = read_text(path)
    if re.search(r"@MainActor\s+(final\s+class|actor|struct)\s+", text):
        errors.append(f"{path}: extracted Stage 5 helper regained type-level @MainActor isolation")

errors.extend(assert_not_contains(home_workflow, ["Task { @MainActor"]))
errors.extend(assert_not_contains(cloud_workflow, ["Task { @MainActor"]))
errors.extend(assert_not_contains(reconnect_coordinator, ["Task { @MainActor"]))
errors.extend(assert_not_contains(overlay_coordinator, ["Task { @MainActor"]))
errors.extend(assert_not_contains(achievement_coordinator, ["Task { @MainActor"]))
errors.extend(assert_not_contains(hero_service, ["Task { @MainActor"]))

fail(errors)
print("Stage 5 off-main helper guard passed.")
