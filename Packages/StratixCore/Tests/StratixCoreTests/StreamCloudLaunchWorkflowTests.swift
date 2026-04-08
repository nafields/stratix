// StreamCloudLaunchWorkflowTests.swift
// Exercises stream cloud launch workflow behavior.
//

import DiagnosticsKit
import Foundation
import Testing
import os
@testable import StratixCore
import StratixModels
import XCloudAPI

@MainActor
@Suite(.serialized)
struct StreamCloudLaunchWorkflowTests {
    @Test
    func run_failsWhenCloudAuthThrows() async {
        let workflow = StreamCloudLaunchWorkflow()
        var published: [StreamAction] = []

        await workflow.run(
            titleId: makeTitleID(),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: makeCloudEnvironment(
                cloudConnectAuth: {
                    throw APIError.decodingError("auth failed")
                },
                publish: { published.append(contentsOf: $0) }
            )
        )

        #expect(published.contains { action in
            guard case .streamStartFailed(let message) = action else { return false }
            return message.contains("Cloud connect auth failed")
        })
        #expect(published.contains(.sessionAttachmentStateSet(.detached)))
    }

    @Test
    func run_failsWhenXcloudTokenMissing() async {
        let workflow = StreamCloudLaunchWorkflow()
        var published: [StreamAction] = []

        await workflow.run(
            titleId: makeTitleID(),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: makeCloudEnvironment(
                cloudConnectAuth: {
                    .init(
                        tokens: StreamTokens(
                            xhomeToken: "",
                            xhomeHost: "",
                            xcloudToken: nil,
                            xcloudHost: nil,
                            webToken: nil,
                            webTokenUHS: nil,
                            xcloudRegions: []
                        ),
                        userToken: "user-token"
                    )
                },
                publish: { published.append(contentsOf: $0) }
            )
        )

        #expect(published.contains { action in
            guard case .streamStartFailed(let message) = action else { return false }
            return message.contains("missing xCloud token")
        })
    }

    @Test
    func run_setsHeroURL_beforeCloudConnect() async {
        var publishedBatches: [[StreamAction]] = []
        let heroURL = URL(string: "https://example.com/hero.png")
        let workflow = StreamCloudLaunchWorkflow(
            makeSession: { _, _, _, _ in await makeStreamingSession() },
            connectCloud: { _, _, _ in }
        )

        await workflow.run(
            titleId: makeTitleID(),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: makeCloudEnvironment(
                cachedHeroURL: { _ in heroURL },
                publish: { publishedBatches.append($0) }
            )
        )

        let heroBatchIndex = publishedBatches.firstIndex(where: { batch in
            batch == [.launchHeroURLSet(heroURL)]
        })
        let attachingBatchIndex = publishedBatches.firstIndex(where: { batch in
            batch == [.sessionAttachmentStateSet(.attaching)]
        })

        #expect(heroBatchIndex != nil)
        #expect(attachingBatchIndex != nil)
        #expect(heroBatchIndex! < attachingBatchIndex!)
    }

    @Test
    func run_attachesSession_andStartsCloudConnect() async {
        let connectCalls = ArrayRecorder<(String, String)>()
        let workflow = StreamCloudLaunchWorkflow(
            makeSession: { _, _, _, _ in await makeStreamingSession() },
            connectCloud: { _, titleId, userToken in
                await connectCalls.append((titleId, userToken))
            }
        )

        await workflow.run(
            titleId: makeTitleID("5678"),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: makeCloudEnvironment(publish: { _ in })
        )

        let calls = await connectCalls.snapshot()
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "5678")
        #expect(calls.first?.1 == "user-token")
    }

    @Test
    func run_recordsLaunchAndRuntimePreparedMilestonesIntoSharedPipeline() async {
        let workflow = StreamCloudLaunchWorkflow(
            makeSession: { _, _, _, _ in await makeStreamingSession() },
            connectCloud: { _, _, _ in }
        )
        let records = OSAllocatedUnfairLock(initialState: [StreamMetricsRecord]())
        let token = StreamMetricsPipeline.shared.registerSink(
            StreamMetricsSink(name: #function) { record in
                records.withLock { $0.append(record) }
            }
        )
        defer { StreamMetricsPipeline.shared.unregisterSink(token) }

        await workflow.run(
            titleId: makeTitleID("9999"),
            bridge: TestWebRTCBridge(),
            state: { .empty },
            reconnectCoordinator: StreamReconnectCoordinator(),
            environment: makeCloudEnvironment(publish: { _ in })
        )

        let milestoneRecords = records.withLock { allRecords in
            allRecords.compactMap { record -> StreamMetricsMilestoneRecord? in
                guard case .milestone(let milestone) = record.payload else { return nil }
                return milestone.targetID == "9999" ? milestone : nil
            }
        }
        #expect(milestoneRecords.contains { $0.milestone == .launchRequested && $0.context == .cloud })
        #expect(milestoneRecords.contains { $0.milestone == .runtimePrepared && $0.context == .cloud })
    }

    private func makeCloudEnvironment(
        cloudConnectAuth: @escaping @Sendable () async throws -> SessionController.CloudConnectAuth = {
            .init(
                tokens: StreamTokens(
                    xhomeToken: "",
                    xhomeHost: "",
                    xcloudToken: "xcloud-token",
                    xcloudHost: "https://xcloud.example.com",
                    webToken: nil,
                    webTokenUHS: nil,
                    xcloudRegions: []
                ),
                userToken: "user-token"
            )
        },
        cachedHeroURL: @escaping @MainActor (TitleID) -> URL? = { _ in nil },
        publish: @escaping @MainActor ([StreamAction]) -> Void
    ) -> StreamCloudLaunchWorkflowEnvironment {
        StreamCloudLaunchWorkflowEnvironment(
            launchEnvironment: makeStreamLaunchEnvironment(),
            runtimeAttachmentEnvironment: makeRuntimeAttachmentEnvironment(),
            priorityModeEnvironment: StreamPriorityModeEnvironment(
                enterPriorityMode: {},
                exitPriorityMode: {}
            ),
            overlayEnvironment: StreamOverlayEnvironment(
                heroArtworkEnvironment: nil,
                achievementEnvironment: nil,
                shouldContinuePresentationRefresh: { false },
                publishRefreshResult: { _ in },
                injectNeutralFrame: {},
                injectPauseMenuTap: {}
            ),
            logger: GLogger(category: .auth),
            updateControllerSettings: {},
            prepareVideoCapabilities: {},
            cloudConnectAuth: cloudConnectAuth,
            setLastAuthError: { _ in },
            cachedHeroURL: cachedHeroURL,
            apiSession: .shared,
            publish: publish,
            onLifecycleChange: { _ in }
        )
    }
}
