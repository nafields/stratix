// ConsoleController.swift
// Defines the console controller.
//

import DiagnosticsKit
import Foundation
import StratixModels
import Observation
import StreamingCore
import XCloudAPI

@MainActor
@Observable
public final class ConsoleController {
    public private(set) var consoles: [RemoteConsole] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    private enum TaskID {
        static let refresh = "refresh"
    }

    let taskRegistry = TaskRegistry()
    private weak var dependencies: (any ConsoleControllerDependencies)?
    private let refreshWorkflow: (@MainActor (ConsoleController, StreamTokens) async throws -> [RemoteConsole])?
    private let logger = GLogger(category: .auth)
    private var isSuspendedForStreaming = false

    init(
        refreshWorkflow: (@MainActor (ConsoleController, StreamTokens) async throws -> [RemoteConsole])? = nil
    ) {
        self.refreshWorkflow = refreshWorkflow
    }

    func attach(_ dependencies: any ConsoleControllerDependencies) {
        self.dependencies = dependencies
    }

    public func refresh() async {
        guard !isSuspendedForStreaming else { return }
        let (task, inserted) = await taskRegistry.taskOrRegister(id: TaskID.refresh) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performRefresh()
            }
        }
        await task.value
        if inserted {
            await taskRegistry.remove(id: TaskID.refresh)
        }
    }

    func setConsoles(_ consoles: [RemoteConsole]) {
        self.consoles = consoles
    }

    func setIsLoading(_ isLoading: Bool) {
        self.isLoading = isLoading
    }

    func setLastError(_ message: String?) {
        lastError = message
    }

    func suspendForStreaming() async {
        isSuspendedForStreaming = true
        isLoading = false
        await taskRegistry.cancel(id: TaskID.refresh)
    }

    func resumeAfterStreaming() {
        isSuspendedForStreaming = false
    }

    func resetForSignOut() {
        isSuspendedForStreaming = false
        consoles = []
        isLoading = false
        lastError = nil
    }

    private func performRefresh() async {
        guard !isSuspendedForStreaming else { return }
        guard let tokens = dependencies?.authenticatedConsoleTokens() else { return }
        guard !isSuspendedForStreaming else { return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let loaded: [RemoteConsole]
            guard !isSuspendedForStreaming else { return }
            if let refreshWorkflow {
                loaded = try await refreshWorkflow(self, tokens)
            } else {
                let client = XCloudAPIClient(baseHost: tokens.xhomeHost, gsToken: tokens.xhomeToken)
                let response = try await client.getConsoles()
                loaded = response.results
            }
            guard !isSuspendedForStreaming else { return }
            consoles = loaded
        } catch is CancellationError {
            return
        } catch {
            let message = error.localizedDescription
            lastError = message
            logger.error("Failed to load consoles: \(message)")
        }
    }
}
