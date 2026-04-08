// LibraryHydrationMetadataTests.swift
// Exercises library hydration metadata behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

@Suite(.serialized)
struct LibraryHydrationMetadataTests {
    @Test
    func productDetailsSnapshot_encodesAndDecodesMetadata() throws {
        let savedAt = Date(timeIntervalSince1970: 1_702_020_202)
        let metadata = LibraryHydrationMetadata(
            snapshotID: UUID(),
            generatedAt: savedAt,
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
            market: "US",
            language: "en-US",
            refreshSource: "product_details_cache",
            hydrationGeneration: 42,
            homeReady: false,
            completenessBySectionID: [:]
        )
        let snapshot = ProductDetailsDiskCacheSnapshot(
            savedAt: savedAt,
            details: [ProductID("product-1"): .init(productId: "product-1", title: "Halo Infinite")],
            metadata: metadata
        )

        let decoded = try JSONDecoder().decode(
            ProductDetailsDiskCacheSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.metadata == metadata)
    }

    @Test
    func librarySectionsSnapshot_encodesAndDecodesMetadata() throws {
        let savedAt = Date(timeIntervalSince1970: 1_703_030_303)
        let snapshot = LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: [TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1")])],
            homeMerchandising: nil,
            discovery: nil,
            savedAt: savedAt,
            isUnifiedHomeReady: true,
            refreshSource: "unit_test"
        )

        let decoded = try JSONDecoder().decode(
            LibrarySectionsDiskCacheSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.metadata.refreshSource == "unit_test")
        #expect(decoded.metadata.homeReady == true)
    }

    @Test
    func legacySnapshotDecode_synthesizesCompatibilityMetadata() throws {
        let savedAt = Date(timeIntervalSince1970: 1_704_040_404)
        let legacy = """
        {
          "savedAt":"\(ISO8601DateFormatter().string(from: savedAt))",
          "details":{"product-1":{"productId":"product-1","title":"Halo Infinite"}},
          "cacheVersion":2
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(ProductDetailsDiskCacheSnapshot.self, from: legacy)

        #expect(decoded.metadata.refreshSource == "legacy_decode")
        #expect(decoded.metadata.hydrationGeneration == 0)
    }
}
