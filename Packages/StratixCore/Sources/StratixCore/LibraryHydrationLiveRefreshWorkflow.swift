// LibraryHydrationLiveRefreshWorkflow.swift
// Defines library hydration live refresh workflow.
//

import Foundation
import StratixModels
import XCloudAPI

protocol LibraryHydrationLiveRefreshing: Sendable {
    @MainActor
    func run(
        request: LibraryHydrationRequest,
        controller: LibraryController
    ) async throws -> LibraryHydrationLiveFetchResult
}

@MainActor
struct LibraryHydrationLiveRefreshWorkflow: LibraryHydrationLiveRefreshing {
    func run(
        request: LibraryHydrationRequest,
        controller: LibraryController
    ) async throws -> LibraryHydrationLiveFetchResult {
        guard !controller.hydrationIsSuspendedForStreaming else {
            return LibraryHydrationLiveFetchResult(
                catalogState: LibraryHydrationCatalogState.liveFetch(
                    primaryTitlesResponse: XCloudTitlesResponse(results: []),
                    supplementaryResponses: [],
                    mruResponse: XCloudTitlesResponse(results: []),
                    existingSections: controller.sections
                ),
                committedSections: controller.sections,
                seededProductDetails: CatalogProductDetailsSeedState(
                    details: controller.productDetails,
                    upsertedCount: 0
                ),
                recoveryState: nil,
                merchandisingSnapshot: controller.homeMerchandising,
                merchandisingDiscovery: nil,
                hydratedCatalogProducts: [],
                hydratedProductCount: 0
            )
        }

        let tokens = try controller.authenticatedLibraryTokens()
        let tokenCandidates = controller.makeLibraryTokenCandidates(tokens: tokens)
        guard !tokenCandidates.isEmpty else { throw AuthError.noStreamToken }

        let xcloudCandidates = tokenCandidates.filter { $0.label != "xHome" }
        let xhomeCandidates = tokenCandidates.filter { $0.label == "xHome" }

        var workingXCloudTokens: [(label: String, token: String, preferredHost: String?)] = []
        var lastError: Error?

        for candidate in xcloudCandidates {
            guard !controller.hydrationIsSuspendedForStreaming else { throw CancellationError() }
            do {
                controller.hydrationInfo("Cloud library token validation: \(candidate.label)")
                _ = try await controller.resolveLibraryHost(
                    tokens: tokens,
                    gsToken: candidate.token,
                    preferredHost: candidate.preferredHost
                )
                workingXCloudTokens.append(candidate)
            } catch {
                lastError = error
                controller.hydrationWarning(
                    "Cloud library token validation failed (\(candidate.label)): \(controller.logString(for: error))"
                )
            }
        }

        if !workingXCloudTokens.isEmpty {
            let primary = workingXCloudTokens[0]
            let supplementary = Array(workingXCloudTokens.dropFirst())
            controller.hydrationInfo(
                "Cloud library building with primary=\(primary.label), supplementary=\(supplementary.map(\.label))"
            )
            return try await runFetch(
                controller: controller,
                tokens: tokens,
                gsToken: primary.token,
                preferredHost: primary.preferredHost,
                supplementaryCandidates: supplementary
            )
        }

        for candidate in xhomeCandidates {
            guard !controller.hydrationIsSuspendedForStreaming else { throw CancellationError() }
            do {
                controller.hydrationInfo("Cloud library token attempt: \(candidate.label)")
                return try await runFetch(
                    controller: controller,
                    tokens: tokens,
                    gsToken: candidate.token,
                    preferredHost: candidate.preferredHost,
                    supplementaryCandidates: []
                )
            } catch {
                lastError = error
                controller.hydrationWarning(
                    "Cloud library token attempt failed (\(candidate.label)): \(controller.logString(for: error))"
                )
            }
        }

        if let lastError { throw lastError }
        throw AuthError.invalidResponse("Cloud library token attempts produced no result.")
    }

