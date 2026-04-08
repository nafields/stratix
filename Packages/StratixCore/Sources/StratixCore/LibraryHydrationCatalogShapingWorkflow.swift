// LibraryHydrationCatalogShapingWorkflow.swift
// Defines library hydration catalog shaping workflow.
//

import Foundation
import StratixModels
import XCloudAPI

@MainActor
struct LibraryHydrationCatalogShapingWorkflow {
    struct Context: Sendable {
        let existingSections: [CloudLibrarySection]
        let catalogState: LibraryHydrationCatalogState
        let existingProductDetails: [ProductID: CloudLibraryProductDetail]
        let productDetailsCacheSizeLimit: Int
        let market: String
        let language: String
        let hydration: String
        let authorizationToken: String
    }

    struct Dependencies {
        let isSuspendedForStreaming: () -> Bool
        let hydrateProducts: @Sendable (
            _ productIds: [String],
            _ market: String,
            _ language: String,
            _ hydration: String,
            _ authorizationToken: String
        ) async throws -> [GamePassCatalogClient.CatalogProduct]
        let makeSections: @Sendable (
            _ titles: [TitleEntry],
            _ mruEntries: [LibraryMRUEntry],
            _ productMap: [String: GamePassCatalogClient.CatalogProduct],
            _ titleByProductId: [ProductID: TitleEntry],
            _ titleByTitleId: [TitleID: TitleEntry],
            _ productByXCloudTitleId: [String: GamePassCatalogClient.CatalogProduct],
            _ mruProductIds: Set<ProductID>
        ) async -> [CloudLibrarySection]
        let logInfo: (String) -> Void
        let logWarning: (String) -> Void
        let logDebug: (String) -> Void
        let describeSections: ([CloudLibrarySection]) -> String
        let sectionBreakdown: ([CloudLibrarySection]) -> String
        let missingTitleEntries: (_ expected: [TitleEntry], _ sections: [CloudLibrarySection]) -> [TitleEntry]
        let sampleTitleEntries: ([TitleEntry]) -> String
    }

