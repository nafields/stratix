// LibraryHydrationCatalogShapingWorkflowTests.swift
// Exercises library hydration catalog shaping workflow behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing
import XCloudAPI

@MainActor
@Suite(.serialized)
struct LibraryHydrationCatalogShapingWorkflowTests {
    @Test
    func shape_batchesProducts_andBuildsTypedFetchResult() async throws {
        actor Recorder {
            var batchSizes: [Int] = []
            func record(_ size: Int) { batchSizes.append(size) }
        }

        let recorder = Recorder()
        let titleDTOs = (1...101).map { index in
            TestHydrationFixtures.titleDTO(
                titleId: "title-\(index)",
                productId: "product-\(index)",
                name: "Game \(index)",
                entitled: true
            )
        }
        let catalogState = LibraryHydrationCatalogState.liveFetch(
            primaryTitlesResponse: TestHydrationFixtures.titlesResponse(titleDTOs),
            supplementaryResponses: [],
            mruResponse: XCloudTitlesResponse(results: []),
            existingSections: []
        )

        let result = try await LibraryHydrationCatalogShapingWorkflow().shape(
            context: .init(
                existingSections: [],
                catalogState: catalogState,
                existingProductDetails: [:],
                productDetailsCacheSizeLimit: 10,
                market: "US",
                language: "en-US",
                hydration: "test",
                authorizationToken: "token"
            ),
            dependencies: .init(
                isSuspendedForStreaming: { false },
                hydrateProducts: { productIds, _, _, _, _ in
                    await recorder.record(productIds.count)
                    return productIds.map { productId in
                        let index = Int(productId.replacingOccurrences(of: "product-", with: "")) ?? 0
                        return TestHydrationFixtures.catalogProduct(
                            productId: productId,
                            title: "Game \(index)",
                            shortDescription: "Description \(index)"
                        )
                    }
                },
                makeSections: { _, _, productMap, titleByProductId, _, _, _ in
                    let items = titleByProductId.values
                        .sorted { $0.titleId < $1.titleId }
                        .compactMap { title -> CloudLibraryItem? in
                            guard productMap[title.productId] != nil else { return nil }
                            return TestHydrationFixtures.item(
                                titleId: title.titleId,
                                productId: title.productId
                            )
                        }
                    return [TestHydrationFixtures.section(items: items)]
                },
                logInfo: { _ in },
                logWarning: { _ in },
                logDebug: { _ in },
                describeSections: { sections in
                    "titles=\(LibraryController.libraryTitleCount(in: sections))"
                },
                sectionBreakdown: { sections in
                    sections.map { "\($0.id):\($0.items.count)" }.joined(separator: ",")
                },
                missingTitleEntries: { expected, sections in
                    let shapedTitleIDs = Set(LibraryController.allLibraryItems(from: sections).map(\.titleId))
                    return expected.filter { !shapedTitleIDs.contains($0.titleId) }
                },
                sampleTitleEntries: { titles in
                    titles.prefix(3).map(\.titleId).joined(separator: ",")
                }
            )
        )

        let batchSizes = await recorder.batchSizes
        #expect(batchSizes.sorted() == [1, 100])
        #expect(LibraryController.libraryTitleCount(in: result.committedSections) == 101)
        #expect(result.hydratedProductCount == 101)
        #expect(result.catalogState.expectedLibraryTitleCount == 101)
    }
}
