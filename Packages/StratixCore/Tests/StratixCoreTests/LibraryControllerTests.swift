// LibraryControllerTests.swift
// Exercises library controller behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@MainActor
@Suite(.serialized)
struct LibraryControllerTests {
    @Test
    func librarySnapshot_readsCanonicalState() async {
        let item = makeItem(titleId: "title-1", productId: "product-1")
        let section = makeSection(id: "library", name: "Library", items: [item])
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
        let home = HomeMerchandisingSnapshot(
            recentlyAddedItems: [],
            rows: [],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let state = LibraryState(
            sections: [section],
            itemsByTitleID: [TitleID("title-1"): item],
            itemsByProductID: [ProductID("product-1"): item],
            productDetails: [ProductID("product-1"): detail],
            isLoading: true,
            lastError: "boom",
            needsReauth: true,
            lastHydratedAt: nil,
            cacheSavedAt: nil,
            isArtworkPrefetchThrottled: false,
            homeMerchandising: home,
            discoveryEntries: [],
            isHomeMerchandisingLoading: true,
            hasCompletedInitialHomeMerchandising: true,
            homeMerchandisingSessionSource: .liveRecovery,
            hasRecoveredLiveHomeMerchandisingThisSession: false,
            catalogRevision: 1,
            detailRevision: 2,
            homeRevision: 3,
            sceneContentRevision: 4
        )
        let controller = LibraryController(initialState: state)

        let snapshot = await controller.librarySnapshot()

        #expect(snapshot.sections == state.sections)
        #expect(snapshot.productDetails == state.productDetails)
        #expect(snapshot.isLoading == state.isLoading)
        #expect(snapshot.homeMerchandising == state.homeMerchandising)
        #expect(snapshot.isHomeMerchandisingLoading == state.isHomeMerchandisingLoading)
        #expect(snapshot.hasCompletedInitialHomeMerchandising == state.hasCompletedInitialHomeMerchandising)
        #expect(snapshot.lastError == state.lastError)
        #expect(snapshot.needsReauth == state.needsReauth)
    }

    @Test
    func typedLookupAPIs_readCanonicalStateByTitleAndProductID() {
        let item = makeItem(titleId: "title-1", productId: "product-1")
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
        let controller = LibraryController(
            initialState: LibraryState(
                sections: [makeSection(id: "library", name: "Library", items: [item])],
                itemsByTitleID: [TitleID("title-1"): item],
                itemsByProductID: [ProductID("product-1"): item],
                productDetails: [ProductID("product-1"): detail],
                isLoading: false,
                lastError: nil,
                needsReauth: false,
                lastHydratedAt: nil,
                cacheSavedAt: nil,
                isArtworkPrefetchThrottled: false,
                homeMerchandising: nil,
                discoveryEntries: [],
                isHomeMerchandisingLoading: false,
                hasCompletedInitialHomeMerchandising: false,
                homeMerchandisingSessionSource: .none,
                hasRecoveredLiveHomeMerchandisingThisSession: false,
                catalogRevision: 1,
                detailRevision: 1,
                homeRevision: 0,
                sceneContentRevision: 1
            )
        )

        #expect(controller.item(titleID: TitleID("title-1"))?.productId == "product-1")
        #expect(controller.item(productID: ProductID("product-1"))?.titleId == "title-1")
        #expect(controller.productDetail(productID: ProductID("product-1"))?.title == "Halo Infinite")
    }

    @Test
    func productDetailsCache_roundTripsVersionedSnapshot() async {
        clearDetailsCacheFile()
        defer { clearDetailsCacheFile() }

        let source = LibraryController()
        source.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite"),
            primaryKey: "PRODUCT-1"
        )
        await source.flushProductDetailsCacheForTesting()
        await waitForCacheFile(LibraryController.detailsCacheURL)

        let restored = LibraryController()
        await restored.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(restored.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
    }

    @Test
    func productDetailsCache_legacyUnversionedSnapshotIsIgnored() async throws {
        clearDetailsCacheFile()
        defer { clearDetailsCacheFile() }

        let legacyDetails = [
            "product-1": CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
        ]
        let data = try JSONEncoder().encode(legacyDetails)
        try data.write(to: LibraryController.detailsCacheURL, options: .atomic)

        let restored = LibraryController()
        await restored.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(restored.productDetails.isEmpty)
    }

    @Test
    func productDetailsCache_burstWritesCollapseToLatestSnapshot() async throws {
        clearDetailsCacheFile()
        defer { clearDetailsCacheFile() }

        let source = LibraryController()
        source.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "First"),
            primaryKey: "product-1"
        )
        source.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "Latest"),
            primaryKey: "product-1"
        )
        await source.flushProductDetailsCacheForTesting()

        let data = try Data(contentsOf: LibraryController.detailsCacheURL)
        let snapshot = try JSONDecoder().decode(ProductDetailsDiskCacheSnapshot.self, from: data)

        #expect(snapshot.details[ProductID("product-1")]?.title == "Latest")
    }

    @Test
    func sceneContentRevision_advancesForContentMutations() {
        let controller = LibraryController()
        let initialRevision = controller.sceneContentRevision

        controller.apply(
            .sectionsReplaced([
                makeSection(
                    id: "library",
                    name: "Library",
                    items: [makeItem(titleId: "title-1", productId: "product-1")]
                )
            ])
        )
        #expect(controller.sceneContentRevision == initialRevision + 1)

        controller.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite"),
            primaryKey: "PRODUCT-1"
        )
        #expect(controller.sceneContentRevision == initialRevision + 2)
    }

    @Test
    func restoreDiskCachesIfNeeded_restoresDetailsAndUnifiedSectionsTogether() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-details-and-sections-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let cacheLocations = LibraryController.CacheLocations(
            details: cacheRoot.appendingPathComponent("details.json"),
            sections: cacheRoot.appendingPathComponent("sections.json"),
            homeMerchandising: cacheRoot.appendingPathComponent("home.json")
        )

        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                siglID == "sigl-recent" ? ["product-1"] : []
            }
        )
        let source = LibraryController(
            cacheLocations: cacheLocations,
            homeMerchandisingSIGLProvider: provider
        )
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1")]
            )
        ]

        source.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite"),
            primaryKey: "product-1"
        )
        source.apply(.sectionsReplaced(sections))
        await source.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )
        await source.flushProductDetailsCacheForTesting()
        await waitForCacheFile(cacheLocations.details)
        source.saveCloudLibrarySectionsCache()
        await source.flushSectionsCacheForTesting()
        await waitForCacheFile(cacheLocations.repository)

        let restored = LibraryController(cacheLocations: cacheLocations)
        await restored.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(restored.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(restored.sections.map(\.id) == ["library"])
        #expect(restored.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(restored.hasCompletedInitialHomeMerchandising == true)
        #expect(restored.homeMerchandisingSessionSource == .cacheRestore)
        #expect(restored.hasRecoveredLiveHomeMerchandisingThisSession == false)
        #expect(restored.hasRecoveredLiveHomeMerchandisingThisSession == false)
    }

    @Test
    func hydrationWorker_decodesUnifiedSectionsSnapshotIntoTypedPayload() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-hydration-worker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let sectionsURL = cacheRoot.appendingPathComponent("sections.json")
        let snapshot = makeUnifiedSectionsSnapshot(savedAt: Date())
        let repository = try SwiftDataLibraryRepository(storeURL: sectionsURL)
        await repository.saveUnifiedSectionsSnapshot(snapshot)

        let worker = LibraryHydrationWorker(
            detailsCacheURL: cacheRoot.appendingPathComponent("details.json"),
            sectionsCacheURL: sectionsURL,
            homeMerchandisingCacheURL: cacheRoot.appendingPathComponent("home.json")
        )

        let payload = await worker.loadStartupCachePayload(
            loadProductDetails: false,
            loadSections: true
        )

        #expect(payload.sectionsSnapshot?.sections.map(\.id) == ["library"])
        #expect(payload.sectionsSnapshot?.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(payload.sectionsSnapshot?.discovery?.entries.map(\.alias) == ["recently-added"])
        #expect(payload.sectionsSnapshot?.isUnifiedHomeReady == true)
    }

    @Test
    func hydrationPublishedState_cacheRestoreUsesCacheRestoreMetadata() {
        let savedAt = Date(timeIntervalSince1970: 1_717_171_717)
        let snapshot = makeDecodedUnifiedSectionsSnapshot(savedAt: savedAt)

        let publishedState = LibraryHydrationPublishedState.cacheRestore(snapshot: snapshot)

        #expect(publishedState.source == .cacheRestore)
        #expect(publishedState.sessionSource == .cacheRestore)
        #expect(publishedState.savedAt == savedAt)
        #expect(publishedState.sections.map(\.id) == ["library"])
        #expect(publishedState.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(publishedState.discovery?.entries.map(\.alias) == ["recently-added"])
        #expect(publishedState.isUnifiedHomeReady == true)
    }

    @Test
    func hydrationPublishedState_liveRecoveryUsesLiveRecoveryMetadata() throws {
        let savedAt = Date(timeIntervalSince1970: 1_818_181_818)
        let snapshot = makeDecodedUnifiedSectionsSnapshot(savedAt: savedAt)
        let merchandising = try #require(snapshot.homeMerchandising)
        let discovery = try #require(snapshot.discovery)

        let publishedState = LibraryHydrationPublishedState.liveRecovery(
            sections: snapshot.sections,
            homeMerchandising: merchandising,
            discovery: discovery,
            savedAt: savedAt
        )

        #expect(publishedState.source == LibraryHydrationPublishedState.Source.liveRecovery)
        #expect(publishedState.sessionSource == HomeMerchandisingSessionSource.liveRecovery)
        #expect(publishedState.savedAt == savedAt)
        #expect(publishedState.sections.map { $0.id } == ["library"])
        #expect(publishedState.homeMerchandising?.rows.map { $0.alias } == ["recently-added"])
        #expect(publishedState.discovery?.entries.map { $0.alias } == ["recently-added"])
        #expect(publishedState.isUnifiedHomeReady == true)
    }

    @Test
    func hydrationProductDetailsState_cacheRestorePrefersRicherIncomingDetails() {
        let existing = CloudLibraryProductDetail(
            productId: "product-1",
            title: "Halo Infinite"
        )
        let richerIncoming = CloudLibraryProductDetail(
            productId: "product-1",
            title: "Halo Infinite",
            galleryImageURLs: [URL(string: "https://example.com/gallery.jpg")!]
        )

        let state = LibraryHydrationProductDetailsState.cacheRestore(
            details: [ProductID("product-1"): richerIncoming],
            existing: [ProductID("product-1"): existing]
        )

        #expect(state.source == LibraryHydrationProductDetailsState.Source.cacheRestore)
        #expect(state.shouldPersist == false)
        #expect(state.restoredCount == 1)
        #expect(state.details[ProductID("product-1")]?.galleryImageURLs.count == 1)
    }

    @Test
    func hydrationProductDetailsState_liveRecoveryRequestsPersistence() {
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")

        let state = LibraryHydrationProductDetailsState.liveRecovery(
            details: [ProductID("product-1"): detail]
        )

        #expect(state.source == LibraryHydrationProductDetailsState.Source.liveRecovery)
        #expect(state.shouldPersist == true)
        #expect(state.restoredCount == 1)
        #expect(state.details[ProductID("product-1")]?.title == "Halo Infinite")
    }

    @Test
    func hydrationRecoveryState_liveRecoveryPersistsUnifiedSnapshotAndProductDetails() throws {
        let savedAt = Date(timeIntervalSince1970: 1_919_191_919)
        let snapshot = makeDecodedUnifiedSectionsSnapshot(savedAt: savedAt)
        let merchandising = try #require(snapshot.homeMerchandising)
        let discovery = try #require(snapshot.discovery)
        let detail = CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")

        let state = LibraryHydrationRecoveryState.liveRecovery(
            sections: snapshot.sections,
            productDetails: [ProductID("product-1"): detail],
            homeMerchandising: merchandising,
            discovery: discovery,
            savedAt: savedAt
        )

        #expect(state.shouldPersistUnifiedSnapshot == true)
        #expect(state.publishedState.source == .liveRecovery)
        #expect(state.publishedState.sections.map(\.id) == ["library"])
        #expect(state.productDetailsState?.shouldPersist == true)
        #expect(state.productDetailsState?.details[ProductID("product-1")]?.title == "Halo Infinite")
    }

    @Test
    func hydrationRecoveryState_postStreamDeltaOmitsProductDetailsButPersistsPublishedState() throws {
        let savedAt = Date(timeIntervalSince1970: 2_020_202_020)
        let snapshot = makeDecodedUnifiedSectionsSnapshot(savedAt: savedAt)
        let merchandising = try #require(snapshot.homeMerchandising)
        let discovery = try #require(snapshot.discovery)

        let state = LibraryHydrationRecoveryState.postStreamDelta(
            sections: snapshot.sections,
            homeMerchandising: merchandising,
            discovery: discovery,
            savedAt: savedAt
        )

        #expect(state.shouldPersistUnifiedSnapshot == true)
        #expect(state.publishedState.source == .liveRecovery)
        #expect(state.productDetailsState == nil)
        #expect(state.publishedState.discovery?.entries.map(\.alias) == ["recently-added"])
    }

    @Test
    func hydrationCatalogState_mergesSupplementaryTitlesWithoutDuplicateTitleIDs() {
        let state = LibraryHydrationCatalogState.liveFetch(
            primaryTitlesResponse: makeTitlesResponse([
                makeTitleDTO(titleId: "title-primary", productId: "product-primary", name: "Primary", entitled: true),
                makeTitleDTO(titleId: "title-no-entitlement", productId: "product-no-entitlement", name: "Skip", entitled: false)
            ]),
            supplementaryResponses: [
                (
                    label: "xCloudF2P",
                    response: makeTitlesResponse([
                        makeTitleDTO(titleId: "title-primary", productId: "product-primary", name: "Primary Duplicate", entitled: true),
                        makeTitleDTO(titleId: "title-f2p", productId: "product-f2p", name: "Free To Play", entitled: true)
                    ])
                )
            ],
            mruResponse: XCloudTitlesResponse(results: []),
            existingSections: []
        )

        #expect(state.titles.map(\.titleId) == ["title-primary", "title-f2p"])
        #expect(state.expectedLibraryTitleCount == 2)
        #expect(state.supplementaryMerges.map(\.label) == ["xCloudF2P"])
        #expect(state.supplementaryMerges.first?.addedTitles.map(\.titleId) == ["title-f2p"])
        #expect(state.duplicateTitleIds.isEmpty)
    }

    @Test
    func hydrationCatalogState_fallsBackToCachedMRUWhenLiveMRUIsEmpty() {
        let state = LibraryHydrationCatalogState.liveFetch(
            primaryTitlesResponse: makeTitlesResponse([
                makeTitleDTO(titleId: "title-cached", productId: "product-cached", name: "Cached", entitled: true),
                makeTitleDTO(titleId: "title-library", productId: "product-library", name: "Library", entitled: true)
            ]),
            supplementaryResponses: [],
            mruResponse: XCloudTitlesResponse(results: []),
            existingSections: [
                makeSection(
                    id: "mru",
                    name: "Continue Playing",
                    items: [makeItem(titleId: "title-cached", productId: "product-cached", isInMRU: true)]
                ),
                makeSection(
                    id: "library",
                    name: "Library",
                    items: [
                        makeItem(titleId: "title-cached", productId: "product-cached", isInMRU: true),
                        makeItem(titleId: "title-library", productId: "product-library")
                    ]
                )
            ]
        )

        #expect(state.mruSource == .fallback)
        #expect(state.fetchedMRUCount == 0)
        #expect(state.mruEntries.map(\.titleId) == ["title-cached"])
        #expect(state.mruEntries.map(\.productId) == ["product-cached"])
    }

    @Test
    func hydrationCatalogState_buildsLookupMapsAndPrioritizedProductIDs() {
        let state = LibraryHydrationCatalogState.liveFetch(
            primaryTitlesResponse: makeTitlesResponse([
                makeTitleDTO(titleId: "title-a", productId: "product-a", name: "A", entitled: true),
                makeTitleDTO(titleId: "title-b", productId: "product-b", name: "B", entitled: true)
            ]),
            supplementaryResponses: [],
            mruResponse: makeTitlesResponse([
                makeTitleDTO(titleId: "title-b", productId: "product-b", name: "B", entitled: true),
                makeTitleDTO(titleId: "title-missing", productId: "product-missing", name: "Missing", entitled: true)
            ]),
            existingSections: []
        )

        #expect(state.mruSource == .live)
        #expect(state.fetchedMRUCount == 1)
        #expect(state.mruEntries.map(\.titleId) == ["title-b"])
        #expect(state.titleByProductId[ProductID("product-a")]?.titleId == "title-a")
        #expect(state.titleByTitleId[TitleID("title-b")]?.productId == "product-b")
        #expect(Array(state.allProductIds.prefix(2)) == [ProductID("product-b"), ProductID("product-a")])
        #expect(state.mruProductIds == Set([ProductID("product-b")]))
    }

    @Test
    func hydrationLiveFetchApplyState_seedsCatalogDetailsAndBuildsRecoveryState() throws {
        let savedAt = Date(timeIntervalSince1970: 3_030_303_030)
        let snapshot = makeDecodedUnifiedSectionsSnapshot(savedAt: savedAt)
        let merchandising = try #require(snapshot.homeMerchandising)
        let discovery = try #require(snapshot.discovery)
        let title = TitleEntry(
            titleID: TitleID("title-1"),
            productID: ProductID("product-1"),
            inputs: ["controller"],
            fallbackName: "Fallback Halo"
        )

        let state = LibraryHydrationLiveFetchApplyState.liveFetch(
            sections: snapshot.sections,
            hydratedCatalogProducts: [
                makeCatalogProduct(
                    productId: "product-1",
                    title: "Halo Infinite",
                    shortDescription: "Chief returns",
                    publisherName: "Xbox",
                    screenshotURL: "https://example.com/halo-shot.jpg"
                )
            ],
            titleByProductId: [ProductID("product-1"): title],
            existingProductDetails: [:],
            homeMerchandising: merchandising,
            discovery: discovery,
            savedAt: savedAt,
            productDetailsCacheSizeLimit: 10
        )

        #expect(state.seededProductDetailCount == 1)
        #expect(state.recoveryState.shouldPersistUnifiedSnapshot == true)
        #expect(state.recoveryState.publishedState.source == .liveRecovery)
        #expect(state.recoveryState.productDetailsState?.shouldPersist == true)
        #expect(state.recoveryState.productDetailsState?.details[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(state.recoveryState.productDetailsState?.details[ProductID("product-1")]?.publisherName == "Xbox")
        #expect(state.recoveryState.productDetailsState?.details[ProductID("product-1")]?.galleryImageURLs.count == 1)
    }

    @Test
    func hydrationLiveFetchApplyState_keepsRicherExistingMediaWhileMergingCatalogDetails() throws {
        let savedAt = Date(timeIntervalSince1970: 4_040_404_040)
        let snapshot = makeDecodedUnifiedSectionsSnapshot(savedAt: savedAt)
        let merchandising = try #require(snapshot.homeMerchandising)
        let discovery = try #require(snapshot.discovery)
        let title = TitleEntry(
            titleID: TitleID("title-1"),
            productID: ProductID("product-1"),
            inputs: ["controller"],
            fallbackName: "Fallback Halo"
        )
        let existingMediaURL = URL(string: "https://example.com/rich-shot.jpg")
        let existing = CloudLibraryProductDetail(
            productId: "product-1",
            title: "Old Halo",
            publisherName: "Old Publisher",
            shortDescription: "Old description",
            mediaAssets: [
                CloudLibraryMediaAsset(
                    kind: .image,
                    url: try #require(existingMediaURL),
                    priority: 0,
                    source: .productDetails
                )
            ],
            galleryImageURLs: [try #require(existingMediaURL)]
        )

        let state = LibraryHydrationLiveFetchApplyState.liveFetch(
            sections: snapshot.sections,
            hydratedCatalogProducts: [
                makeCatalogProduct(
                    productId: "product-1",
                    title: "New Halo",
                    shortDescription: "Catalog description",
                    publisherName: "Xbox"
                )
            ],
            titleByProductId: [ProductID("product-1"): title],
            existingProductDetails: [ProductID("product-1"): existing],
            homeMerchandising: merchandising,
            discovery: discovery,
            savedAt: savedAt,
            productDetailsCacheSizeLimit: 10
        )

        let merged = try #require(state.recoveryState.productDetailsState?.details[ProductID("product-1")])
        #expect(state.seededProductDetailCount == 1)
        #expect(merged.title == "New Halo")
        #expect(merged.shortDescription == "Catalog description")
        #expect(merged.galleryImageURLs == [try #require(existingMediaURL)])
        #expect(merged.mediaAssets.first?.source == .productDetails)
    }

    @Test
    func productDetailsCache_versionMismatchIsIgnored() async throws {
        clearDetailsCacheFile()
        defer { clearDetailsCacheFile() }

        let snapshot = ProductDetailsDiskCacheSnapshot(
            savedAt: Date(),
            details: [
                ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
            ],
            cacheVersion: 99
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: LibraryController.detailsCacheURL, options: .atomic)

        let restored = LibraryController()
        await restored.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(restored.productDetails.isEmpty)
    }

    @Test
    func sectionsCache_restoresFreshUnifiedHomeSnapshot() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-sections-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let cacheLocations = LibraryController.CacheLocations(
            details: cacheRoot.appendingPathComponent("details.json"),
            sections: cacheRoot.appendingPathComponent("sections.json"),
            homeMerchandising: cacheRoot.appendingPathComponent("home.json")
        )

        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                siglID == "sigl-recent" ? ["product-1"] : []
            }
        )
        let source = LibraryController(
            cacheLocations: cacheLocations,
            homeMerchandisingSIGLProvider: provider
        )
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1")]
            )
        ]

        source.apply(.sectionsReplaced(sections))
        await source.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )
        source.saveCloudLibrarySectionsCache()
        await source.flushSectionsCacheForTesting()
        await waitForCacheFile(cacheLocations.repository)

        let restored = LibraryController(cacheLocations: cacheLocations)
        await restored.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(restored.sections.map(\.id) == ["library"])
        #expect(restored.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(restored.homeMerchandising?.recentlyAddedItems.map(\.titleId) == ["title-1"])
        #expect(restored.hasCompletedInitialHomeMerchandising == true)
        #expect(restored.hasRecoveredLiveHomeMerchandisingThisSession == false)
    }

    @Test
    func restoreDiskCachesIfNeeded_restoresProductDetailsWhenSectionsSnapshotIsRejected() async throws {
        clearDetailsCacheFile()
        clearSectionsCacheFile()
        defer {
            clearDetailsCacheFile()
            clearSectionsCacheFile()
        }

        let source = LibraryController()
        source.insertProductDetail(
            CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite"),
            primaryKey: "product-1"
        )
        await source.flushProductDetailsCacheForTesting()

        let staleSnapshot = makeUnifiedSectionsSnapshot(
            savedAt: .now.addingTimeInterval(-(StratixConstants.Hydration.effectiveCombinedHomeTTL + 60))
        )
        let staleRepository = try SwiftDataLibraryRepository(
            storeURL: LibraryController.CacheLocations.live.repository
        )
        await staleRepository.saveUnifiedSectionsSnapshot(staleSnapshot)

        let restored = LibraryController()
        await restored.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(restored.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(restored.sections.isEmpty)
        #expect(restored.homeMerchandising == nil)
        #expect(restored.hasCompletedInitialHomeMerchandising == false)
    }

    @Test
    func sectionsCache_restoresEmbeddedDiscoveryCache() async {
        clearSectionsCacheFile()
        defer { clearSectionsCacheFile() }

        let discoveryCounter = AsyncCounter()
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                await discoveryCounter.increment()
                return GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                siglID == "sigl-recent" ? ["product-1"] : []
            }
        )
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1")]
            )
        ]

        let source = LibraryController(homeMerchandisingSIGLProvider: provider)
        source.apply(.sectionsReplaced(sections))
        await source.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )
        source.saveCloudLibrarySectionsCache()
        await source.flushSectionsCacheForTesting()
        await waitForCacheFile(LibraryController.CacheLocations.live.repository)

        let restored = LibraryController(homeMerchandisingSIGLProvider: provider)
        await restored.restoreDiskCachesIfNeeded(isAuthenticated: true)
        await restored.refreshHomeMerchandisingSnapshot(
            latestSections: restored.sections,
            market: "US",
            language: "en-US"
        )

        #expect(await discoveryCounter.value == 1)
        #expect(restored.hasRecoveredLiveHomeMerchandisingThisSession == true)
    }

    @Test
    func sectionsCache_staleUnifiedSnapshotIsIgnored() async throws {
        clearSectionsCacheFile()
        defer { clearSectionsCacheFile() }

        let staleSavedAt = Date().addingTimeInterval(-(StratixConstants.Hydration.combinedHomeTTL + 120))
        let staleSnapshot = makeUnifiedSectionsSnapshot(savedAt: staleSavedAt)
        let staleRepository = try SwiftDataLibraryRepository(
            storeURL: LibraryController.CacheLocations.live.repository
        )
        await staleRepository.saveUnifiedSectionsSnapshot(staleSnapshot)

        let controller = LibraryController()
        await controller.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(controller.sections.isEmpty)
        #expect(controller.homeMerchandising == nil)
        #expect(controller.hasCompletedInitialHomeMerchandising == false)
    }

    @Test
    func sectionsCache_incompleteUnifiedSnapshotIsIgnored() async throws {
        clearSectionsCacheFile()
        defer { clearSectionsCacheFile() }

        let incompleteSnapshot = makeUnifiedSectionsSnapshot(
            savedAt: Date(),
            includeDiscovery: false,
            isUnifiedHomeReady: false
        )
        let incompleteRepository = try SwiftDataLibraryRepository(
            storeURL: LibraryController.CacheLocations.live.repository
        )
        await incompleteRepository.saveUnifiedSectionsSnapshot(incompleteSnapshot)

        let controller = LibraryController()
        await controller.restoreDiskCachesIfNeeded(isAuthenticated: true)

        #expect(controller.sections.isEmpty)
        #expect(controller.homeMerchandising == nil)
        #expect(controller.hasCompletedInitialHomeMerchandising == false)
    }

    @Test
    func refresh_skipsWhenUnifiedSnapshotIsStillValid() async {
        let counter = CounterBox()
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                siglID == "sigl-recent" ? ["product-1"] : []
            }
        )
        let controller = LibraryController(refreshWorkflow: { _, _, _ in
            counter.value += 1
        }, homeMerchandisingSIGLProvider: provider)
        let sections = [makeSection(titleId: "title-1", productId: "product-1")]
        controller.apply(.sectionsReplaced(sections))
        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )
        controller.apply(.lastHydratedAtSet(Date()))

        await controller.refresh(forceRefresh: false, reason: .manualUser)

        #expect(counter.value == 0)
        #expect(await controller.testingIsLoadTaskActive() == false)
    }

    @Test
    func hydrationPlanner_acceptsFreshUnifiedStartupSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        let planner = LibraryHydrationPlanner(now: { now })
        let snapshot = makeUnifiedSectionsSnapshot(savedAt: now.addingTimeInterval(-120))

        #expect(planner.startupRestoreDecision(for: snapshot) == .applyUnifiedSnapshot)
        #expect(planner.shouldApplyUnifiedSectionsCache(snapshot))
    }

    @Test
    func hydrationPlanner_rejectsStaleAndIncompleteStartupSnapshots() {
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        let planner = LibraryHydrationPlanner(now: { now })
        let staleSnapshot = makeUnifiedSectionsSnapshot(
            savedAt: now.addingTimeInterval(-(StratixConstants.Hydration.effectiveCombinedHomeTTL + 5))
        )
        let incompleteSnapshot = makeUnifiedSectionsSnapshot(
            savedAt: now,
            includeDiscovery: false,
            isUnifiedHomeReady: false
        )

        #expect(planner.startupRestoreDecision(for: staleSnapshot) == .reject("stale"))
        #expect(planner.startupRestoreDecision(for: incompleteSnapshot) == .reject("home_not_ready"))
    }

    @Test
    func hydrationPlanner_buildsStartupRestoreResultForFreshVersionedPayload() {
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        let planner = LibraryHydrationPlanner(now: { now })
        let payload = LibraryStartupCachePayload(
            productDetails: .snapshot(
                ProductDetailsDiskCacheSnapshot(
                    savedAt: now,
                    details: [
                        ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
                    ],
                    cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion
                )
            ),
            sectionsSnapshot: makeDecodedUnifiedSectionsSnapshot(savedAt: now.addingTimeInterval(-120))
        )

        let result = planner.makeStartupRestoreResult(
            payload: payload,
            shouldLoadProductDetails: true,
            shouldLoadSections: true,
            expectedCacheVersion: LibraryHydrationCacheSchema.currentCacheVersion
        )

        guard case .apply(let details)? = result.productDetails else {
            Issue.record("Expected product details restore apply outcome.")
            return
        }
        #expect(details[ProductID("product-1")]?.title == "Halo Infinite")

        guard case .apply(let snapshot)? = result.sections else {
            Issue.record("Expected unified sections restore apply outcome.")
            return
        }
        #expect(snapshot.sections.map(\.id) == ["library"])
        #expect(snapshot.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
    }

    @Test
    func hydrationPlanner_buildsStartupRestoreRejectionsForLegacyAndStalePayloads() {
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        let planner = LibraryHydrationPlanner(now: { now })
        let payload = LibraryStartupCachePayload(
            productDetails: .legacyUnversioned,
            sectionsSnapshot: makeDecodedUnifiedSectionsSnapshot(
                savedAt: now.addingTimeInterval(-(StratixConstants.Hydration.effectiveCombinedHomeTTL + 5))
            )
        )

        let result = planner.makeStartupRestoreResult(
            payload: payload,
            shouldLoadProductDetails: true,
            shouldLoadSections: true,
            expectedCacheVersion: LibraryHydrationCacheSchema.currentCacheVersion
        )

        guard case .rejectLegacyUnversioned? = result.productDetails else {
            Issue.record("Expected legacy product-details rejection.")
            return
        }

        guard case .rejectUnifiedSnapshot(let reason, _)? = result.sections else {
            Issue.record("Expected stale unified-sections rejection.")
            return
        }
        #expect(reason == "stale")
    }

    @Test
    func hydrationPlanner_prefersPostStreamMRUDeltaForFreshUnifiedSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        let planner = LibraryHydrationPlanner(now: { now })
        let sections = [makeSection(titleId: "title-1", productId: "product-1")]
        let merchandising = HomeMerchandisingSnapshot(
            recentlyAddedItems: [makeItem(titleId: "title-1", productId: "product-1")],
            rows: [],
            generatedAt: now.addingTimeInterval(-120)
        )

        let plan = planner.makePostStreamPlan(
            sections: sections,
            homeMerchandising: merchandising,
            hasCompletedInitialHomeMerchandising: true,
            lastHydratedAt: now.addingTimeInterval(-120),
            cacheSavedAt: nil
        )

        #expect(plan.mode == .refreshMRUDelta)
        #expect(plan.decisionDescription == "fresh_unified_snapshot")
    }

    @Test
    func hydrationPlanner_escalatesPostStreamRefreshWhenSnapshotIsIncompleteOrStale() {
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        let planner = LibraryHydrationPlanner(now: { now })
        let sections = [makeSection(titleId: "title-1", productId: "product-1")]
        let merchandising = HomeMerchandisingSnapshot(
            recentlyAddedItems: [makeItem(titleId: "title-1", productId: "product-1")],
            rows: [],
            generatedAt: now
        )

        let missingHomePlan = planner.makePostStreamPlan(
            sections: sections,
            homeMerchandising: nil,
            hasCompletedInitialHomeMerchandising: true,
            lastHydratedAt: now,
            cacheSavedAt: nil
        )
        let stalePlan = planner.makePostStreamPlan(
            sections: sections,
            homeMerchandising: merchandising,
            hasCompletedInitialHomeMerchandising: true,
            lastHydratedAt: now.addingTimeInterval(-(StratixConstants.Hydration.effectiveCombinedHomeTTL + 5)),
            cacheSavedAt: nil
        )

        #expect(missingHomePlan.mode == .refreshNetwork)
        #expect(missingHomePlan.decisionDescription == "home_missing")
        #expect(stalePlan.mode == .refreshNetwork)
        #expect(stalePlan.decisionDescription == "snapshot_stale")
    }

    @Test
    func makePostStreamHydrationPlan_escalatesWhenControllerStateIsIncomplete() async {
        let controller = LibraryController()
        controller.apply([
            .sectionsReplaced([makeSection(titleId: "title-1", productId: "product-1")]),
            .lastHydratedAtSet(Date().addingTimeInterval(-(StratixConstants.Hydration.effectiveCombinedHomeTTL + 5)))
        ])

        let plan = controller.makePostStreamHydrationPlan()

        #expect(plan.mode == .refreshNetwork)
        #expect(plan.decisionDescription == "home_missing")
    }

    @Test
    func applyPostStreamMRUDelta_returnsNoChangeWhenMRUAlreadyMatches() async {
        let controller = LibraryController()
        let sections = [
            makeSection(
                id: "mru",
                name: "Continue Playing",
                items: [makeItem(titleId: "title-1", productId: "product-1", isInMRU: true)]
            ),
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1", isInMRU: true)]
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
            [makeMRUEntry(titleId: "title-1", productId: "product-1")],
            market: "US",
            language: "en-US"
        )

        #expect(result == .noChange)
    }

    @Test
    func setLastHydratedAt_doesNotBumpCatalogRevision() {
        let controller = LibraryController()
        controller.apply(.sectionsReplaced([makeSection(titleId: "title-1", productId: "product-1")]))
        let baselineRevision = controller.catalogRevision

        controller.apply(.lastHydratedAtSet(Date()))

        #expect(controller.catalogRevision == baselineRevision)
    }

    @Test
    func refresh_deduplicatesInflightLoads() async {
        let counter = CounterBox()
        let controller = LibraryController(refreshWorkflow: { _, _, _ in
            counter.value += 1
            try? await Task.sleep(nanoseconds: 150_000_000)
        })

        async let first: Void = controller.refresh(forceRefresh: true, reason: .manualUser)
        async let second: Void = controller.refresh(forceRefresh: true, reason: .manualUser)
        _ = await (first, second)

        #expect(counter.value == 1)
    }

    @Test
    func suspendForStreaming_blocksNewWorkAndPreservesCachedState() async {
        let refreshCounter = CounterBox()
        let detailCounter = CounterBox()
        let controller = LibraryController(
            refreshWorkflow: { _, _, _ in
                refreshCounter.value += 1
            },
            detailWorkflow: { _, _, _, _ in
                detailCounter.value += 1
            }
        )
        controller.apply([
            .sectionsReplaced([makeSection(titleId: "title-1", productId: "product-1")]),
            .productDetailsReplaced([
                ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")
            ])
        ])
        let originalHome = HomeMerchandisingSnapshot(
            recentlyAddedItems: [makeItem(titleId: "title-1", productId: "product-1")],
            rows: [
                HomeMerchandisingRow(
                    alias: "recently-added",
                    label: "Recently Added",
                    source: .fixedPriority,
                    items: [makeItem(titleId: "title-1", productId: "product-1")]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        controller.apply(.homeMerchandisingSet(originalHome))

        await controller.suspendForStreaming()

        await controller.refresh(forceRefresh: true, reason: .manualUser)
        await controller.loadDetail(productID: ProductID("product-1"), forceRefresh: true)
        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: [makeSection(titleId: "title-2", productId: "product-2")],
            market: "US",
            language: "en-US"
        )
        await controller.prefetchArtworkURLs(
            [URL(string: "https://example.com/artwork.jpg")!],
            reason: "test"
        )

        #expect(refreshCounter.value == 0)
        #expect(detailCounter.value == 0)
        #expect(controller.sections.map(\.id) == ["library"])
        #expect(controller.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
        #expect(controller.homeMerchandising == originalHome)
        #expect(controller.hasCompletedInitialHomeMerchandising == false)
    }

    @Test
    func resumeAfterStreaming_allowsRefreshWorkAgain() async {
        let refreshCounter = CounterBox()
        let controller = LibraryController(refreshWorkflow: { _, _, _ in
            refreshCounter.value += 1
        })

        await controller.suspendForStreaming()
        await controller.refresh(forceRefresh: true, reason: .manualUser)
        #expect(refreshCounter.value == 0)

        controller.resumeAfterStreaming()
        await controller.refresh(forceRefresh: true, reason: .manualUser)

        #expect(refreshCounter.value == 1)
    }

    @Test
    func makeLibraryTokenCandidates_preservePerOfferingHosts() {
        let controller = LibraryController()
        let tokens = StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: "https://xcloud.example.com",
            xcloudF2PToken: "f2p-token",
            xcloudF2PHost: "https://f2p.example.com"
        )

        let candidates = controller.makeLibraryTokenCandidates(tokens: tokens)

        #expect(candidates.map(\.label) == ["xCloud", "xCloudF2P", "xHome"])
        #expect(candidates.map(\.preferredHost) == [
            "https://xcloud.example.com",
            LibraryController.hydrationConfig.canonicalF2PLibraryHost,
            "https://xhome.example.com"
        ])
    }

    @Test
    func makeLibraryHostCandidates_prioritizePreferredAndStoredHosts() {
        let controller = LibraryController()
        let tokens = StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: "https://xcloud.example.com/",
            xcloudF2PToken: "f2p-token",
            xcloudF2PHost: "f2p.example.com"
        )

        let hosts = controller.makeLibraryHostCandidates(
            tokens: tokens,
            preferredHost: LibraryController.hydrationConfig.canonicalF2PLibraryHost
        )

        #expect(Array(hosts.prefix(4)) == [
            LibraryController.hydrationConfig.canonicalF2PLibraryHost,
            "https://xcloud.example.com",
            "https://f2p.example.com",
            LibraryController.hydrationConfig.defaultLibraryHost
        ])
        #expect(hosts.filter { $0 == "https://xcloud.example.com" }.count == 1)
    }

    @Test
    func preferredHydrationSections_keepsCandidateWithMoreTitles() {
        let currentBest = [
            makeSection(
                id: "library",
                name: "Library",
                items: [
                    makeItem(titleId: "title-1", productId: "product-1")
                ]
            )
        ]
        let candidate = [
            makeSection(
                id: "library",
                name: "Library",
                items: [
                    makeItem(titleId: "title-1", productId: "product-1"),
                    makeItem(titleId: "title-2", productId: "product-2")
                ]
            )
        ]

        let preferred = LibraryController.preferredHydrationSections(
            currentBest: currentBest,
            candidate: candidate
        )

        #expect(LibraryController.libraryTitleCount(in: preferred) == 2)
    }

    @Test
    func preferredHydrationSections_keepsCurrentBestWhenCandidateShrinks() {
        let currentBest = [
            makeSection(
                id: "library",
                name: "Library",
                items: [
                    makeItem(titleId: "title-1", productId: "product-1"),
                    makeItem(titleId: "title-2", productId: "product-2")
                ]
            )
        ]
        let candidate = [
            makeSection(
                id: "library",
                name: "Library",
                items: [
                    makeItem(titleId: "title-1", productId: "product-1")
                ]
            )
        ]

        let preferred = LibraryController.preferredHydrationSections(
            currentBest: currentBest,
            candidate: candidate
        )

        #expect(LibraryController.libraryTitleCount(in: preferred) == 2)
    }

    @Test
    func noteArtworkPrefetchFailure_disablesFurtherPrefetchesForSession() async {
        let controller = LibraryController()
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.ENOSPC.rawValue))

        await controller.noteArtworkPrefetchFailure(error)

        #expect(controller.shouldThrottleArtworkPrefetch == true)
        #expect(controller.isArtworkPrefetchThrottled == true)
    }

    @Test
    func resetForSignOut_clearsStateAndFlags() async {
        let controller = LibraryController()
        controller.apply([
            .sectionsReplaced([makeSection(titleId: "title-1", productId: "product-1")]),
            .productDetailsReplaced([ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1")]),
            .homeMerchandisingSessionSourceSet(.liveRecovery),
            .errorSet("error"),
            .needsReauthSet(true),
            .lastHydratedAtSet(Date()),
            .cacheSavedAtSet(Date()),
            .artworkPrefetchThrottleSet(true)
        ])
        controller.hasPerformedNetworkHydrationThisSession = true
        controller.hasLoadedProductDetailsCache = true
        controller.hasLoadedSectionsCache = true
        controller.isArtworkPrefetchDisabledForSession = true
        controller.lastArtworkPrefetchStartedAt = Date()
        controller.artworkPrefetchLastCompletedAtByURL = ["https://example.com/image.jpg": Date()]

        await controller.resetForSignOut()

        #expect(controller.sections.isEmpty)
        #expect(controller.productDetails.isEmpty)
        #expect(controller.lastError == nil)
        #expect(controller.needsReauth == false)
        #expect(controller.lastHydratedAt == nil)
        #expect(controller.homeMerchandisingSessionSource == .none)
        #expect(controller.hasRecoveredLiveHomeMerchandisingThisSession == false)
        #expect(controller.isArtworkPrefetchThrottled == false)
        #expect(controller.hasPerformedNetworkHydrationThisSession == false)
        #expect(controller.hasLoadedProductDetailsCache == false)
        #expect(controller.hasLoadedSectionsCache == false)
        #expect(controller.shouldThrottleArtworkPrefetch == false)
        #expect(controller.artworkPrefetchLastCompletedAtByURL.isEmpty)
    }

    @Test
    func refreshHomeMerchandising_reusesFreshDiscoveryCache() async {
        let discoveryCounter = AsyncCounter()
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                await discoveryCounter.increment()
                return GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                if siglID == "sigl-recent" {
                    return ["product-1"]
                }
                return []
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1")]
            )
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )
        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        #expect(await discoveryCounter.value == 1)
    }

    @Test
    func refreshHomeMerchandising_marksSessionSourceAsLiveRecovery() async {
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                siglID == "sigl-recent" ? ["product-1"] : []
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1")]
            )
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        #expect(controller.homeMerchandisingSessionSource == .liveRecovery)
        #expect(controller.hasRecoveredLiveHomeMerchandisingThisSession == true)
        #expect(controller.hasCompletedInitialHomeMerchandising == true)
    }

    @Test
    func refreshHomeMerchandising_forceDiscoveryRefreshBypassesFreshDiscoveryCache() async {
        let discoveryCounter = AsyncCounter()
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                await discoveryCounter.increment()
                return GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                if siglID == "sigl-recent" {
                    return ["product-1"]
                }
                return []
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1")]
            )
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )
        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US",
            forceDiscoveryRefresh: true
        )

        #expect(await discoveryCounter.value == 2)
    }

    @Test
    func refreshHomeMerchandising_fallsBackWhenDiscoveryFails() async {
        let fallbackRecentlyAddedSIGL = GamePassSiglClient.fallbackAliasToSiglID["recently-added"] ?? ""
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                throw NSError(domain: "test", code: 1)
            },
            fetchProductIDs: { siglID, _, _ in
                if siglID == fallbackRecentlyAddedSIGL {
                    return ["product-1", "product-missing"]
                }
                return []
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1")]
            )
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        let snapshot = controller.homeMerchandising
        #expect(snapshot != nil)
        #expect(snapshot?.rows.first?.alias == "recently-added")
        #expect(snapshot?.rows.first?.source == .fixedPriority)
        #expect(snapshot?.rows.first?.items.map(\.productId) == ["product-1"])
    }

    @Test
    func refreshHomeMerchandising_preservesExistingRecentlyAddedWhenRefreshReturnsEmpty() async {
        actor CallCounter {
            var value = 0
            func next() -> Int {
                defer { value += 1 }
                return value
            }
        }

        let counter = CallCounter()
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                guard siglID == "sigl-recent" else { return [] }
                return await counter.next() == 0 ? ["product-1"] : []
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-1", productId: "product-1")]
            )
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )
        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        #expect(controller.homeMerchandising?.rows.map(\.alias) == ["recently-added"])
        #expect(controller.homeMerchandising?.recentlyAddedItems.map(\.titleId) == ["title-1"])
    }

    @Test
    func refreshHomeMerchandising_preservesFixedOrderAndSuppressesEmptyRows() async {
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "fighters", siglID: "sigl-fighters"),
                    Self.makeDiscoveryEntry(alias: "popular", siglID: "sigl-popular"),
                    Self.makeDiscoveryEntry(alias: "action-adventure", siglID: "sigl-action"),
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                switch siglID {
                case "sigl-recent": return ["product-recent"]
                case "sigl-popular": return ["product-popular"]
                case "sigl-fighters": return ["product-fighters"]
                case "sigl-action": return ["product-missing"]
                default: return []
                }
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [
                    makeItem(titleId: "title-recent", productId: "product-recent"),
                    makeItem(titleId: "title-popular", productId: "product-popular"),
                    makeItem(titleId: "title-fighters", productId: "product-fighters")
                ]
            )
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        #expect(controller.homeMerchandising?.rows.map(\.alias) == [
            "recently-added",
            "popular",
            "fighters"
        ])
    }

    @Test
    func refreshThenApplyPostStreamMRUDelta_reusesCachedDiscoveryAndPreservesRows() async {
        let discoveryCounter = AsyncCounter()
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                await discoveryCounter.increment()
                return GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent"),
                    Self.makeDiscoveryEntry(alias: "popular", siglID: "sigl-popular")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                switch siglID {
                case "sigl-recent":
                    return ["product-new", "product-old"]
                case "sigl-popular":
                    return ["product-popular"]
                default:
                    return []
                }
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "mru",
                name: "Continue Playing",
                items: [makeItem(titleId: "title-old", productId: "product-old", isInMRU: true)]
            ),
            makeSection(
                id: "library",
                name: "Library",
                items: [
                    makeItem(titleId: "title-old", productId: "product-old", isInMRU: true),
                    makeItem(titleId: "title-new", productId: "product-new"),
                    makeItem(titleId: "title-popular", productId: "product-popular")
                ]
            )
        ]

        controller.apply(.sectionsReplaced(sections))
        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        let result = await controller.applyPostStreamMRUDelta(
            [makeMRUEntry(titleId: "title-new", productId: "product-new")],
            market: "US",
            language: "en-US"
        )

        #expect(result == .appliedDelta)
        #expect(await discoveryCounter.value == 1)
        #expect(controller.discoveryEntries.map(\.alias) == ["recently-added", "popular"])
        #expect(controller.homeMerchandising?.rows.map(\.alias) == ["recently-added", "popular"])
        #expect(controller.homeMerchandising?.recentlyAddedItems.map(\.titleId) == ["title-new", "title-old"])
        #expect(controller.homeMerchandising?.rows.first?.items.map(\.titleId) == ["title-new", "title-old"])
    }

    @Test
    func refreshHomeMerchandising_capsExtraDiscoveredRowsInOrder() async {
        let extraAliases = (1...7).map { "bonus-\($0)" }
        let discoveryEntries = [
            Self.makeDiscoveryEntry(alias: "popular", siglID: "sigl-popular")
        ] + extraAliases.map { alias in
            Self.makeDiscoveryEntry(alias: alias, siglID: "sigl-\(alias)")
        }

        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: discoveryEntries)
            },
            fetchProductIDs: { siglID, _, _ in
                if siglID == "sigl-popular" {
                    return ["product-popular"]
                }
                if siglID.hasPrefix("sigl-bonus-") {
                    return ["product-\(siglID.replacingOccurrences(of: "sigl-", with: ""))"]
                }
                return []
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)

        var items = [makeItem(titleId: "title-popular", productId: "product-popular")]
        items += extraAliases.map { alias in
            makeItem(titleId: "title-\(alias)", productId: "product-\(alias)")
        }
        let sections = [
            makeSection(id: "library", name: "Library", items: items)
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        #expect(controller.homeMerchandising?.rows.map(\.alias) == [
            "popular",
            "bonus-1",
            "bonus-2",
            "bonus-3",
            "bonus-4",
            "bonus-5",
            "bonus-6"
        ])
    }

    @Test
    func refreshHomeMerchandising_keepsFreeToPlayAtBottom() async {
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "free-to-play", siglID: "sigl-f2p"),
                    Self.makeDiscoveryEntry(alias: "bonus", siglID: "sigl-bonus")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                switch siglID {
                case "sigl-f2p": return ["product-f2p"]
                case "sigl-bonus": return ["product-bonus"]
                default: return []
                }
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [
                    makeItem(titleId: "title-bonus", productId: "product-bonus"),
                    makeItem(titleId: "title-f2p", productId: "product-f2p")
                ]
            )
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        #expect(controller.homeMerchandising?.rows.map(\.alias) == [
            "bonus",
            "free-to-play"
        ])
    }

    @Test
    func refreshHomeMerchandising_filtersToPlayableLibraryIntersection() async {
        let provider = LibraryController.HomeMerchandisingSIGLProvider(
            discoverAliases: {
                GamePassSiglDiscoveryResult(entries: [
                    Self.makeDiscoveryEntry(alias: "popular", siglID: "sigl-popular")
                ])
            },
            fetchProductIDs: { siglID, _, _ in
                if siglID == "sigl-popular" {
                    return ["product-playable", "product-nonplayable"]
                }
                return []
            }
        )
        let controller = LibraryController(homeMerchandisingSIGLProvider: provider)
        let sections = [
            makeSection(
                id: "mru",
                name: "Jump Back In",
                items: [makeItem(titleId: "title-mru", productId: "product-nonplayable", isInMRU: true)]
            ),
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-playable", productId: "product-playable")]
            )
        ]

        await controller.refreshHomeMerchandisingSnapshot(
            latestSections: sections,
            market: "US",
            language: "en-US"
        )

        #expect(controller.homeMerchandising?.rows.first?.alias == "popular")
        #expect(controller.homeMerchandising?.rows.first?.items.map(\.titleId) == ["title-playable"])
    }

    @Test
    func sectionsApplyingMRUDelta_rebuildsMRUSectionAndFlagsLibraryItems() {
        let sections = [
            makeSection(
                id: "mru",
                name: "Continue Playing",
                items: [makeItem(titleId: "title-stale", productId: "product-stale", isInMRU: true)]
            ),
            makeSection(
                id: "library",
                name: "Library",
                items: [
                    makeItem(titleId: "title-fresh", productId: "product-fresh"),
                    makeItem(titleId: "title-stale", productId: "product-stale", isInMRU: true),
                    makeItem(titleId: "title-other", productId: "product-other")
                ]
            )
        ]

        let updatedSections = LibraryController.sectionsApplyingMRUDelta(
            to: sections,
            liveMRUEntries: [
                makeMRUEntry(titleId: "title-fresh", productId: "product-fresh"),
                makeMRUEntry(titleId: "title-fresh", productId: "product-fresh")
            ]
        )

        let appliedSections: [CloudLibrarySection]
        switch updatedSections {
        case .updated(let sections):
            appliedSections = sections
        default:
            Issue.record("Expected MRU delta to produce updated sections.")
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
    func sectionsApplyingMRUDelta_requiresFullRefreshWhenLiveEntriesCannotMapOntoCache() {
        let sections = [
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-cached", productId: "product-cached")]
            )
        ]

        let result = LibraryController.sectionsApplyingMRUDelta(
            to: sections,
            liveMRUEntries: [makeMRUEntry(titleId: "title-live", productId: "product-live")]
        )

        #expect(result == .requiresFullRefresh("mru_entries_unmapped"))
    }

    @Test
    func sectionsApplyingMRUDelta_clearsStaleMRUWhenLiveEntriesAreEmpty() {
        let sections = [
            makeSection(
                id: "mru",
                name: "Continue Playing",
                items: [makeItem(titleId: "title-stale", productId: "product-stale", isInMRU: true)]
            ),
            makeSection(
                id: "library",
                name: "Library",
                items: [makeItem(titleId: "title-stale", productId: "product-stale", isInMRU: true)]
            )
        ]

        let result = LibraryController.sectionsApplyingMRUDelta(
            to: sections,
            liveMRUEntries: []
        )

        let appliedSections: [CloudLibrarySection]
        switch result {
        case .updated(let sections):
            appliedSections = sections
        default:
            Issue.record("Expected empty live MRU to clear stale MRU state.")
            return
        }

        #expect(appliedSections.map(\.id) == ["library"])
        #expect(appliedSections[0].items.allSatisfy { $0.isInMRU == false })
    }

    private func makeSection(titleId: String, productId: String) -> CloudLibrarySection {
        CloudLibrarySection(
            id: "library",
            name: "Library",
            items: [
                makeItem(titleId: titleId, productId: productId)
            ]
        )
    }

    private func makeSection(
        id: String,
        name: String,
        items: [CloudLibraryItem]
    ) -> CloudLibrarySection {
        CloudLibrarySection(
            id: id,
            name: name,
            items: items
        )
    }

    private func makeItem(
        titleId: String,
        productId: String,
        isInMRU: Bool = false
    ) -> CloudLibraryItem {
        CloudLibraryItem(
            titleId: titleId,
            productId: productId,
            name: "Test \(titleId)",
            shortDescription: nil,
            artURL: URL(string: "https://example.com/\(titleId).jpg"),
            supportedInputTypes: ["controller"],
            isInMRU: isInMRU
        )
    }

    private func makeMRUEntry(titleId: String, productId: String) -> LibraryMRUEntry {
        LibraryMRUEntry(titleID: TitleID(titleId), productID: ProductID(productId))
    }

    private func makeTitlesResponse(_ results: [XCloudTitleDTO]) -> XCloudTitlesResponse {
        XCloudTitlesResponse(results: results)
    }

    private func makeTitleDTO(
        titleId: String,
        productId: String,
        name: String,
        entitled: Bool,
        inputs: [String] = ["controller"]
    ) -> XCloudTitleDTO {
        XCloudTitleDTO(
            titleId: titleId,
            details: .init(
                productId: productId,
                name: name,
                hasEntitlement: entitled,
                supportedInputTypes: inputs
            )
        )
    }

    private func makeCatalogProduct(
        productId: String,
        title: String,
        shortDescription: String? = nil,
        publisherName: String? = nil,
        screenshotURL: String? = nil
    ) -> GamePassCatalogClient.CatalogProduct {
        var payload: [String: Any] = [
            "ProductId": productId,
            "ProductTitle": title
        ]
        if let shortDescription {
            payload["ProductDescriptionShort"] = shortDescription
        }
        if let publisherName {
            payload["PublisherName"] = publisherName
        }
        if let screenshotURL {
            payload["Screenshots"] = [
                [
                    "URL": screenshotURL,
                    "Width": 1920,
                    "Height": 1080
                ]
            ]
        }

        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(GamePassCatalogClient.CatalogProduct.self, from: data)
    }

    private nonisolated static func makeDiscoveryEntry(alias: String, siglID: String) -> GamePassSiglDiscoveryEntry {
        GamePassSiglDiscoveryEntry(
            alias: alias,
            label: alias,
            siglID: siglID,
            source: .nextData
        )
    }

    private func makeUnifiedSectionsSnapshot(
        savedAt: Date,
        includeDiscovery: Bool = true,
        isUnifiedHomeReady: Bool = true
    ) -> LibrarySectionsDiskCacheSnapshot {
        LibrarySectionsDiskCacheSnapshot(
            savedAt: savedAt,
            sections: [
                LibrarySectionDiskCacheSnapshot(
                    id: "library",
                    name: "Library",
                    items: [makeDiskItemSnapshot(titleId: "title-1", productId: "product-1")]
                )
            ],
            homeMerchandising: HomeMerchandisingDiskCacheSnapshot(
                savedAt: savedAt,
                recentlyAddedItems: [makeDiskItemSnapshot(titleId: "title-1", productId: "product-1")],
                rows: [
                    HomeMerchandisingRowDiskCacheSnapshot(
                        alias: "recently-added",
                        label: "Recently Added",
                        source: HomeMerchandisingRow.Source.fixedPriority.rawValue,
                        items: [makeDiskItemSnapshot(titleId: "title-1", productId: "product-1")]
                    )
                ]
            ),
            siglDiscovery: includeDiscovery
                ? HomeMerchandisingDiscoveryDiskCacheSnapshot(
                    savedAt: savedAt,
                    entries: [
                        HomeMerchandisingDiscoveryEntryDiskCacheSnapshot(
                            alias: "recently-added",
                            label: "Recently Added",
                            siglID: "sigl-recent",
                            source: GamePassSiglDiscoveryEntry.Source.nextData.rawValue
                        )
                    ]
                )
                : nil,
            isUnifiedHomeReady: isUnifiedHomeReady
        )
    }

    private func makeDecodedUnifiedSectionsSnapshot(
        savedAt: Date,
        includeDiscovery: Bool = true,
        isUnifiedHomeReady: Bool = true
    ) -> DecodedLibrarySectionsCacheSnapshot {
        DecodedLibrarySectionsCacheSnapshot(
            savedAt: savedAt,
            sections: [
                makeSection(
                    id: "library",
                    name: "Library",
                    items: [makeItem(titleId: "title-1", productId: "product-1")]
                )
            ],
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
            discovery: includeDiscovery
                ? HomeMerchandisingDiscoveryCachePayload(
                    entries: [
                        Self.makeDiscoveryEntry(alias: "recently-added", siglID: "sigl-recent")
                    ],
                    savedAt: savedAt
                )
                : nil,
            isUnifiedHomeReady: isUnifiedHomeReady,
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
            metadata: .compatibility(
                savedAt: savedAt,
                cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
                refreshSource: "test_fixture",
                homeReady: isUnifiedHomeReady
            )
        )
    }

    private func makeDiskItemSnapshot(titleId: String, productId: String) -> LibraryItemDiskCacheSnapshot {
        LibraryItemDiskCacheSnapshot(
            titleId: TitleID(titleId),
            productId: ProductID(productId),
            name: "Test \(titleId)",
            shortDescription: nil,
            artURL: "https://example.com/\(titleId).jpg",
            posterImageURL: nil,
            heroImageURL: nil,
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: ["controller"],
            isInMRU: false
        )
    }

    private func clearSectionsCacheFile() {
        try? FileManager.default.removeItem(at: LibraryController.sectionsCacheURL)
        try? FileManager.default.removeItem(at: LibraryController.CacheLocations.live.repository)
        try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: LibraryController.CacheLocations.live.repository.path + "-shm")
        )
        try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: LibraryController.CacheLocations.live.repository.path + "-wal")
        )
    }

    private func clearDetailsCacheFile() {
        try? FileManager.default.removeItem(at: LibraryController.detailsCacheURL)
    }

    private func waitForCacheFile(_ url: URL) async {
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: url.path) {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

@MainActor
private final class CounterBox {
    var value = 0
}

private actor AsyncCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
