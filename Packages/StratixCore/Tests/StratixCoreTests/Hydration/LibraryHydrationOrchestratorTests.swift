// LibraryHydrationOrchestratorTests.swift
// Exercises library hydration orchestrator behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing

@MainActor
@Suite(.serialized)
struct LibraryHydrationOrchestratorTests {
    @Test
    func startupRestore_usesStartupWorkflow_andReturnsPublishedStateWithoutPersistenceIntent() async throws {
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date())
        let startupRecorder = TestLibraryHydrationStartupRestoreWorkflow.Recorder()
        let liveRefreshRecorder = TestLibraryHydrationLiveRefreshWorkflow.Recorder()
        let commitRecorder = TestLibraryHydrationLiveCommitWorkflow.Recorder()
        let postStreamRecorder = TestLibraryHydrationPostStreamDeltaWorkflow.Recorder()
        let orchestrator = makeOrchestrator(
            startupRestoreWorkflow: TestLibraryHydrationStartupRestoreWorkflow(
                result: LibraryStartupRestoreResult(
                    productDetails: .unavailable,
                    sections: .apply(snapshot)
                ),
                recorder: startupRecorder
            ),
            liveRefreshWorkflow: TestLibraryHydrationLiveRefreshWorkflow(
                result: .success(makeFetchResult()),
                recorder: liveRefreshRecorder
            ),
            liveCommitWorkflow: TestLibraryHydrationLiveCommitWorkflow(
                result: makeCommitResult(),
                recorder: commitRecorder
            ),
            postStreamDeltaWorkflow: TestLibraryHydrationPostStreamDeltaWorkflow(
                result: .success(makePostStreamResult(.noChange)),
                recorder: postStreamRecorder
            )
        )

        let controller = LibraryController()
        let result = try await orchestrator.performStartupRestore(
            controller: controller,
            request: makeRequest(trigger: .startupRestore, allowPersistenceWrite: false)
        )

