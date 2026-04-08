// LibraryMRUDeltaApplyWorkflowTests.swift
// Exercises library mru delta apply workflow behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing

@MainActor
@Suite(.serialized)
struct LibraryMRUDeltaApplyWorkflowTests {
    @Test
    func sectionsApplyingMRUDelta_rebuildsMRUSectionAndFlagsLibraryItems() {
        let sections = [
            TestHydrationFixtures.section(
                id: "mru",
                name: "Continue Playing",
                items: [TestHydrationFixtures.item(titleId: "title-stale", productId: "product-stale", isInMRU: true)]
            ),
            TestHydrationFixtures.section(
                id: "library",
                name: "Library",
                items: [
                    TestHydrationFixtures.item(titleId: "title-fresh", productId: "product-fresh"),
                    TestHydrationFixtures.item(titleId: "title-stale", productId: "product-stale", isInMRU: true),
                    TestHydrationFixtures.item(titleId: "title-other", productId: "product-other")
                ]
            )
        ]

        let result = LibraryController.sectionsApplyingMRUDelta(
            to: sections,
            liveMRUEntries: [
                LibraryMRUEntry(titleID: TitleID("title-fresh"), productID: ProductID("product-fresh")),
                LibraryMRUEntry(titleID: TitleID("title-fresh"), productID: ProductID("product-fresh"))
            ]
        )

        let appliedSections: [CloudLibrarySection]
        switch result {
        case .updated(let sections):
            appliedSections = sections
        default:
            Issue.record("Expected MRU delta to update sections.")
            return
        }

        #expect(appliedSections.first?.id == "mru")
        #expect(appliedSections.first?.items.map(\.titleId) == ["title-fresh"])

        let libraryItems = appliedSections.first(where: { $0.id == "library" })?.items ?? []
        #expect(libraryItems.first(where: { $0.titleId == "title-fresh" })?.isInMRU == true)
        #expect(libraryItems.first(where: { $0.titleId == "title-stale" })?.isInMRU == false)
        #expect(libraryItems.first(where: { $0.titleId == "title-other" })?.isInMRU == false)
    }

    @Test
    func applyPostStreamMRUDelta_returnsNoChangeWhenMRUAlreadyMatches() async {
        let controller = LibraryController()
        let sections = [
            TestHydrationFixtures.section(
                id: "mru",
                name: "Continue Playing",
                items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1", isInMRU: true)]
            ),
            TestHydrationFixtures.section(
                id: "library",
                name: "Library",
                items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1", isInMRU: true)]
            )
        ]
        controller.apply([
            .sectionsReplaced(sections),
            .homeMerchandisingSet(
                HomeMerchandisingSnapshot(
                    recentlyAddedItems: [],
                    rows: [],
                    generatedAt: Date()
                )
            ),
            .homeMerchandisingCompletionSet(true)
        ])

        let result = await controller.applyPostStreamMRUDelta(
            [LibraryMRUEntry(titleID: TitleID("title-1"), productID: ProductID("product-1"))],
            market: "US",
            language: "en-US"
        )

        #expect(result == .noChange)
    }
}
