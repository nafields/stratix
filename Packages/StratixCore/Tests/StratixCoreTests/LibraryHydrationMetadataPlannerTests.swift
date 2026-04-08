// LibraryHydrationMetadataPlannerTests.swift
// Exercises library hydration metadata planner behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing

@Suite(.serialized)
struct LibraryHydrationMetadataPlannerTests {
    @Test
    func planner_rejectsSnapshotWithWrongMarket() {
        let planner = LibraryHydrationPlanner(now: Date.init)
        let snapshot = makeSnapshot(
            market: "GB",
            language: "en-US",
            completenessBySectionID: ["library": true]
        )

        #expect(planner.startupRestoreDecision(for: snapshot) == .reject("market_or_language_mismatch"))
    }

    @Test
    func planner_rejectsSnapshotWithWrongLanguage() {
        let planner = LibraryHydrationPlanner(now: Date.init)
        let snapshot = makeSnapshot(
            market: LibraryHydrationConfig().market,
            language: "fr-FR",
            completenessBySectionID: ["library": true]
        )

        #expect(planner.startupRestoreDecision(for: snapshot) == .reject("market_or_language_mismatch"))
    }

    @Test
    func planner_prefersSnapshotWithHigherCompleteness() {
        let planner = LibraryHydrationPlanner(now: Date.init)
        let currentBest = makeSnapshot(
            market: LibraryHydrationConfig().market,
            language: LibraryHydrationConfig().language,
            completenessBySectionID: ["library": true, "mru": false]
        )
        let candidate = makeSnapshot(
            market: LibraryHydrationConfig().market,
            language: LibraryHydrationConfig().language,
            completenessBySectionID: ["library": true, "mru": true]
        )

        #expect(planner.preferredStartupSnapshot(currentBest: currentBest, candidate: candidate) == candidate)
    }

    @Test
    func planner_handlesLegacyMetadataFallback() {
        let planner = LibraryHydrationPlanner(now: Date.init)
        let snapshot = makeSnapshot(
            metadata: .compatibility(
                savedAt: Date(),
                cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
                homeReady: true
            )
        )

        #expect(planner.startupRestoreDecision(for: snapshot) == .applyUnifiedSnapshot)
    }

    private func makeSnapshot(
        market: String = LibraryHydrationConfig().market,
        language: String = LibraryHydrationConfig().language,
        completenessBySectionID: [String: Bool] = ["library": true],
        metadata: LibraryHydrationMetadata? = nil
    ) -> LibrarySectionsDiskCacheSnapshot {
        let savedAt = Date()
        let effectiveMetadata = metadata ?? LibraryHydrationMetadata(
            snapshotID: UUID(),
            generatedAt: savedAt,
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
            market: market,
            language: language,
            refreshSource: "test_snapshot",
            hydrationGeneration: 1,
            homeReady: true,
            completenessBySectionID: completenessBySectionID,
            deferredStages: [],
            trigger: "test"
        )
        return LibrarySectionsDiskCacheSnapshot(
            savedAt: savedAt,
            sections: [
                LibrarySectionDiskCacheSnapshot(
                    id: "library",
                    name: "Library",
                    items: [
                        LibraryItemDiskCacheSnapshot(
                            titleId: TitleID("title-1"),
                            productId: ProductID("product-1"),
                            name: "Halo Infinite",
                            shortDescription: nil,
                            artURL: nil,
                            posterImageURL: nil,
                            heroImageURL: nil,
                            galleryImageURLs: [],
                            publisherName: nil,
                            attributes: [],
                            supportedInputTypes: ["controller"],
                            isInMRU: false
                        )
                    ]
                )
            ],
            homeMerchandising: HomeMerchandisingDiskCacheSnapshot(
                savedAt: savedAt,
                recentlyAddedItems: [],
                rows: [],
                metadata: effectiveMetadata
            ),
            siglDiscovery: HomeMerchandisingDiscoveryDiskCacheSnapshot(
                savedAt: savedAt,
                entries: [],
                metadata: effectiveMetadata
            ),
            isUnifiedHomeReady: true,
            metadata: effectiveMetadata
        )
    }
}
