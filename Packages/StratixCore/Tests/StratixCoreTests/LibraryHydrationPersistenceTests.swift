// LibraryHydrationPersistenceTests.swift
// Exercises library hydration persistence behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@Suite(.serialized)
struct LibraryHydrationPersistenceTests {
    @Test
    func persistenceStore_writesUnifiedSectionsSnapshot() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )
        let savedAt = Date()
        let section = makeSection(
            id: "library",
            name: "Library",
            items: [makeItem(titleId: "title-1", productId: "product-1")]
        )
        let merchandising = HomeMerchandisingSnapshot(
            recentlyAddedItems: [makeItem(titleId: "title-1", productId: "product-1")],
            rows: [
                HomeMerchandisingRow(
                    alias: "recently-added",
                    label: "Recently Added",
                    source: .fixedPriority,
                    items: [makeItem(titleId: "title-1", productId: "product-1")]
                )
            ],
            generatedAt: savedAt
        )
        let discovery = HomeMerchandisingDiscoveryCachePayload(
            entries: [
                GamePassSiglDiscoveryEntry(
                    alias: "recently-added",
                    label: "Recently Added",
                    siglID: "sigl-recent",
                    source: .nextData
                )
            ],
            savedAt: savedAt
        )

        await store.scheduleUnifiedSectionsCache(
            sections: [section],
            homeMerchandising: merchandising,
            discovery: discovery,
            savedAt: savedAt,
            isUnifiedHomeReady: true
        )
        await store.flushUnifiedSectionsCache()

        let repository = try makeRepository(cacheRoot: cacheRoot)
        let snapshot = await repository.loadUnifiedSectionsSnapshot()

        #expect(snapshot?.sections.map(\.id) == ["library"])
        #expect(snapshot?.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(snapshot?.discovery?.entries.map(\.alias) == ["recently-added"])
        #expect(snapshot?.isUnifiedHomeReady == true)
        #expect(snapshot?.cacheVersion == LibraryHydrationCacheSchema.currentCacheVersion)
    }

    @Test
    func persistenceStore_schedulesVersionedProductDetailsSnapshot() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )

        await store.scheduleProductDetailsCache(
            details: [
                ProductID("product-1"): CloudLibraryProductDetail(
                    productId: "product-1",
                    title: "Halo Infinite"
                )
            ]
        )
        await store.flushProductDetailsCache()

        let data = try Data(contentsOf: cacheRoot.appendingPathComponent("details.json"))
        let snapshot = try JSONDecoder().decode(ProductDetailsDiskCacheSnapshot.self, from: data)

        #expect(snapshot.details[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(snapshot.cacheVersion == LibraryHydrationCacheSchema.currentCacheVersion)
    }

    @Test
    func persistenceStore_latestUnifiedSectionsSnapshotWins() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )

        await store.scheduleUnifiedSectionsCache(
            sections: [makeSection(id: "first", name: "First", items: [makeItem(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: .now.addingTimeInterval(-60),
            isUnifiedHomeReady: false
        )
        await store.scheduleUnifiedSectionsCache(
            sections: [makeSection(id: "second", name: "Second", items: [makeItem(titleId: "title-2", productId: "product-2")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: .now,
            isUnifiedHomeReady: true
        )
        await store.flushUnifiedSectionsCache()

        let repository = try makeRepository(cacheRoot: cacheRoot)
        let snapshot = await repository.loadUnifiedSectionsSnapshot()

        #expect(snapshot?.sections.map(\.id) == ["second"])
        #expect(snapshot?.isUnifiedHomeReady == true)
    }

    @Test
    func persistenceStore_scheduleIntent_writesCombinedSnapshots() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let store = LibraryHydrationPersistenceStore(
            detailsURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsURL: cacheRoot.appendingPathComponent("sections.json")
        )
        let savedAt = Date()
        let sectionsSnapshot = LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: [makeSection(id: "library", name: "Library", items: [makeItem(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: savedAt,
            isUnifiedHomeReady: false
        )
        let detailsSnapshot = ProductDetailsDiskCacheSnapshot(
            savedAt: savedAt,
            details: [ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")]
        )

        await store.schedule(.unifiedSectionsAndProductDetails(sections: sectionsSnapshot, details: detailsSnapshot))
        await store.flushUnifiedSectionsCache()
        await store.flushProductDetailsCache()

        let repository = try makeRepository(cacheRoot: cacheRoot)
        let detailsData = try Data(contentsOf: cacheRoot.appendingPathComponent("details.json"))
        let decodedSections = await repository.loadUnifiedSectionsSnapshot()
        let decodedDetails = try JSONDecoder().decode(ProductDetailsDiskCacheSnapshot.self, from: detailsData)

        #expect(decodedSections?.sections.map(\.id) == ["library"])
        #expect(decodedDetails.details[ProductID("product-1")]?.title == "Halo Infinite")
    }

    private func makeCacheRoot() throws -> URL {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-hydration-persistence-\(UUID().uuidString)", isDirectory: true)
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

    private func makeSection(
        id: String,
        name: String,
        items: [CloudLibraryItem]
    ) -> CloudLibrarySection {
        CloudLibrarySection(id: id, name: name, items: items)
    }

    private func makeItem(titleId: String, productId: String) -> CloudLibraryItem {
        CloudLibraryItem(
            titleId: titleId,
            productId: productId,
            name: "Test \(titleId)",
            shortDescription: nil,
            artURL: URL(string: "https://example.com/\(titleId).jpg"),
            supportedInputTypes: ["controller"],
            isInMRU: false
        )
    }
}