    private func runFetch(
        controller: LibraryController,
        tokens: StreamTokens,
        gsToken: String,
        preferredHost: String?,
        supplementaryCandidates: [(label: String, token: String, preferredHost: String?)]
    ) async throws -> LibraryHydrationLiveFetchResult {
        let libraryHost = try await controller.resolveLibraryHost(
            tokens: tokens,
            gsToken: gsToken,
            preferredHost: preferredHost
        )
        controller.hydrationInfo("Cloud library host: \(libraryHost)")

        let xcloudClient = XCloudAPIClient(baseHost: libraryHost, gsToken: gsToken)
        let catalogClient = GamePassCatalogClient()

        async let titlesTask = xcloudClient.getCloudTitles()
        async let mruTask = xcloudClient.getCloudTitlesMRU(limit: LibraryController.hydrationConfig.mruLimit)

        let titlesResponse = try await titlesTask
        controller.hydrationInfo("Cloud library titles count: \(titlesResponse.results.count)")

        let mruResponse: XCloudTitlesResponse
        do {
            mruResponse = try await mruTask
            controller.hydrationInfo("Cloud library MRU count: \(mruResponse.results.count)")
        } catch {
            controller.hydrationWarning("Cloud library MRU failed: \(controller.logString(for: error))")
            mruResponse = XCloudTitlesResponse(results: [])
        }

        var supplementaryResponses: [(label: String, response: XCloudTitlesResponse)] = []
        supplementaryResponses.reserveCapacity(supplementaryCandidates.count)
        if !supplementaryCandidates.isEmpty {
            for supplementary in supplementaryCandidates {
                guard !controller.hydrationIsSuspendedForStreaming else { throw CancellationError() }
                do {
                    let supplementaryHost = try await controller.resolveLibraryHost(
                        tokens: tokens,
                        gsToken: supplementary.token,
                        preferredHost: supplementary.preferredHost
                    )
                    let supplementaryClient = XCloudAPIClient(
                        baseHost: supplementaryHost,
                        gsToken: supplementary.token
                    )
                    let response: XCloudTitlesResponse
                    if supplementary.label == "xCloudF2P" {
                        response = try await supplementaryClient.getCloudTitlesWithRawPayload().response
                    } else {
                        response = try await supplementaryClient.getCloudTitles()
                    }
                    supplementaryResponses.append((label: supplementary.label, response: response))
                } catch {
                    controller.hydrationWarning(
                        "Cloud library supplementary token fetch failed (\(supplementary.label)): \(controller.logString(for: error))"
                    )
                }
            }
        }

        let catalogState = LibraryHydrationCatalogState.liveFetch(
            primaryTitlesResponse: titlesResponse,
            supplementaryResponses: supplementaryResponses,
            mruResponse: mruResponse,
            existingSections: controller.sections
        )
        controller.hydrationInfo(
            "Cloud library entitled titles: \(catalogState.titles.count) / \(titlesResponse.results.count) total"
        )
        controller.hydrationDebug(
            "titles_primary entitled=\(catalogState.titles.count) raw=\(titlesResponse.results.count) sample=[\(controller.sampleHydrationTitleEntries(catalogState.titles))]"
        )
        for merge in catalogState.supplementaryMerges {
            controller.hydrationInfo(
                "Cloud library supplementary token added \(merge.addedTitles.count) new titles from \(merge.label) (total now: \(catalogState.titles.count))"
            )
            controller.hydrationDebug(
                "titles_supplementary source=\(merge.label) raw=\(merge.rawCount) added=\(merge.addedTitles.count) total=\(catalogState.titles.count) sample=[\(controller.sampleHydrationTitleEntries(merge.addedTitles))]"
            )
        }
        controller.hydrationDebug(
            "mru_selected source=\(catalogState.mruSource.rawValue) fetched=\(catalogState.fetchedMRUCount) final=\(catalogState.mruEntries.count) sample=[\(controller.sampleHydrationMRUEntries(catalogState.mruEntries))]"
        )

        let shapingResult = try await LibraryHydrationCatalogShapingWorkflow().shape(
            context: .init(
                existingSections: controller.sections,
                catalogState: catalogState,
                existingProductDetails: controller.productDetails,
                productDetailsCacheSizeLimit: LibraryController.productDetailsCacheSizeLimit,
                market: LibraryController.hydrationConfig.market,
                language: LibraryController.hydrationConfig.language,
                hydration: LibraryController.hydrationConfig.hydration,
                authorizationToken: gsToken
            ),
            dependencies: .init(
                isSuspendedForStreaming: { [weak controller] in
                    controller?.hydrationIsSuspendedForStreaming ?? true
                },
                hydrateProducts: { productIds, market, language, hydration, authorizationToken in
                    try await catalogClient.hydrateProducts(
                        productIds: productIds,
                        market: market,
                        language: language,
                        hydration: hydration,
                        authorizationToken: authorizationToken
                    )
                },
                makeSections: { titles, mruEntries, productMap, titleByProductId, titleByTitleId, productByXCloudTitleId, mruProductIds in
                    await LibraryShaper.makeCloudLibrarySectionsAsync(
                        titles: titles,
                        mruEntries: mruEntries,
                        productMap: productMap,
                        titleByProductId: titleByProductId,
                        titleByTitleId: titleByTitleId,
                        productByXCloudTitleId: productByXCloudTitleId,
                        mruProductIds: mruProductIds
                    )
                },
                logInfo: { [weak controller] message in
                    controller?.hydrationInfo(message)
                },
                logWarning: { [weak controller] message in
                    controller?.hydrationWarning(message)
                },
                logDebug: { [weak controller] message in
                    controller?.hydrationDebug(message)
                },
                describeSections: { [weak controller] sections in
                    controller?.describeHydrationSections(sections) ?? ""
                },
                sectionBreakdown: { [weak controller] sections in
                    controller?.hydrationSectionBreakdown(sections) ?? ""
                },
                missingTitleEntries: { [weak controller] titles, sections in
                    controller?.missingHydrationTitleEntries(expected: titles, from: sections) ?? []
                },
                sampleTitleEntries: { [weak controller] titles in
                    controller?.sampleHydrationTitleEntries(titles) ?? ""
                }
            )
        )

        let merchandisingResult = await controller.refreshHomeMerchandisingForHydration(
            latestSections: shapingResult.committedSections,
            market: LibraryController.hydrationConfig.market,
            language: LibraryController.hydrationConfig.language,
            forceDiscoveryRefresh: true
        )

        guard !controller.hydrationIsSuspendedForStreaming else {
            return LibraryHydrationLiveFetchResult(
                catalogState: shapingResult.catalogState,
                committedSections: shapingResult.committedSections,
                seededProductDetails: shapingResult.seededProductDetails,
                recoveryState: nil,
                merchandisingSnapshot: merchandisingResult.snapshot,
                merchandisingDiscovery: merchandisingResult.discovery,
                hydratedCatalogProducts: shapingResult.hydratedCatalogProducts,
                hydratedProductCount: shapingResult.hydratedProductCount
            )
        }

        controller.hydrationInfo(
            "Cloud library catalog returned product count: \(shapingResult.hydratedProductCount)"
        )
        controller.hydrationDebug(
            "home_snapshot_ready \(controller.describeHydrationHomeMerchandising(merchandisingResult.snapshot)) \(controller.describeHydrationDiscovery(merchandisingResult.discovery))"
        )

        let savedAt = Date()
        let liveFetchApplyState = LibraryHydrationLiveFetchApplyState.liveFetch(
            sections: shapingResult.committedSections,
            hydratedCatalogProducts: shapingResult.hydratedCatalogProducts,
            titleByProductId: shapingResult.catalogState.titleByProductId,
            existingProductDetails: controller.productDetails,
            homeMerchandising: merchandisingResult.snapshot,
            discovery: merchandisingResult.discovery,
            savedAt: savedAt,
            productDetailsCacheSizeLimit: LibraryController.productDetailsCacheSizeLimit
        )
        controller.hydrationDebug(
            "live_fetch_apply_state seededProductDetails=\(liveFetchApplyState.seededProductDetailCount) savedAtAge=\(controller.hydrationFormattedAge(savedAt)) \(controller.describeHydrationSections(shapingResult.committedSections)) \(controller.describeHydrationHomeMerchandising(merchandisingResult.snapshot)) \(controller.describeHydrationDiscovery(merchandisingResult.discovery))"
        )

        return LibraryHydrationLiveFetchResult(
            catalogState: shapingResult.catalogState,
            committedSections: shapingResult.committedSections,
            seededProductDetails: shapingResult.seededProductDetails,
            recoveryState: liveFetchApplyState.recoveryState,
            merchandisingSnapshot: merchandisingResult.snapshot,
            merchandisingDiscovery: merchandisingResult.discovery,
            hydratedCatalogProducts: shapingResult.hydratedCatalogProducts,
            hydratedProductCount: shapingResult.hydratedProductCount
        )
    }
}
