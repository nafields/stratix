// StreamPriorityModeCoordinator.swift
// Defines the stream priority mode coordinator for the Streaming surface.
//

import Foundation
import DiagnosticsKit

struct StreamPriorityModeEnvironment {
    let enterPriorityMode: @Sendable @MainActor () async -> Void
    let exitPriorityMode: @Sendable @MainActor () async -> Void
}

struct StreamPriorityShellParticipant {
    let suspend: @Sendable @MainActor () async -> Void
    let resume: @Sendable @MainActor () -> Void
}

struct StreamPriorityShellEnvironment {
    let participants: [StreamPriorityShellParticipant]
    let refreshPostStreamShellState: @Sendable @MainActor () async -> Void
}

@MainActor
final class StreamPriorityModeCoordinator {
    func enter(
        context: StreamRuntimeContext,
        state: StreamState,
        environment: StreamPriorityModeEnvironment,
        publish: @escaping @MainActor ([StreamAction]) -> Void
    ) async {
        publish([
            .runtimeContextSet(context),
            .shellRestoredAfterExitSet(false)
        ])

        StreamPerformanceTracker.mark(
            .streamIntent,
            metadata: ["context": context.performanceLabel]
        )

        switch state.runtimePhase {
        case .shellActive, .restoringShell:
            publish([.runtimePhaseSet(.preparingStream)])
            await environment.enterPriorityMode()
        case .preparingStream, .streaming:
            break
        }
    }

    func exit(
        state: StreamState,
        environment: StreamPriorityModeEnvironment,
        publish: @escaping @MainActor ([StreamAction]) -> Void
    ) async {
        publish([.runtimeContextSet(nil)])
        guard state.runtimePhase != .shellActive else { return }
        publish([.runtimePhaseSet(.restoringShell)])
        await environment.exitPriorityMode()
        publish([.runtimePhaseSet(.shellActive)])
    }

    func enterShellPriorityMode(
        isShellSuspendedForStreaming: Bool,
        policyLabel: String,
        environment: StreamPriorityShellEnvironment
    ) async -> Bool {
        guard !isShellSuspendedForStreaming else { return true }
        for participant in environment.participants {
            await participant.suspend()
        }
        StreamPerformanceTracker.mark(
            .shellSuspended,
            metadata: ["policy": policyLabel]
        )
        return true
    }

    func exitShellPriorityMode(
        isShellSuspendedForStreaming: Bool,
        environment: StreamPriorityShellEnvironment
    ) async -> Bool {
        guard isShellSuspendedForStreaming else { return false }
        StreamPerformanceTracker.mark(.shellResumeStart)
        for participant in environment.participants {
            participant.resume()
        }
        await environment.refreshPostStreamShellState()
        StreamPerformanceTracker.mark(.shellResumeFinish)
        return false
    }
}
