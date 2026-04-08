// LibraryHydrationStartupRestoreWorkflowTests.swift
// Exercises library hydration startup restore workflow behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing

@Suite(.serialized)
struct LibraryHydrationStartupRestoreWorkflowTests {
    @Test
    func run_loadsStartupPayload_andBuildsRestoreResult() async {
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date())
        let expected = LibraryStartupRestoreResult(
            productDetails: .apply([ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo")]),
            sections: .apply(snapshot)
        )
        let planner = TestLibraryHydrationPlanner(startupRestoreResult: expected)
        let worker = TestLibraryHydrationWorker(
            payload: LibraryStartupCachePayload(
                productDetails: .unavailable,
                sectionsSnapshot: snapshot
            )
        )

        let result = await LibraryHydrationStartupRestoreWorkflow().run(
            request: LibraryHydrationRequest(
                trigger: .startupRestore,
                market: "US",
                language: "en-US",
                preferDeltaRefresh: false,
                forceFullRefresh: false,
                allowCacheRestore: true,
                allowPersistenceWrite: false,
                deferInitialRoutePublication: false,
                refreshReason: nil,
                sourceDescription: "startup"
            ),
            planner: planner,
            worker: worker,
            shouldLoadProductDetails: true,
            shouldLoadSections: true,
            expectedCacheVersion: LibraryHydrationCacheSchema.currentCacheVersion
        )

        #expect(planner.startupRestoreCalls == 1)
        #expect(await worker.loadStartupCachePayloadCalls == 1)
        if case .apply(let appliedSnapshot)? = result.sections {
            #expect(appliedSnapshot.sections.map(\.id) == ["library"])
        } else {
            Issue.record("Expected startup restore to apply the unified snapshot.")
        }
    }

    @Test
    func run_returnsUnavailableOutcomes_whenCachesMissing() async {
        let planner = LibraryHydrationPlanner(now: Date.init)
        let worker = TestLibraryHydrationWorker(
            payload: LibraryStartupCachePayload(
                productDetails: .unavailable,
                sectionsSnapshot: nil
            )
        )

        let result = await LibraryHydrationStartupRestoreWorkflow().run(
            request: LibraryHydrationRequest(
                trigger: .startupRestore,
                market: "US",
                language: "en-US",
                preferDeltaRefresh: false,
                forceFullRefresh: false,
                allowCacheRestore: true,
                allowPersistenceWrite: false,
                deferInitialRoutePublication: false,
                refreshReason: nil,
                sourceDescription: "startup"
            ),
            planner: planner,
            worker: worker,
            shouldLoadProductDetails: true,
            shouldLoadSections: true,
            expectedCacheVersion: LibraryHydrationCacheSchema.currentCacheVersion
        )

        if case .unavailable? = result.productDetails {
        } else {
            Issue.record("Expected missing product details cache to be unavailable.")
        }
        if case .unavailable? = result.sections {
        } else {
            Issue.record("Expected missing sections cache to be unavailable.")
        }
    }

    @Test
    func run_rejectsVersionMismatch_whenSnapshotVersionIsOld() async {
        let staleSnapshot = DecodedLibrarySectionsCacheSnapshot(
            savedAt: Date(),
            sections: TestHydrationFixtures.unifiedSnapshot(savedAt: Date()).sections,
            homeMerchandising: TestHydrationFixtures.unifiedSnapshot(savedAt: Date()).homeMerchandising,
            discovery: TestHydrationFixtures.unifiedSnapshot(savedAt: Date()).discovery,
            isUnifiedHomeReady: true,
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion - 1,
            metadata: .compatibility(
                savedAt: Date(),
                cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion - 1
            )
        )
        let detailSnapshot = ProductDetailsDiskCacheSnapshot(
            savedAt: Date(),
            details: [ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo")],
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion - 1
        )
        let planner = LibraryHydrationPlanner(now: Date.init)
        let worker = TestLibraryHydrationWorker(
            payload: LibraryStartupCachePayload(
                productDetails: .snapshot(detailSnapshot),
                sectionsSnapshot: staleSnapshot
            )
        )

        let result = await LibraryHydrationStartupRestoreWorkflow().run(
            request: LibraryHydrationRequest(
                trigger: .startupRestore,
                market: "US",
                language: "en-US",
                preferDeltaRefresh: false,
                forceFullRefresh: false,
                allowCacheRestore: true,
                allowPersistenceWrite: false,
                deferInitialRoutePublication: false,
                refreshReason: nil,
                sourceDescription: "startup"
            ),
            planner: planner,
            worker: worker,
            shouldLoadProductDetails: true,
            shouldLoadSections: true,
            expectedCacheVersion: LibraryHydrationCacheSchema.currentCacheVersion
        )

        if case .rejectVersionMismatch(let found, let expected)? = result.productDetails {
            #expect(found == LibraryHydrationCacheSchema.currentCacheVersion - 1)
            #expect(expected == LibraryHydrationCacheSchema.currentCacheVersion)
        } else {
            Issue.record("Expected product details version mismatch rejection.")
        }
        if case .rejectVersionMismatch(let found, let expected)? = result.sections {
            #expect(found == LibraryHydrationCacheSchema.currentCacheVersion - 1)
            #expect(expected == LibraryHydrationCacheSchema.currentCacheVersion)
        } else {
            Issue.record("Expected sections version mismatch rejection.")
        }
    }
}
