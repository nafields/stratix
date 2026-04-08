// ShellBootstrapController.swift
// Defines the shell bootstrap controller.
//

import DiagnosticsKit
import Foundation
import Observation

@Observable
@MainActor
public final class ShellBootstrapController {

    public enum BootstrapPhase: Equatable, Sendable {
        case idle
        case hydrating(statusText: String?, deferRoutePublication: Bool)
        case ready
    }

    public private(set) var phase: BootstrapPhase = .idle

    public var initialHydrationInProgress: Bool {
        if case .hydrating = phase { return true }
        return false
    }

    public var initialRoutePublicationDeferred: Bool {
        if case .hydrating(_, let deferred) = phase { return deferred }
        return false
    }

    public var isLoading: Bool { initialHydrationInProgress }

    public var statusText: String? {
        if case .hydrating(let text, _) = phase { return text }
        return nil
    }

    private enum TaskID {
        static let hydration = "shell.hydration"
    }

    let taskRegistry = TaskRegistry()
    private let logger = GLogger(category: .auth)
    private var isSuspendedForStreaming = false

    init() {}

    func setIsLoading(_ value: Bool) {
        if value {
            phase = .hydrating(statusText: statusText, deferRoutePublication: initialRoutePublicationDeferred)
        } else {
            phase = .ready
        }
    }

    func setStatusText(_ value: String?) {
        if case .hydrating(_, let deferred) = phase {
            phase = .hydrating(statusText: value, deferRoutePublication: deferred)
        }
    }

    func suspendForStreaming() async {
        isSuspendedForStreaming = true
        phase = .idle
        await taskRegistry.cancel(id: TaskID.hydration)
    }

    func resumeAfterStreaming() {
        isSuspendedForStreaming = false
    }

    func resetForSignOut() async {
        isSuspendedForStreaming = false
        phase = .idle
        await taskRegistry.cancel(id: TaskID.hydration)
    }

    func beginHydrationIfNeeded(
        plan: ShellBootHydrationPlan?,
        refreshAction: @escaping @MainActor (_ deferInitialRoutePublication: Bool) async -> Void,
        prefetchAction: @escaping @MainActor () async -> Void
    ) async {
        guard let plan else { return }
        guard !isSuspendedForStreaming else { return }

        logger.info(
            "Shell boot hydration decision: mode=\(String(describing: plan.mode)) decision=\(plan.decisionDescription)"
        )

        phase = .hydrating(
            statusText: plan.statusText,
            deferRoutePublication: plan.deferInitialRoutePublication
        )

        let registry = taskRegistry
        let (_, inserted) = await taskRegistry.taskOrRegister(id: TaskID.hydration) {
            Task { @MainActor [weak self, registry] in
                if let self {
                    let startedAt = Date()

                    if !Task.isCancelled, !self.isSuspendedForStreaming {
                        switch plan.mode {
                        case .refreshNetwork:
                            await refreshAction(plan.deferInitialRoutePublication)
                        case .prefetchCached:
                            await prefetchAction()
                        }
                    }

                    if !Task.isCancelled, !self.isSuspendedForStreaming {
                        let minimumDuration = plan.minimumVisibleDuration
                        let elapsed = Date().timeIntervalSince(startedAt)
                        let minimumDurationSeconds = Double(minimumDuration.components.seconds)
                            + (Double(minimumDuration.components.attoseconds) / 1_000_000_000_000_000_000)
                        if elapsed < minimumDurationSeconds {
                            let remainingNanos = UInt64((minimumDurationSeconds - elapsed) * 1_000_000_000)
                            try? await Task.sleep(for: .nanoseconds(remainingNanos))
                        }
                        if !Task.isCancelled, !self.isSuspendedForStreaming {
                            self.phase = .ready
                        }
                    }
                }
                await registry.remove(id: TaskID.hydration)
            }
        }
        if !inserted {
            // A hydration task is already in-flight; keep existing gate state until the
            // registered owner clears it on completion.
        }
    }
}