        #expect(await startupRecorder.calls == 1)
        #expect(await liveRefreshRecorder.calls == 0)
        #expect(await commitRecorder.calls == 0)
        #expect(await postStreamRecorder.calls == 0)
        #expect(result.actions.contains(where: {
            if case .hydrationPublishedStateApplied(let state) = $0 {
                return state.sections.map(\.id) == ["library"]
            }
            return false
        }))
        if case .none = result.persistenceIntent {
        } else {
            Issue.record("Expected startup restore to avoid persistence scheduling.")
        }
    }

    @Test
    func liveRefresh_usesLiveRefreshAndCommitWorkflow_andReturnsPersistenceIntent() async throws {
        let startupRecorder = TestLibraryHydrationStartupRestoreWorkflow.Recorder()
        let liveRefreshRecorder = TestLibraryHydrationLiveRefreshWorkflow.Recorder()
        let commitRecorder = TestLibraryHydrationLiveCommitWorkflow.Recorder()
        let postStreamRecorder = TestLibraryHydrationPostStreamDeltaWorkflow.Recorder()
        let commitResult = makeCommitResult()
        let orchestrator = makeOrchestrator(
            startupRestoreWorkflow: TestLibraryHydrationStartupRestoreWorkflow(
                result: LibraryStartupRestoreResult(productDetails: .unavailable, sections: .unavailable),
                recorder: startupRecorder
            ),
            liveRefreshWorkflow: TestLibraryHydrationLiveRefreshWorkflow(
                result: .success(makeFetchResult()),
                recorder: liveRefreshRecorder
            ),
            liveCommitWorkflow: TestLibraryHydrationLiveCommitWorkflow(
                result: commitResult,
                recorder: commitRecorder
            ),
            postStreamDeltaWorkflow: TestLibraryHydrationPostStreamDeltaWorkflow(
                result: .success(makePostStreamResult(.noChange)),
                recorder: postStreamRecorder
            )
        )

        let result = try await orchestrator.performLiveRefresh(
            controller: LibraryController(),
            request: makeRequest(trigger: .liveRefresh, allowPersistenceWrite: true)
        )

        #expect(await startupRecorder.calls == 0)
        #expect(await liveRefreshRecorder.calls == 1)
        #expect(await commitRecorder.calls == 1)
        #expect(await postStreamRecorder.calls == 0)
        #expect(result.actions == commitResult.actions)
        switch result.persistenceIntent {
        case .unifiedSectionsAndProductDetails:
            break
        default:
            Issue.record("Expected live refresh orchestration to carry commit persistence intent.")
        }
    }

    @Test
    func postStreamDelta_usesDeltaWorkflow_andReturnsPostStreamResult() async throws {
        let startupRecorder = TestLibraryHydrationStartupRestoreWorkflow.Recorder()
        let liveRefreshRecorder = TestLibraryHydrationLiveRefreshWorkflow.Recorder()
        let commitRecorder = TestLibraryHydrationLiveCommitWorkflow.Recorder()
        let postStreamRecorder = TestLibraryHydrationPostStreamDeltaWorkflow.Recorder()
        let postStreamResult = makePostStreamResult(.appliedDelta)
        let orchestrator = makeOrchestrator(
            startupRestoreWorkflow: TestLibraryHydrationStartupRestoreWorkflow(
                result: LibraryStartupRestoreResult(productDetails: .unavailable, sections: .unavailable),
                recorder: startupRecorder
            ),
            liveRefreshWorkflow: TestLibraryHydrationLiveRefreshWorkflow(
                result: .success(makeFetchResult()),
                recorder: liveRefreshRecorder
            ),
            liveCommitWorkflow: TestLibraryHydrationLiveCommitWorkflow(
                result: makeCommitResult(),
                recorder: commitRecorder
            ),
            postStreamDeltaWorkflow: TestLibraryHydrationPostStreamDeltaWorkflow(
                result: .success(postStreamResult),
                recorder: postStreamRecorder
            )
        )

        let result = try await orchestrator.performPostStreamDelta(
            controller: LibraryController(),
            request: makeRequest(trigger: .postStreamDelta, allowPersistenceWrite: true)
        )

        #expect(await startupRecorder.calls == 0)
        #expect(await liveRefreshRecorder.calls == 0)
        #expect(await commitRecorder.calls == 0)
        #expect(await postStreamRecorder.calls == 1)
        #expect(result.source == .postStreamDelta)
        #expect(result.postStreamResult == .appliedDelta)
    }

    private func makeOrchestrator(
        startupRestoreWorkflow: any LibraryHydrationStartupRestoring,
        liveRefreshWorkflow: any LibraryHydrationLiveRefreshing,
        liveCommitWorkflow: any LibraryHydrationLiveCommitting,
        postStreamDeltaWorkflow: any LibraryHydrationPostStreamDeltaRunning
    ) -> LibraryHydrationOrchestrator {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hydration-orchestrator-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )
        return LibraryHydrationOrchestrator(
            planner: TestLibraryHydrationPlanner(
                startupRestoreResult: LibraryStartupRestoreResult(productDetails: .unavailable, sections: .unavailable)
            ),
            worker: TestLibraryHydrationWorker(
                payload: LibraryStartupCachePayload(productDetails: .unavailable, sectionsSnapshot: nil)
            ),
            persistenceStore: store,
            homeMerchandisingSIGLProvider: .live,
            startupRestoreWorkflow: startupRestoreWorkflow,
            liveRefreshWorkflow: liveRefreshWorkflow,
            liveCommitWorkflow: liveCommitWorkflow,
            postStreamDeltaWorkflow: postStreamDeltaWorkflow
        )
    }

    private func makeRequest(
        trigger: LibraryHydrationTrigger,
        allowPersistenceWrite: Bool
    ) -> LibraryHydrationRequest {
        LibraryHydrationRequest(
            trigger: trigger,
            market: "US",
            language: "en-US",
            preferDeltaRefresh: trigger == .postStreamDelta,
            forceFullRefresh: false,
            allowCacheRestore: trigger == .startupRestore,
            allowPersistenceWrite: allowPersistenceWrite,
            deferInitialRoutePublication: false,
            refreshReason: .manualUser,
            sourceDescription: "test"
        )
    }

    private func makeFetchResult() -> LibraryHydrationLiveFetchResult {
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date())
        return LibraryHydrationLiveFetchResult(
            catalogState: LibraryHydrationCatalogState.liveFetch(
                primaryTitlesResponse: TestHydrationFixtures.titlesResponse([]),
                supplementaryResponses: [],
                mruResponse: TestHydrationFixtures.titlesResponse([]),
                existingSections: snapshot.sections
            ),
            committedSections: snapshot.sections,
            seededProductDetails: CatalogProductDetailsSeedState(details: [:], upsertedCount: 0),
            recoveryState: .postStreamDelta(
                sections: snapshot.sections,
                homeMerchandising: snapshot.homeMerchandising!,
                discovery: snapshot.discovery!,
                savedAt: snapshot.savedAt
            ),
            merchandisingSnapshot: snapshot.homeMerchandising,
            merchandisingDiscovery: snapshot.discovery,
            hydratedCatalogProducts: [],
            hydratedProductCount: 0
        )
    }

    private func makeCommitResult() -> LibraryHydrationCommitResult {
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date())
        return TestHydrationFixtures.commitResult(
            publishedState: .cacheRestore(snapshot: snapshot),
            productDetailsState: .liveRecovery(
                details: [ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")]
            ),
            persistenceIntent: .unifiedSectionsAndProductDetails(
                sections: LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
                    sections: snapshot.sections,
                    homeMerchandising: snapshot.homeMerchandising,
                    discovery: snapshot.discovery,
                    savedAt: snapshot.savedAt,
                    isUnifiedHomeReady: true
                ),
                details: ProductDetailsDiskCacheSnapshot(
                    savedAt: snapshot.savedAt,
                    details: [ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")]
                )
            ),
            cachedDiscovery: snapshot.discovery,
            publicationPlan: LibraryHydrationPublicationPlan(stages: [.routeRestore])
        )
    }

    private func makePostStreamResult(
        _ result: PostStreamRefreshResult
    ) -> LibraryHydrationOrchestrationResult {
        TestHydrationFixtures.orchestrationResult(source: .postStreamDelta, postStreamResult: result)
    }
}
