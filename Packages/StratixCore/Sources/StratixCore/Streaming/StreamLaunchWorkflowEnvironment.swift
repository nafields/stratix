// StreamLaunchWorkflowEnvironment.swift
// Defines stream launch workflow environment for the Streaming surface.
//

import Foundation
import StratixModels
import StreamingCore
import XCloudAPI
import DiagnosticsKit

struct StreamHomeLaunchWorkflowEnvironment {
    let launchEnvironment: StreamLaunchEnvironment
    let runtimeAttachmentEnvironment: StreamRuntimeAttachmentEnvironment
    let priorityModeEnvironment: StreamPriorityModeEnvironment
    let logger: GLogger
    let tokens: StreamTokens
    let updateControllerSettings: @Sendable @MainActor () -> Void
    let prepareVideoCapabilities: @Sendable @MainActor () -> Void
    let apiSession: URLSession
    let publish: @Sendable @MainActor ([StreamAction]) -> Void
    let onLifecycleChange: @Sendable @MainActor (StreamSessionLifecycleEvent) -> Void
}

struct StreamCloudLaunchWorkflowEnvironment {
    let launchEnvironment: StreamLaunchEnvironment
    let runtimeAttachmentEnvironment: StreamRuntimeAttachmentEnvironment
    let priorityModeEnvironment: StreamPriorityModeEnvironment
    let overlayEnvironment: StreamOverlayEnvironment
    let logger: GLogger
    let updateControllerSettings: @Sendable @MainActor () -> Void
    let prepareVideoCapabilities: @Sendable @MainActor () -> Void
    let cloudConnectAuth: @Sendable () async throws -> SessionController.CloudConnectAuth
    let setLastAuthError: @Sendable @MainActor (String) -> Void
    let cachedHeroURL: @Sendable @MainActor (TitleID) -> URL?
    let apiSession: URLSession
    let publish: @Sendable @MainActor ([StreamAction]) -> Void
    let onLifecycleChange: @Sendable @MainActor (StreamSessionLifecycleEvent) -> Void
}
