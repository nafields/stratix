// TestHydrationFixtures.swift
// Exercises test hydration fixtures behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing
import XCloudAPI

enum TestHydrationFixtures {
    static func section(
        id: String = "library",
        name: String = "Library",
        items: [CloudLibraryItem]
    ) -> CloudLibrarySection {
        CloudLibrarySection(id: id, name: name, items: items)
    }

    static func item(
        titleId: String,
        productId: String,
        isInMRU: Bool = false
    ) -> CloudLibraryItem {
        CloudLibraryItem(
            titleId: titleId,
            productId: productId,
            name: "Test \(titleId)",
            shortDescription: nil,
            artURL: URL(string: "https://example.com/\(titleId).jpg"),
            supportedInputTypes: ["controller"],
            isInMRU: isInMRU
        )
    }

    static func discoveryEntry(alias: String, siglID: String) -> GamePassSiglDiscoveryEntry {
        GamePassSiglDiscoveryEntry(
            alias: alias,
            label: alias,
            siglID: siglID,
            source: .nextData
        )
    }

    static func titleDTO(
        titleId: String,
        productId: String,
        name: String,
        entitled: Bool,
        inputs: [String] = ["controller"]
    ) -> XCloudTitleDTO {
        XCloudTitleDTO(
            titleId: titleId,
            details: .init(
                productId: productId,
                name: name,
                hasEntitlement: entitled,
                supportedInputTypes: inputs
            )
        )
    }

    static func titlesResponse(_ results: [XCloudTitleDTO]) -> XCloudTitlesResponse {
        XCloudTitlesResponse(results: results)
    }

    static func catalogProduct(
        productId: String,
        title: String,
        shortDescription: String? = nil,
        publisherName: String? = nil,
        screenshotURL: String? = nil
    ) -> GamePassCatalogClient.CatalogProduct {
        var payload: [String: Any] = [
            "ProductId": productId,
            "ProductTitle": title
        ]
        if let shortDescription {
            payload["ProductDescriptionShort"] = shortDescription
        }
        if let publisherName {
            payload["PublisherName"] = publisherName
        }
        if let screenshotURL {
            payload["Screenshots"] = [[
                "URL": screenshotURL,
                "Width": 1920,
                "Height": 1080
            ]]
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(GamePassCatalogClient.CatalogProduct.self, from: data)
    }

    static func unifiedSnapshot(savedAt: Date) -> DecodedLibrarySectionsCacheSnapshot {
        let section = section(
            items: [item(titleId: "title-1", productId: "product-1")]
        )
        let discovery = HomeMerchandisingDiscoveryCachePayload(
            entries: [discoveryEntry(alias: "recently-added", siglID: "sigl-recent")],
            savedAt: savedAt
        )
        let merchandising = HomeMerchandisingSnapshot(
            recentlyAddedItems: [item(titleId: "title-1", productId: "product-1")],
            rows: [
                HomeMerchandisingRow(
                    alias: "recently-added",
                    label: "recently-added",
                    source: .fixedPriority,
                    items: [item(titleId: "title-1", productId: "product-1")]
                )
            ],
            generatedAt: savedAt
        )
        return DecodedLibrarySectionsCacheSnapshot(
            savedAt: savedAt,
            sections: [section],
            homeMerchandising: merchandising,
            discovery: discovery,
            isUnifiedHomeReady: true,
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
            metadata: .compatibility(
                savedAt: savedAt,
                cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
                refreshSource: "test_fixture",
                homeReady: true
            )
        )
    }

    static func actions(
        publishedState: LibraryHydrationPublishedState? = nil,
        productDetailsState: LibraryHydrationProductDetailsState? = nil
    ) -> [LibraryAction] {
        var actions: [LibraryAction] = []
        if let productDetailsState {
            actions.append(.hydrationProductDetailsStateApplied(productDetailsState))
        }
        if let publishedState {
            actions.append(.hydrationPublishedStateApplied(publishedState))
        }
        return actions
    }

    static func orchestrationResult(
        publishedState: LibraryHydrationPublishedState? = nil,
        productDetailsState: LibraryHydrationProductDetailsState? = nil,
        persistenceIntent: LibraryHydrationPersistenceIntent = .none,
        cachedDiscovery: HomeMerchandisingDiscoveryCachePayload? = nil,
        source: LibraryHydrationTrigger,
        publicationPlan: LibraryHydrationPublicationPlan = LibraryHydrationPublicationPlan(stages: []),
        postStreamResult: PostStreamRefreshResult? = nil
    ) -> LibraryHydrationOrchestrationResult {
        LibraryHydrationOrchestrationResult(
            actions: actions(
                publishedState: publishedState,
                productDetailsState: productDetailsState
            ),
            persistenceIntent: persistenceIntent,
            cachedDiscovery: cachedDiscovery,
            source: source,
            publicationPlan: publicationPlan,
            postStreamResult: postStreamResult
        )
    }

    static func commitResult(
        publishedState: LibraryHydrationPublishedState? = nil,
        productDetailsState: LibraryHydrationProductDetailsState? = nil,
        persistenceIntent: LibraryHydrationPersistenceIntent = .none,
        cachedDiscovery: HomeMerchandisingDiscoveryCachePayload? = nil,
        publicationPlan: LibraryHydrationPublicationPlan = LibraryHydrationPublicationPlan(stages: []),
        shouldPrefetchArtwork: Bool = false,
        shouldWarmProfileAndSocial: Bool = false,
        postStreamResult: PostStreamRefreshResult? = nil
    ) -> LibraryHydrationCommitResult {
        LibraryHydrationCommitResult(
            persistenceIntent: persistenceIntent,
            cachedDiscovery: cachedDiscovery,
            actions: actions(
                publishedState: publishedState,
                productDetailsState: productDetailsState
            ),
            shouldPrefetchArtwork: shouldPrefetchArtwork,
            shouldWarmProfileAndSocial: shouldWarmProfileAndSocial,
            publicationPlan: publicationPlan,
            postStreamResult: postStreamResult
        )
    }
}

final class TestLibraryHydrationPlanner: @unchecked Sendable, LibraryHydrationPlanning {
    var startupRestoreResult: LibraryStartupRestoreResult
    var startupRestoreCalls = 0

