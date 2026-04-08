// AppStreamPriorityShellController.swift
// Defines the app stream priority shell controller that coordinates the App / Shell surface.
//

import Foundation

enum AppStreamPriorityPolicy {
    case tearDownShell
}

struct AppStreamPriorityShellDependencies {
    let suspendShellBootstrap: @MainActor () async -> Void
    let resumeShellBootstrap: @MainActor () -> Void
    let suspendLibrary: @MainActor () async -> Void
    let resumeLibrary: @MainActor () -> Void
    let suspendProfile: @MainActor () async -> Void
    let resumeProfile: @MainActor () -> Void
    let suspendConsole: @MainActor () async -> Void
    let resumeConsole: @MainActor () -> Void
    let suspendAchievements: @MainActor () async -> Void
    let resumeAchievements: @MainActor () -> Void
    let authState: @MainActor () -> SessionAuthState
    let hasStreamingSession: @MainActor () -> Bool
    let makePostStreamHydrationPlan: @MainActor () -> PostStreamHydrationPlan
    let runPostStreamDeltaRefresh: @MainActor (PostStreamHydrationPlan) async -> PostStreamRefreshResult
    let runPostStreamFullRefresh: @MainActor () async -> Void
    let prefetchArtwork: @MainActor () async -> Void
    let setShellStatusText: @MainActor (String?) -> Void
    let setShellIsLoading: @MainActor (Bool) -> Void
    let markShellRestored: @MainActor () -> Void
}

@MainActor
final class AppStreamPriorityShellController {
    private let priorityModeCoordinator: StreamPriorityModeCoordinator
    private let postStreamShellRecoveryWorkflow: PostStreamShellRecoveryWorkflow
    private let dependencies: AppStreamPriorityShellDependencies
    private var isShellSuspended = false

    init(
        priorityModeCoordinator: StreamPriorityModeCoordinator = StreamPriorityModeCoordinator(),
        postStreamShellRecoveryWorkflow: PostStreamShellRecoveryWorkflow = PostStreamShellRecoveryWorkflow(),
        dependencies: AppStreamPriorityShellDependencies
    ) {
        self.priorityModeCoordinator = priorityModeCoordinator
        self.postStreamShellRecoveryWorkflow = postStreamShellRecoveryWorkflow
        self.dependencies = dependencies
    }

    var isShellSuspendedForStreaming: Bool {
        isShellSuspended
    }

#if DEBUG
    var invocationCount: Int {
        postStreamShellRecoveryWorkflow.invocationCount
    }

    var deltaAttemptCount: Int {
        postStreamShellRecoveryWorkflow.deltaAttemptCount
    }

    var fullRefreshFallbackCount: Int {
        postStreamShellRecoveryWorkflow.fullRefreshFallbackCount
    }

    var testingPostStreamDeltaRefreshOverride: (@MainActor () async -> PostStreamRefreshResult)? {
        get { postStreamShellRecoveryWorkflow.testingPostStreamDeltaRefreshOverride }
        set { postStreamShellRecoveryWorkflow.testingPostStreamDeltaRefreshOverride = newValue }
    }

    var testingPostStreamFullRefreshOverride: (@MainActor () async -> Void)? {
        get { postStreamShellRecoveryWorkflow.testingPostStreamFullRefreshOverride }
        set { postStreamShellRecoveryWorkflow.testingPostStreamFullRefreshOverride = newValue }
    }
#endif

    func enter(policy: AppStreamPriorityPolicy) async {
        guard case .tearDownShell = policy else { return }
        isShellSuspended = await priorityModeCoordinator.enterShellPriorityMode(
            isShellSuspendedForStreaming: isShellSuspended,
            policyLabel: "tear_down_shell",
            environment: makeShellEnvironment()
        )
    }

    func exit() async {
        isShellSuspended = await priorityModeCoordinator.exitShellPriorityMode(
            isShellSuspendedForStreaming: isShellSuspended,
            environment: makeShellEnvironment()
        )
    }

    private func makeShellEnvironment() -> StreamPriorityShellEnvironment {
        StreamPriorityShellEnvironment(
            participants: [
                StreamPriorityShellParticipant(
                    suspend: { [dependencies] in
                        await dependencies.suspendShellBootstrap()
                    },
                    resume: { [dependencies] in
                        dependencies.resumeShellBootstrap()
                    }
                ),
                StreamPriorityShellParticipant(
                    suspend: { [dependencies] in
                        await dependencies.suspendLibrary()
                    },
                    resume: { [dependencies] in
                        dependencies.resumeLibrary()
                    }
                ),
                StreamPriorityShellParticipant(
                    suspend: { [dependencies] in
                        await dependencies.suspendProfile()
                    },
                    resume: { [dependencies] in
                        dependencies.resumeProfile()
                    }
                ),
                StreamPriorityShellParticipant(
                    suspend: { [dependencies] in
                        await dependencies.suspendConsole()
                    },
                    resume: { [dependencies] in
                        dependencies.resumeConsole()
                    }
                ),
                StreamPriorityShellParticipant(
                    suspend: { [dependencies] in
                        await dependencies.suspendAchievements()
                    },
                    resume: { [dependencies] in
                        dependencies.resumeAchievements()
                    }
                )
            ],
            refreshPostStreamShellState: { [weak self] in
                await self?.refreshPostStreamShellState()
            }
        )
    }

    private func refreshPostStreamShellState() async {
        guard case .authenticated = dependencies.authState() else {
            dependencies.setShellStatusText(nil)
            dependencies.setShellIsLoading(false)
            dependencies.markShellRestored()
            return
        }
        guard !dependencies.hasStreamingSession() else {
            dependencies.setShellStatusText(nil)
            dependencies.setShellIsLoading(false)
            return
        }

        await postStreamShellRecoveryWorkflow.run(
            environment: PostStreamShellRecoveryEnvironment(
                makePlan: { [dependencies] in
                    dependencies.makePostStreamHydrationPlan()
                },
                runDeltaRefresh: { [dependencies] plan in
                    await dependencies.runPostStreamDeltaRefresh(plan)
                },
                runFullRefresh: { [dependencies] in
                    await dependencies.runPostStreamFullRefresh()
                },
                prefetchArtwork: { [dependencies] in
                    await dependencies.prefetchArtwork()
                },
                setStatusText: { [dependencies] text in
                    dependencies.setShellStatusText(text)
                },
                setIsLoading: { [dependencies] isLoading in
                    dependencies.setShellIsLoading(isLoading)
                },
                markShellRestored: { [dependencies] in
                    dependencies.markShellRestored()
                }
            )
        )
    }
}
