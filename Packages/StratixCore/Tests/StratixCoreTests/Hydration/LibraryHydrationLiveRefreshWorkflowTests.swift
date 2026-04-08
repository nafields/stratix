// LibraryHydrationLiveRefreshWorkflowTests.swift
// Exercises library hydration live refresh workflow behavior.
//

import Foundation
@testable import StratixCore
import Testing

@MainActor
@Suite(.serialized)
struct LibraryHydrationLiveRefreshWorkflowTests {
    @Test
    func run_respectsSuspendedStreamingGuard() async throws {
        let controller = LibraryController()
        await controller.suspendForStreaming()

        let result = try await LibraryHydrationLiveRefreshWorkflow().run(
            request: LibraryHydrationRequest(
                trigger: .liveRefresh,
                market: "US",
                language: "en-US",
                preferDeltaRefresh: false,
                forceFullRefresh: false,
                allowCacheRestore: false,
                allowPersistenceWrite: true,
                deferInitialRoutePublication: false,
                refreshReason: .manualUser,
                sourceDescription: "test"
            ),
            controller: controller
        )

        #expect(result.committedSections.isEmpty)
        #expect(result.hydratedProductCount == 0)
        #expect(result.recoveryState == nil)
        #expect(result.catalogState.titles.isEmpty)
        #expect(result.catalogState.mruEntries.isEmpty)
    }
}
