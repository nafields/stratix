// LibraryCacheRecoveryWorkflowTests.swift
// Exercises library cache recovery workflow behavior.
//

import Foundation
@testable import StratixCore
import Testing

@MainActor
@Suite(.serialized)
struct LibraryCacheRecoveryWorkflowTests {
    @Test
    func restoreDiskCachesIfNeeded_skipsWhenUnauthenticated() async {
        let orchestrator = TestLibraryHydrationOrchestrator()
        let controller = LibraryController(hydrationOrchestrator: orchestrator)

        await controller.restoreDiskCachesIfNeeded(isAuthenticated: false)

        #expect(orchestrator.startupRestoreCalls == 0)
    }

    @Test
    func restoreDiskCachesIfNeeded_delegatesToHydrationOrchestratorWhenAuthenticated() async {
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
        #expect(controller.hasLoadedSectionsCache == true)
    }
}
