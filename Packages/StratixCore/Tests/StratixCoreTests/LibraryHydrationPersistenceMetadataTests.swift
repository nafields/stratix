// LibraryHydrationPersistenceMetadataTests.swift
// Exercises library hydration persistence metadata behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

@Suite(.serialized)
struct LibraryHydrationPersistenceMetadataTests {
    @Test
    func scheduleUnifiedSectionsCache_writesMetadata() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )
        let savedAt = Date(timeIntervalSince1970: 1_706_060_606)
        await store.scheduleUnifiedSectionsCache(
            sections: [TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: savedAt,
            isUnifiedHomeReady: true
        )
        await store.flushUnifiedSectionsCache()

        let repository = try makeRepository(cacheRoot: cacheRoot)
        let decoded = try #require(await repository.loadUnifiedSectionsSnapshot())

        #expect(decoded.metadata.refreshSource == "unified_sections_cache")
        #expect(decoded.metadata.cacheVersion == LibraryHydrationCacheSchema.currentCacheVersion)
        #expect(decoded.metadata.homeReady == true)
        #expect(decoded.metadata.hydrationGeneration > 0)
    }

    @Test
    func scheduleProductDetailsCache_writesMetadata() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )
        await store.scheduleProductDetailsCache(
            details: [ProductID("product-1"): .init(productId: "product-1", title: "Halo Infinite")]
        )
        await store.flushProductDetailsCache()

        let decoded = try JSONDecoder().decode(
            ProductDetailsDiskCacheSnapshot.self,
            from: Data(contentsOf: cacheRoot.appendingPathComponent("details.json"))
        )

        #expect(decoded.metadata.refreshSource == "product_details_cache")
        #expect(decoded.metadata.hydrationGeneration > 0)
    }

    @Test
    func nextHydrationGeneration_incrementsAcrossWrites() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )

        await store.scheduleProductDetailsCache(
            details: [ProductID("product-1"): .init(productId: "product-1", title: "One")]
        )
        await store.flushProductDetailsCache()
        let first = try JSONDecoder().decode(
            ProductDetailsDiskCacheSnapshot.self,
            from: Data(contentsOf: cacheRoot.appendingPathComponent("details.json"))
        )

        await store.scheduleProductDetailsCache(
            details: [ProductID("product-1"): .init(productId: "product-1", title: "Two")]
        )
        await store.flushProductDetailsCache()
        let second = try JSONDecoder().decode(
            ProductDetailsDiskCacheSnapshot.self,
            from: Data(contentsOf: cacheRoot.appendingPathComponent("details.json"))
        )

        #expect(second.metadata.hydrationGeneration > first.metadata.hydrationGeneration)
    }

    @Test
    func schedule_persistsRemainingPublicationStagesIntoSnapshotMetadata() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )
        let savedAt = Date(timeIntervalSince1970: 1_707_070_707)
        let sectionsSnapshot = LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: [TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: savedAt,
            isUnifiedHomeReady: true
        )
        let detailsSnapshot = LibraryHydrationPersistenceStore.makeProductDetailsSnapshot(
            details: [ProductID("product-1"): .init(productId: "product-1", title: "Halo Infinite")],
            savedAt: savedAt
        )
        let plan = LibraryHydrationPublicationPlan(stages: [.routeRestore, .visibleRows, .backgroundArtwork])
        let result = LibraryHydrationPublicationResult(completedStages: [.routeRestore, .visibleRows])

        await store.schedule(
            .unifiedSectionsAndProductDetails(
                sections: sectionsSnapshot,
                details: detailsSnapshot
            ),
            publicationPlan: plan,
            publicationResult: result
        )
        await store.flushUnifiedSectionsCache()
        await store.flushProductDetailsCache()

        let repository = try makeRepository(cacheRoot: cacheRoot)
        let decodedSections = try #require(await repository.loadUnifiedSectionsSnapshot())
        let decodedDetails = try JSONDecoder().decode(
            ProductDetailsDiskCacheSnapshot.self,
            from: Data(contentsOf: cacheRoot.appendingPathComponent("details.json"))
        )

        #expect(decodedSections.metadata.deferredStages == [.backgroundArtwork])
        #expect(decodedDetails.metadata.deferredStages == [.backgroundArtwork])
    }

    private func makeCacheRoot() throws -> URL {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-hydration-persistence-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        return cacheRoot
    }

    private func makeRepository(cacheRoot: URL) throws -> SwiftDataLibraryRepository {
        try SwiftDataLibraryRepository(
            storeURL: cacheRoot
                .appendingPathComponent("sections.json")
                .deletingPathExtension()
                .appendingPathExtension("swiftdata")
        )
    }
}