    init(startupRestoreResult: LibraryStartupRestoreResult) {
        self.startupRestoreResult = startupRestoreResult
    }

    func hasFreshCompleteStartupSnapshot(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> Bool { false }

    func requiresUnifiedHydration(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> Bool { true }

    func startupRestoreDecision(for snapshot: LibrarySectionsDiskCacheSnapshot) -> LibraryHydrationPlanner.StartupRestoreDecision {
        .applyUnifiedSnapshot
    }

    func startupRestoreDecision(for snapshot: DecodedLibrarySectionsCacheSnapshot) -> LibraryHydrationPlanner.StartupRestoreDecision {
        .applyUnifiedSnapshot
    }

    func shouldApplyUnifiedSectionsCache(_ snapshot: LibrarySectionsDiskCacheSnapshot) -> Bool { true }
    func shouldApplyUnifiedSectionsCache(_ snapshot: DecodedLibrarySectionsCacheSnapshot) -> Bool { true }

    func makeStartupRestoreResult(
        payload: LibraryStartupCachePayload,
        shouldLoadProductDetails: Bool,
        shouldLoadSections: Bool,
        expectedCacheVersion: Int
    ) -> LibraryStartupRestoreResult {
        startupRestoreCalls += 1
        return startupRestoreResult
    }

    func makeShellBootPlan(
        isAuthenticated: Bool,
        hasFreshCompleteStartupSnapshot: Bool
    ) -> ShellBootHydrationPlan? { nil }

    func makePostStreamPlan(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> PostStreamHydrationPlan {
        PostStreamHydrationPlan(mode: .refreshNetwork, decisionDescription: "test")
    }

    func isUnifiedHydrationStale(generatedAt: Date) -> Bool { false }
}

actor TestLibraryHydrationWorker: LibraryHydrationWorking {
    var payload: LibraryStartupCachePayload
    var loadStartupCachePayloadCalls = 0

    init(payload: LibraryStartupCachePayload) {
        self.payload = payload
    }

    func loadStartupCachePayload(
        loadProductDetails: Bool,
        loadSections: Bool
    ) async -> LibraryStartupCachePayload {
        loadStartupCachePayloadCalls += 1
        return payload
    }

    func loadProductDetailsCacheSnapshot() async -> ProductDetailsCacheLoadResult {
        payload.productDetails
    }

    func loadDecodedSectionsCacheSnapshot() async -> DecodedLibrarySectionsCacheSnapshot? {
        payload.sectionsSnapshot
    }

    func loadHomeMerchandisingCacheSnapshot() async -> HomeMerchandisingDiskCacheSnapshot? {
        nil
    }
}

final class TestLibraryHydrationOrchestrator: @unchecked Sendable, LibraryHydrationOrchestrating {
    var startupRestoreCalls = 0
    var liveRefreshCalls = 0
    var postStreamCalls = 0
    var startupRestoreResult = TestHydrationFixtures.orchestrationResult(source: .startupRestore)
    var liveRefreshResult = TestHydrationFixtures.orchestrationResult(source: .liveRefresh)
    var postStreamResult = TestHydrationFixtures.orchestrationResult(
        source: .postStreamDelta,
        postStreamResult: .noChange
    )

    func performStartupRestore(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult {
        startupRestoreCalls += 1
        return startupRestoreResult
    }

    func performLiveRefresh(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult {
        liveRefreshCalls += 1
        return liveRefreshResult
    }

    func performPostStreamDelta(
        controller: LibraryController,
        request: LibraryHydrationRequest
    ) async throws -> LibraryHydrationOrchestrationResult {
        postStreamCalls += 1
        return postStreamResult
    }
}

struct TestLibraryHydrationStartupRestoreWorkflow: LibraryHydrationStartupRestoring {
    var result: LibraryStartupRestoreResult
    let recorder: Recorder

    actor Recorder {
        private(set) var calls = 0

        func record() {
            calls += 1
        }
    }

    func run(
        request: LibraryHydrationRequest,
        planner: any LibraryHydrationPlanning,
        worker: any LibraryHydrationWorking,
        shouldLoadProductDetails: Bool,
        shouldLoadSections: Bool,
        expectedCacheVersion: Int
    ) async -> LibraryStartupRestoreResult {
        await recorder.record()
        return result
    }
}

struct TestLibraryHydrationLiveRefreshWorkflow: LibraryHydrationLiveRefreshing {
    var result: Result<LibraryHydrationLiveFetchResult, Error>
    let recorder: Recorder

    actor Recorder {
        private(set) var calls = 0

        func record() {
            calls += 1
        }
    }

    func run(
        request: LibraryHydrationRequest,
        controller: LibraryController
    ) async throws -> LibraryHydrationLiveFetchResult {
        await recorder.record()
        return try result.get()
    }
}

struct TestLibraryHydrationLiveCommitWorkflow: LibraryHydrationLiveCommitting {
    var result: LibraryHydrationCommitResult
    let recorder: Recorder

    actor Recorder {
        private(set) var calls = 0

        func record() {
            calls += 1
        }
    }

    func commit(
        context: LibraryHydrationCommitContext,
        fetchResult: LibraryHydrationLiveFetchResult,
        controller: LibraryController
    ) async -> LibraryHydrationCommitResult {
        await recorder.record()
        return result
    }
}

struct TestLibraryHydrationPostStreamDeltaWorkflow: LibraryHydrationPostStreamDeltaRunning {
    var result: Result<LibraryHydrationOrchestrationResult, Error>
    let recorder: Recorder

    actor Recorder {
        private(set) var calls = 0

        func record() {
            calls += 1
        }
    }

    func run(
        request: LibraryHydrationRequest,
        dependencies: LibraryHydrationPostStreamDeltaWorkflow.Dependencies
    ) async throws -> LibraryHydrationOrchestrationResult {
        await recorder.record()
        return try result.get()
    }
}
