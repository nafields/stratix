// LibraryControllerHydrationDelegationTests.swift
// Exercises library controller hydration delegation behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing
import XCloudAPI

@MainActor
@Suite(.serialized)
struct LibraryControllerHydrationDelegationTests {
    @Test
    func refresh_delegatesToHydrationOrchestrator_whenNoCustomRefreshWorkflowIsInjected() async {
        let orchestrator = TestLibraryHydrationOrchestrator()
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date())
        orchestrator.liveRefreshResult = TestHydrationFixtures.orchestrationResult(
            publishedState: .cacheRestore(snapshot: snapshot),
            persistenceIntent: .none,
            cachedDiscovery: snapshot.discovery,
            source: .liveRefresh
        )
        let controller = LibraryController(hydrationOrchestrator: orchestrator)
        let coordinator = AppCoordinator()
        let services = AppLibraryControllerServices(
            sessionController: coordinator.sessionController,
            profileController: coordinator.profileController,
            achievementsController: coordinator.achievementsController
        )
        controller.attach(services)
        await coordinator.sessionController.applyTokensFromCoordinator(
            StreamTokens(
                xhomeToken: "xhome-token",
                xhomeHost: "https://xhome.example.com",
                xcloudToken: "xcloud-token",
                xcloudHost: "https://xcloud.example.com",
                xcloudF2PToken: nil,
                xcloudF2PHost: nil
            ),
            mode: .full
        )

        await controller.refresh(forceRefresh: true, reason: .manualUser)

        #expect(orchestrator.liveRefreshCalls == 1)
        #expect(controller.sections.map(\.id) == ["library"])
    }

    @Test
    func restoreDiskCachesIfNeeded_delegatesToHydrationOrchestrator() async {
        let orchestrator = TestLibraryHydrationOrchestrator()
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date())
        orchestrator.startupRestoreResult = TestHydrationFixtures.orchestrationResult(
            publishedState: .cacheRestore(snapshot: snapshot),
            persistenceIntent: .none,
            cachedDiscovery: snapshot.discovery,
            source: .startupRestore
        )
        let controller = LibraryController(hydrationOrchestrator: orchestrator)

        await controller.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(orchestrator.startupRestoreCalls == 1)
        #expect(controller.sections.map(\.id) == ["library"])
        #expect(controller.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
    }

    @Test
    func refreshPostStreamResumeDelta_delegatesToHydrationOrchestrator() async {
        let orchestrator = TestLibraryHydrationOrchestrator()
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date())
        orchestrator.postStreamResult = TestHydrationFixtures.orchestrationResult(
            publishedState: .cacheRestore(snapshot: snapshot),
            persistenceIntent: .none,
            cachedDiscovery: snapshot.discovery,
            source: .postStreamDelta,
            postStreamResult: .appliedDelta
        )
        let controller = LibraryController(hydrationOrchestrator: orchestrator)

        let result = await controller.refreshPostStreamResumeDelta(
            plan: PostStreamHydrationPlan(mode: .refreshMRUDelta, decisionDescription: "fresh_unified_snapshot")
        )

        #expect(orchestrator.postStreamCalls == 1)
        #expect(result == .appliedDelta)
        #expect(controller.sections.map(\.id) == ["library"])
    }

    @Test
    func applyHydrationOrchestrationResult_updatesControllerStateAndSchedulesPersistence() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("controller-hydration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let controller = LibraryController(
            cacheLocations: .init(
                details: cacheRoot.appendingPathComponent("details.json"),
                sections: cacheRoot.appendingPathComponent("sections.json"),
                homeMerchandising: cacheRoot.appendingPathComponent("home.json")
            )
        )
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date())
        let details = [ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")]
        await controller.applyHydrationOrchestrationResult(
            TestHydrationFixtures.orchestrationResult(
                publishedState: .cacheRestore(snapshot: snapshot),
                productDetailsState: .liveRecovery(details: details),
                persistenceIntent: .unifiedSectionsAndProductDetails(
                    sections: LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
                        sections: snapshot.sections,
                        homeMerchandising: snapshot.homeMerchandising,
                        discovery: snapshot.discovery,
                        savedAt: snapshot.savedAt,
                        isUnifiedHomeReady: snapshot.isUnifiedHomeReady
                    ),
                    details: ProductDetailsDiskCacheSnapshot(savedAt: snapshot.savedAt, details: details)
                ),
                cachedDiscovery: snapshot.discovery,
                source: .liveRefresh,
            )
        )

        await Task.yield()
        await controller.flushSectionsCacheForTesting()
        await controller.flushProductDetailsCacheForTesting()

        #expect(controller.sections.map(\.id) == ["library"])
        #expect(controller.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(controller.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(controller.cacheSavedAt == snapshot.savedAt)

        let repository = try SwiftDataLibraryRepository(
            storeURL: cacheRoot.appendingPathComponent("sections.swiftdata")
        )
        let detailsData = try Data(contentsOf: cacheRoot.appendingPathComponent("details.json"))
        let decodedSections = try #require(await repository.loadUnifiedSectionsSnapshot())
        let decodedDetails = try JSONDecoder().decode(ProductDetailsDiskCacheSnapshot.self, from: detailsData)

        #expect(decodedSections.sections.map(\.id) == ["library"])
        #expect(decodedDetails.details[ProductID("product-1")]?.title == "Halo Infinite")
    }
}
