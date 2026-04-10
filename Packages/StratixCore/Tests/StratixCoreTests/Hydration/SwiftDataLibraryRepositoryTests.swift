// SwiftDataLibraryRepositoryTests.swift
// Exercises swift data library repository behavior.
//

import Foundation
@testable import StratixCore
import Testing

@Suite(.serialized)
struct SwiftDataLibraryRepositoryTests {
    @Test
    func unifiedSectionsSnapshot_roundTripsThroughSwiftDataRepository() async throws {
        let repository = try SwiftDataLibraryRepository(isStoredInMemoryOnly: true)
        let savedAt = Date(timeIntervalSince1970: 1_717_171_717)
        let snapshot = LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: [TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: HomeMerchandisingSnapshot(
                recentlyAddedItems: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")],
                rows: [
                    HomeMerchandisingRow(
                        alias: "recently-added",
                        label: "Recently Added",
                        source: .fixedPriority,
                        items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")]
                    )
                ],
                generatedAt: savedAt
            ),
            discovery: HomeMerchandisingDiscoveryCachePayload(
                entries: [TestHydrationFixtures.discoveryEntry(alias: "recently-added", siglID: "sigl-recent")],
                savedAt: savedAt
            ),
            savedAt: savedAt,
            isUnifiedHomeReady: true
        )

        await repository.saveUnifiedSectionsSnapshot(snapshot)

        let decoded = try #require(await repository.loadUnifiedSectionsSnapshot())
        #expect(decoded.sections.map(\.id) == ["library"])
        #expect(decoded.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(decoded.discovery?.entries.map(\.alias) == ["recently-added"])
        #expect(decoded.isUnifiedHomeReady == true)
        #expect(decoded.savedAt == savedAt)
    }

    @Test
    func clearUnifiedSectionsCache_removesStoredSnapshot() async throws {
        let repository = try SwiftDataLibraryRepository(isStoredInMemoryOnly: true)
        let snapshot = LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: [TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: .now,
            isUnifiedHomeReady: false
        )

        await repository.saveUnifiedSectionsSnapshot(snapshot)
        #expect(await repository.loadUnifiedSectionsSnapshot() != nil)

        await repository.clearUnifiedSectionsCache()

        #expect(await repository.loadUnifiedSectionsSnapshot() == nil)
    }

    @Test
    func init_resetsUnreadablePersistentStoreAndRetries() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdata-library-repository-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let storeURL = cacheRoot.appendingPathComponent("sections.swiftdata")
        try Data("not a sqlite database".utf8).write(to: storeURL)
        try Data("stale wal".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
        try Data("stale shm".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-shm"))

        let repository = try SwiftDataLibraryRepository(storeURL: storeURL)
        let snapshot = LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: [TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: .now,
            isUnifiedHomeReady: false
        )

        await repository.saveUnifiedSectionsSnapshot(snapshot)

        let decoded = try #require(await repository.loadUnifiedSectionsSnapshot())
        #expect(decoded.sections.map(\.id) == ["library"])
        #expect(FileManager.default.fileExists(atPath: storeURL.path))
    }

    @Test
    func init_createsMissingParentDirectoriesBeforeOpeningStore() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdata-library-repository-parent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let storeURL = cacheRoot
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("sections.swiftdata")
        let repository = try SwiftDataLibraryRepository(storeURL: storeURL)
        let snapshot = LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: [TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: .now,
            isUnifiedHomeReady: false
        )

        await repository.saveUnifiedSectionsSnapshot(snapshot)

        let decoded = try #require(await repository.loadUnifiedSectionsSnapshot())
        #expect(decoded.sections.map(\.id) == ["library"])
        #expect(FileManager.default.fileExists(atPath: storeURL.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: storeURL.path))
    }
}
