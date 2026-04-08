// LibraryCachePersistenceTests.swift
// Exercises library cache persistence behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@MainActor
@Suite(.serialized)
struct LibraryCachePersistenceTests {
    @Test
    func saveCloudLibrarySectionsCache_skipsEmptySections() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let controller = makeController(cacheRoot: cacheRoot)
        controller.saveCloudLibrarySectionsCache(
            sections: [],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: Date(),
            isUnifiedHomeReady: false
        )
        await controller.flushSectionsCacheForTesting()

        let repository = try makeRepository(cacheRoot: cacheRoot)
        #expect(await repository.loadUnifiedSectionsSnapshot() == nil)
    }

    @Test
    func saveCloudLibrarySectionsCache_writesUnifiedSnapshot() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let controller = makeController(cacheRoot: cacheRoot)
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        controller.saveCloudLibrarySectionsCache(
            sections: [makeSection(titleId: "title-1", productId: "product-1")],
            homeMerchandising: HomeMerchandisingSnapshot(
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
            ),
            discovery: HomeMerchandisingDiscoveryCachePayload(
                entries: [
                    GamePassSiglDiscoveryEntry(
                        alias: "recently-added",
                        label: "Recently Added",
                        siglID: "sigl-recent",
                        source: .nextData
                    )
                ],
                savedAt: savedAt
            ),
            savedAt: savedAt,
            isUnifiedHomeReady: true
        )
        await controller.flushSectionsCacheForTesting()

        let repository = try makeRepository(cacheRoot: cacheRoot)
        let snapshot = await repository.loadUnifiedSectionsSnapshot()

        #expect(snapshot?.sections.map(\.id) == ["library"])
        #expect(snapshot?.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(snapshot?.discovery?.entries.map(\.alias) == ["recently-added"])
        #expect(snapshot?.isUnifiedHomeReady == true)
    }

    @Test
    func saveProductDetailsCache_writesLatestDetailsSnapshot() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let controller = makeController(cacheRoot: cacheRoot)
        controller.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "First"),
            primaryKey: "product-1"
        )
        controller.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "Latest"),
            primaryKey: "product-1"
        )
        controller.saveProductDetailsCache()
        await controller.flushProductDetailsCacheForTesting()

        let data = try Data(contentsOf: cacheRoot.appendingPathComponent("details.json"))
        let snapshot = try JSONDecoder().decode(ProductDetailsDiskCacheSnapshot.self, from: data)

        #expect(snapshot.details[ProductID("product-1")]?.title == "Latest")
    }

    @Test
    func flushSectionsCacheForTesting_waitsForScheduledWrite() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let controller = makeController(cacheRoot: cacheRoot)
        controller.saveCloudLibrarySectionsCache(
            sections: [makeSection(titleId: "title-1", productId: "product-1")],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: Date(),
            isUnifiedHomeReady: false
        )

        await controller.flushSectionsCacheForTesting()

        let repository = try makeRepository(cacheRoot: cacheRoot)
        #expect(await repository.loadUnifiedSectionsSnapshot() != nil)
    }

    @Test
    func flushProductDetailsCacheForTesting_waitsForScheduledWrite() async throws {
        let cacheRoot = try makeCacheRoot()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let controller = makeController(cacheRoot: cacheRoot)
        controller.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite"),
            primaryKey: "product-1"
        )
        controller.saveProductDetailsCache()

        await controller.flushProductDetailsCacheForTesting()

        #expect(FileManager.default.fileExists(atPath: cacheRoot.appendingPathComponent("details.json").path))
    }

    private func makeController(cacheRoot: URL) -> LibraryController {
        LibraryController(
            cacheLocations: .init(
                details: cacheRoot.appendingPathComponent("details.json"),
                sections: cacheRoot.appendingPathComponent("sections.json"),
                homeMerchandising: cacheRoot.appendingPathComponent("home.json")
            )
        )
    }

    private func makeCacheRoot() throws -> URL {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-cache-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        return cacheRoot
    }

    private func makeRepository(cacheRoot: URL) throws -> SwiftDataLibraryRepository {
        try SwiftDataLibraryRepository(
            storeURL: cacheRoot.appendingPathComponent("sections.swiftdata")
        )
    }

    private func makeSection(titleId: String, productId: String) -> CloudLibrarySection {
        CloudLibrarySection(
            id: "library",
            name: "Library",
            items: [makeItem(titleId: titleId, productId: productId)]
        )
    }

    private func makeItem(titleId: String, productId: String) -> CloudLibraryItem {
        CloudLibraryItem(
            titleId: titleId,
            productId: productId,
            name: "Test \(titleId)",
            shortDescription: nil,
            artURL: URL(string: "https://example.com/\(titleId).jpg"),
            supportedInputTypes: [],
            isInMRU: false
        )
    }
}
