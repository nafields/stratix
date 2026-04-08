// LibraryPostLoadWarmupCoordinator.swift
// Defines the library post load warmup coordinator.
//

import Foundation

struct LibraryPostLoadWarmupEnvironment {
    let loadCurrentUserProfile: @Sendable @MainActor () async -> Void
    let loadSocialPeople: @Sendable @MainActor (Int) async -> Void
}

@MainActor
struct LibraryPostLoadWarmupCoordinator {
    func warm(
        taskRegistry: TaskRegistry,
        taskID: String,
        environment: LibraryPostLoadWarmupEnvironment,
        isSuspendedForStreaming: @escaping () -> Bool
    ) async {
        guard !isSuspendedForStreaming() else { return }
        await taskRegistry.cancel(id: taskID)
        let registry = taskRegistry
        _ = await taskRegistry.register(Task { @MainActor [registry] in
            if !isSuspendedForStreaming() {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await environment.loadCurrentUserProfile() }
                    group.addTask { await environment.loadSocialPeople(48) }
                    for await _ in group {}
                }
            }
            await registry.remove(id: taskID)
        }, id: taskID)
    }
}