    func shape(
        context: Context,
        dependencies: Dependencies
    ) async throws -> LibraryHydrationLiveFetchResult {
        let titles = context.catalogState.titles
        dependencies.logInfo("Cloud library catalog hydrate product count: \(context.catalogState.allProductIds.count)")

        if !context.catalogState.duplicateTitleIds.isEmpty {
            dependencies.logWarning("Cloud library duplicate titleId entries ignored: \(context.catalogState.duplicateTitleIds.count)")
        }

        if !context.existingSections.isEmpty {
            let currentCount = context.existingSections.reduce(0) { $0 + $1.items.count }
            dependencies.logInfo("Cloud library refresh preserving existing view state (\(currentCount) visible title(s))")
        }

        var productMap: [String: GamePassCatalogClient.CatalogProduct] = [:]
        var productByXCloudTitleId: [String: GamePassCatalogClient.CatalogProduct] = [:]

        let initialSections = await dependencies.makeSections(
            titles,
            context.catalogState.mruEntries,
            productMap,
            context.catalogState.titleByProductId,
            context.catalogState.titleByTitleId,
            productByXCloudTitleId,
            context.catalogState.mruProductIds
        )
        dependencies.logDebug(
            "shape_initial expectedTitles=\(context.catalogState.expectedLibraryTitleCount) \(dependencies.describeSections(initialSections))"
        )

        var committedSections = initialSections
        let batches = context.catalogState.allProductIds.chunked(into: 100)
        var hydratedCatalogProducts: [GamePassCatalogClient.CatalogProduct] = []
        var completedBatches = 0
        let hydrateProducts = dependencies.hydrateProducts
        let market = context.market
        let language = context.language
        let hydration = context.hydration
        let authorizationToken = context.authorizationToken

        try await withThrowingTaskGroup(
            of: [GamePassCatalogClient.CatalogProduct].self,
            returning: Void.self
        ) { group in
            for batch in batches {
                guard !dependencies.isSuspendedForStreaming() else {
                    group.cancelAll()
                    return
                }

                group.addTask {
                    try await hydrateProducts(
                        batch.map(\.rawValue),
                        market,
                        language,
                        hydration,
                        authorizationToken
                    )
                }
            }

            for try await catalogProducts in group {
                guard !dependencies.isSuspendedForStreaming() else {
                    group.cancelAll()
                    return
                }

                completedBatches += 1
                hydratedCatalogProducts.append(contentsOf: catalogProducts)

                for product in catalogProducts {
                    productMap[product.ProductId] = product
                    if let storeId = product.StoreId, !storeId.isEmpty {
                        productMap[storeId] = product
                    }
                    if let xCloudTitleId = product.XCloudTitleId, !xCloudTitleId.isEmpty {
                        productByXCloudTitleId[xCloudTitleId] = product
                    }
                }

                let candidateSections = await dependencies.makeSections(
                    titles,
                    context.catalogState.mruEntries,
                    productMap,
                    context.catalogState.titleByProductId,
                    context.catalogState.titleByTitleId,
                    productByXCloudTitleId,
                    context.catalogState.mruProductIds
                )

                let committedBefore = LibraryController.libraryTitleCount(in: committedSections)
                let candidateCount = LibraryController.libraryTitleCount(in: candidateSections)
                let preferredSections = LibraryController.preferredHydrationSections(
                    currentBest: committedSections,
                    candidate: candidateSections
                )
                let committedAfter = LibraryController.libraryTitleCount(in: preferredSections)

                if candidateCount < committedBefore {
                    dependencies.logWarning(
                        "shape_batch_shrank batch=\(completedBatches)/\(batches.count) hydratedProducts=\(hydratedCatalogProducts.count) candidateTitles=\(candidateCount) committedBefore=\(committedBefore) committedAfter=\(committedAfter) candidateBreakdown=[\(dependencies.sectionBreakdown(candidateSections))]"
                    )
                } else {
                    dependencies.logDebug(
                        "shape_batch batch=\(completedBatches)/\(batches.count) hydratedProducts=\(hydratedCatalogProducts.count) candidateTitles=\(candidateCount) committedBefore=\(committedBefore) committedAfter=\(committedAfter) candidateBreakdown=[\(dependencies.sectionBreakdown(candidateSections))]"
                    )
                }

                committedSections = preferredSections
            }
        }

        let committedLibraryTitleCount = LibraryController.libraryTitleCount(in: committedSections)
        let missingTitles = dependencies.missingTitleEntries(titles, committedSections)
        if committedLibraryTitleCount < context.catalogState.expectedLibraryTitleCount {
            dependencies.logWarning(
                "Cloud library hydration kept fullest snapshot but still missing titles: expected=\(context.catalogState.expectedLibraryTitleCount) shaped=\(committedLibraryTitleCount)"
            )
            dependencies.logWarning(
                "shape_final_missing expected=\(context.catalogState.expectedLibraryTitleCount) shaped=\(committedLibraryTitleCount) missing=\(missingTitles.count) missingSample=[\(dependencies.sampleTitleEntries(missingTitles))] \(dependencies.describeSections(committedSections))"
            )
        } else {
            dependencies.logDebug(
                "shape_final expected=\(context.catalogState.expectedLibraryTitleCount) shaped=\(committedLibraryTitleCount) \(dependencies.describeSections(committedSections))"
            )
        }

        return LibraryHydrationLiveFetchResult(
            catalogState: context.catalogState,
            committedSections: committedSections,
            seededProductDetails: CatalogProductDetailHydrator.seededProductDetails(
                products: hydratedCatalogProducts,
                titleByProductId: context.catalogState.titleByProductId,
                existingProductDetails: context.existingProductDetails,
                cacheSizeLimit: context.productDetailsCacheSizeLimit
            ),
            recoveryState: nil,
            merchandisingSnapshot: nil,
            merchandisingDiscovery: nil,
            hydratedCatalogProducts: hydratedCatalogProducts,
            hydratedProductCount: hydratedCatalogProducts.count
        )
    }
}
