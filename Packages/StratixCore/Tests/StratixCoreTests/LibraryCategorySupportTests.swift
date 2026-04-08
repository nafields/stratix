// LibraryCategorySupportTests.swift
// Exercises library category support behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels

struct LibraryCategorySupportTests {
    @Test
    func resolveCategoryItems_prefersIndexedMatchesAndDeduplicatesByTitleID() {
        let direct = makeItem(titleId: "title-1", productId: "product-1", name: "Direct")
        let fallback = makeItem(titleId: "legacy-title", productId: "legacy-product", name: "Fallback")

        let resolved = LibraryController.resolveCategoryItems(
            productIDs: ["product-1", "legacy-title", "product-1", "missing"],
            itemsByProductID: [ProductID("product-1"): direct],
            itemsByTitleID: [TitleID("legacy-title"): fallback]
        )

        #expect(resolved.map(\.productId) == ["product-1", "legacy-product"])
    }

    @Test
    func displayLabel_formatsKnownAliases() {
        #expect(LibraryController.displayLabel(for: "recently-added") == "Recently Added")
        #expect(LibraryController.displayLabel(for: "rpgs") == "RPGs")
        #expect(LibraryController.displayLabel(for: "ea-play") == "EA Play")
    }

    @Test
    func deduplicatePreservingOrder_keepsFirstTitleOccurrence() {
        let first = makeItem(titleId: "title-1", productId: "product-1", name: "First")
        let duplicate = makeItem(titleId: "title-1", productId: "product-2", name: "Duplicate")
        let second = makeItem(titleId: "title-2", productId: "product-3", name: "Second")

        let deduplicated = LibraryController.deduplicatePreservingOrder([first, duplicate, second])

        #expect(deduplicated.map(\.productId) == ["product-1", "product-3"])
    }

    @Test
    func normalizedCategoryProductKey_trimsAndLowercases() {
        #expect(LibraryController.normalizedCategoryProductKey("  Product-1 \n") == "product-1")
    }

    private func makeItem(titleId: String, productId: String, name: String) -> CloudLibraryItem {
        CloudLibraryItem(
            titleId: titleId,
            productId: productId,
            name: name,
            shortDescription: nil,
            artURL: URL(string: "https://example.com/\(titleId).jpg"),
            supportedInputTypes: [],
            isInMRU: false
        )
    }
}
