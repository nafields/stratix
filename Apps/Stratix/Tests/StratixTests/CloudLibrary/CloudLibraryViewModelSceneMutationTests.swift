// CloudLibraryViewModelSceneMutationTests.swift
// Exercises cloud library view model scene mutation behavior.
//

import XCTest
import StratixModels
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

@MainActor
final class CloudLibraryViewModelSceneMutationTests: XCTestCase {
    func testApplySceneMutation_updatesCachedCountsLookupsAndProjections() {
        let viewModel = CloudLibraryViewModel()
        let recentItem = CloudLibraryTestSupport.makeItem(
            titleID: "recent-title",
            productID: "recent-product",
            name: "Recent Game"
        )
        let libraryItem = CloudLibraryTestSupport.makeItem(
            titleID: "library-title",
            productID: "library-product",
            name: "Library Game"
        )
        let detail = CloudLibraryTestSupport.makeDetail(
            productId: "recent-product",
            title: "Recent Game"
        )
        let adapter = CloudLibraryTestSupport.makeLibraryStateSnapshot(
            sections: [
                CloudLibrarySection(id: "mru", name: "Recent", items: [recentItem]),
                CloudLibrarySection(id: "library", name: "Library", items: [recentItem, libraryItem])
            ],
            productDetails: [ProductID("recent-product"): detail],
            catalogRevision: 7,
            detailRevision: 11,
            homeRevision: 9,
            sceneContentRevision: 13
        )
        var queryState = LibraryQueryState()
        queryState.selectedTabID = "full-library"
        let inputs = CloudLibrarySceneInputs(
            library: adapter,
            queryState: queryState,
            showsContinueBadge: true
        )

        viewModel.applySceneMutation(inputs: inputs)

        XCTAssertEqual(viewModel.cachedLibraryCount, 2)
        XCTAssertEqual(viewModel.cachedItemsByTitleID[TitleID("recent-title")]?.productId, "recent-product")
        XCTAssertEqual(viewModel.cachedItemsByProductID[ProductID("library-product")]?.titleId, "library-title")
        XCTAssertEqual(viewModel.cachedHomeState.sections.first?.id, "mru")
        XCTAssertEqual(viewModel.cachedLibraryState.selectedTabID, "full-library")
        XCTAssertFalse(viewModel.cachedLibraryState.gridItems.isEmpty)
    }

    func testHeroBackgroundContext_buildsStableTaskIDAndCachesContext() {
        let viewModel = CloudLibraryViewModel()
        let homeItem = CloudLibraryTestSupport.makeItem(
            titleID: "home-title",
            productID: "home-product",
            name: "Home Game"
        )
        let detailItem = CloudLibraryTestSupport.makeItem(
            titleID: "detail-title",
            productID: "detail-product",
            name: "Detail Game"
        )
        viewModel.cachedItemsByTitleID = [
            TitleID(homeItem.titleId): homeItem,
            TitleID(detailItem.titleId): detailItem
        ]

        let firstTaskID = viewModel.heroBackgroundTaskID(
            browseRouteRawValue: CloudLibrarySceneModel.HeroBackgroundRoute.home.rawValue,
            utilityRouteVisible: false,
            detailTitleID: TitleID(detailItem.titleId),
            homeFocusedTitleID: TitleID(homeItem.titleId),
            libraryFocusedTitleID: nil
        )
        let secondTaskID = viewModel.heroBackgroundTaskID(
            browseRouteRawValue: CloudLibrarySceneModel.HeroBackgroundRoute.home.rawValue,
            utilityRouteVisible: false,
            detailTitleID: TitleID(detailItem.titleId),
            homeFocusedTitleID: TitleID(homeItem.titleId),
            libraryFocusedTitleID: nil
        )

        XCTAssertEqual(firstTaskID, secondTaskID)

        viewModel.rebuildHeroBackgroundContext(
            browseRouteRawValue: CloudLibrarySceneModel.HeroBackgroundRoute.home.rawValue,
            utilityRouteVisible: false,
            detailTitleID: TitleID(detailItem.titleId),
            homeFocusedTitleID: TitleID(homeItem.titleId),
            libraryFocusedTitleID: nil
        )
        let initialContext = viewModel.cachedHeroBackgroundContext

        XCTAssertEqual(initialContext.taskID, firstTaskID)
        XCTAssertEqual(initialContext.inputs.detailHeroBackgroundURL, detailItem.heroImageURL)
        XCTAssertEqual(initialContext.inputs.homeFocusedHeroBackgroundURL, homeItem.heroImageURL)

        let changedTaskID = viewModel.heroBackgroundTaskID(
            browseRouteRawValue: CloudLibrarySceneModel.HeroBackgroundRoute.library.rawValue,
            utilityRouteVisible: false,
            detailTitleID: TitleID(detailItem.titleId),
            homeFocusedTitleID: nil,
            libraryFocusedTitleID: TitleID(homeItem.titleId)
        )

        XCTAssertNotEqual(changedTaskID, firstTaskID)
    }

    func testCloudLibrarySceneInputsDriveSearchProjectionUpdates() {
        let viewModel = CloudLibraryViewModel()
        let matchingItem = CloudLibraryItem(
            titleId: "forza-title",
            productId: "forza-product",
            name: "Forza Horizon 5",
            shortDescription: "Arcade racing",
            artURL: URL(string: "https://example.com/forza-art.png"),
            posterImageURL: nil,
            heroImageURL: URL(string: "https://example.com/forza-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )
        let sections = [
            CloudLibrarySection(id: "library", name: "Library", items: [matchingItem])
        ]

        viewModel.applySceneMutation(
            inputs: CloudLibrarySceneInputs(
                library: CloudLibraryStateSnapshot(
                    state: LibraryState(
                        sections: sections,
                        itemsByTitleID: [:],
                        itemsByProductID: [:],
                        productDetails: [:],
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
                        detailRevision: 0,
                        homeRevision: 0,
                        sceneContentRevision: 1
                    )
                ),
                queryState: LibraryQueryState(),
                showsContinueBadge: false
            )
        )
        XCTAssertTrue(viewModel.cachedSearchResultItems.isEmpty)

        var matchingQuery = LibraryQueryState()
        matchingQuery.searchText = "Forza"

        viewModel.applySceneMutation(
            inputs: CloudLibrarySceneInputs(
                library: CloudLibraryStateSnapshot(
                    state: LibraryState(
                        sections: sections,
                        itemsByTitleID: [:],
                        itemsByProductID: [:],
                        productDetails: [:],
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
                        detailRevision: 0,
                        homeRevision: 0,
                        sceneContentRevision: 2
                    )
                ),
                queryState: matchingQuery,
                showsContinueBadge: false
            )
        )

        XCTAssertEqual(viewModel.cachedSearchResultItems.count, 1)
        XCTAssertEqual(viewModel.cachedSearchResultItems.first?.title, "Forza Horizon 5")
    }

    func testCloudLibrarySceneInputsRefreshHomeProjectionWhenArtworkChangesAtSameCount() {
        let viewModel = CloudLibraryViewModel()

        func makeItem(artURL: String) -> CloudLibraryItem {
            CloudLibraryItem(
                titleId: "forza-title",
                productId: "forza-product",
                name: "Forza Horizon 5",
                shortDescription: "Arcade racing",
                artURL: URL(string: artURL),
                posterImageURL: nil,
                heroImageURL: nil,
                galleryImageURLs: [],
                publisherName: "Xbox Game Studios",
                attributes: [],
                supportedInputTypes: [],
                isInMRU: false
            )
        }

        let initialSections = [
            CloudLibrarySection(id: "library", name: "Library", items: [makeItem(artURL: "https://example.com/forza-art-1.png")])
        ]
        let updatedSections = [
            CloudLibrarySection(id: "library", name: "Library", items: [makeItem(artURL: "https://example.com/forza-art-2.png")])
        ]

        viewModel.applySceneMutation(
            inputs: CloudLibrarySceneInputs(
                library: CloudLibraryStateSnapshot(
                    state: LibraryState(
                        sections: initialSections,
                        itemsByTitleID: [:],
                        itemsByProductID: [:],
                        productDetails: [:],
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
                        detailRevision: 0,
                        homeRevision: 0,
                        sceneContentRevision: 1
                    )
                ),
                queryState: LibraryQueryState(),
                showsContinueBadge: false
            )
        )
        let initialHeroURL = viewModel.cachedHomeState.heroBackgroundURL
        XCTAssertEqual(initialHeroURL, URL(string: "https://example.com/forza-art-1.png"))

        viewModel.applySceneMutation(
            inputs: CloudLibrarySceneInputs(
                library: CloudLibraryStateSnapshot(
                    state: LibraryState(
                        sections: updatedSections,
                        itemsByTitleID: [:],
                        itemsByProductID: [:],
                        productDetails: [:],
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
                        detailRevision: 0,
                        homeRevision: 0,
                        sceneContentRevision: 2
                    )
                ),
                queryState: LibraryQueryState(),
                showsContinueBadge: false
            )
        )

        XCTAssertEqual(viewModel.cachedHomeState.heroBackgroundURL, URL(string: "https://example.com/forza-art-2.png"))
        XCTAssertNotEqual(viewModel.cachedHomeState.heroBackgroundURL, initialHeroURL)
    }

    func testCloudLibraryViewModelBuildsHeroBackgroundInputsFromCachedState() {
        let viewModel = CloudLibraryViewModel()
        let detailItem = CloudLibraryItem(
            titleId: "detail-title",
            productId: "detail-product",
            name: "Avowed",
            shortDescription: "Detail hero",
            artURL: URL(string: "https://example.com/detail-art.png"),
            posterImageURL: URL(string: "https://example.com/detail-poster.png"),
            heroImageURL: URL(string: "https://example.com/detail-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )
        let homeItem = CloudLibraryItem(
            titleId: "home-title",
            productId: "home-product",
            name: "Halo Infinite",
            shortDescription: "Home hero",
            artURL: URL(string: "https://example.com/home-art.png"),
            posterImageURL: nil,
            heroImageURL: URL(string: "https://example.com/home-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )

        viewModel.cachedItemsByTitleID = [
            TitleID(detailItem.titleId): detailItem,
            TitleID(homeItem.titleId): homeItem
        ]
        viewModel.cachedHomeState = CloudLibraryHomeViewState(
            heroBackgroundURL: URL(string: "https://example.com/fallback-home-hero.png"),
            carouselItems: [],
            sections: []
        )
        viewModel.cachedLibraryState = CloudLibraryLibraryViewState(
            heroBackdropURL: URL(string: "https://example.com/fallback-library-hero.png"),
            tabs: [
                .init(id: "full-library", title: "Full library")
            ],
            selectedTabID: "full-library",
            filters: [],
            sortLabel: "Sort A-Z",
            displayMode: .grid,
            gridItems: []
        )
        viewModel.cachedSearchHeroURL = URL(string: "https://example.com/search-hero.png")

        let inputs = viewModel.heroBackgroundInputs(
            route: .library,
            utilityRouteVisible: false,
            detailTitleID: TitleID(rawValue: detailItem.titleId),
            homeFocusedTitleID: TitleID(rawValue: homeItem.titleId),
            libraryFocusedTitleID: TitleID(rawValue: "missing-title")
        )

        XCTAssertEqual(inputs.route, CloudLibrarySceneModel.HeroBackgroundRoute.library)
        XCTAssertEqual(inputs.detailHeroBackgroundURL, detailItem.heroImageURL)
        XCTAssertEqual(inputs.homeFocusedHeroBackgroundURL, homeItem.heroImageURL)
        XCTAssertNil(inputs.libraryFocusedHeroBackgroundURL)
        XCTAssertEqual(inputs.homeHeroBackgroundURL, URL(string: "https://example.com/fallback-home-hero.png"))
        XCTAssertEqual(inputs.libraryHeroBackgroundURL, URL(string: "https://example.com/fallback-library-hero.png"))
        XCTAssertEqual(inputs.searchHeroBackgroundURL, URL(string: "https://example.com/search-hero.png"))
    }

    func testCloudLibraryViewModelBuildsHeroBackgroundContextFromCachedState() {
        let viewModel = CloudLibraryViewModel()
        let detailItem = CloudLibraryItem(
            titleId: "detail-title",
            productId: "detail-product",
            name: "Avowed",
            shortDescription: "Detail hero",
            artURL: URL(string: "https://example.com/detail-art.png"),
            posterImageURL: URL(string: "https://example.com/detail-poster.png"),
            heroImageURL: URL(string: "https://example.com/detail-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )
        let homeItem = CloudLibraryItem(
            titleId: "home-title",
            productId: "home-product",
            name: "Halo Infinite",
            shortDescription: "Home hero",
            artURL: URL(string: "https://example.com/home-art.png"),
            posterImageURL: nil,
            heroImageURL: URL(string: "https://example.com/home-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )

        viewModel.cachedItemsByTitleID = [
            TitleID(detailItem.titleId): detailItem,
            TitleID(homeItem.titleId): homeItem
        ]
        viewModel.cachedHomeState = CloudLibraryHomeViewState(
            heroBackgroundURL: URL(string: "https://example.com/fallback-home-hero.png"),
            carouselItems: [],
            sections: []
        )
        viewModel.cachedLibraryState = CloudLibraryLibraryViewState(
            heroBackdropURL: URL(string: "https://example.com/fallback-library-hero.png"),
            tabs: [
                .init(id: "full-library", title: "Full library")
            ],
            selectedTabID: "full-library",
            filters: [],
            sortLabel: "Sort A-Z",
            displayMode: .grid,
            gridItems: []
        )
        viewModel.cachedSearchHeroURL = URL(string: "https://example.com/search-hero.png")

        let baselineContext = viewModel.heroBackgroundContext(
            browseRouteRawValue: "library",
            utilityRouteVisible: false,
            detailTitleID: TitleID(rawValue: detailItem.titleId),
            homeFocusedTitleID: TitleID(rawValue: homeItem.titleId),
            libraryFocusedTitleID: TitleID(rawValue: "missing-title")
        )
        let repeatedContext = viewModel.heroBackgroundContext(
            browseRouteRawValue: "library",
            utilityRouteVisible: false,
            detailTitleID: TitleID(rawValue: detailItem.titleId),
            homeFocusedTitleID: TitleID(rawValue: homeItem.titleId),
            libraryFocusedTitleID: TitleID(rawValue: "missing-title")
        )

        XCTAssertEqual(baselineContext.inputs.detailHeroBackgroundURL, detailItem.heroImageURL)
        XCTAssertEqual(baselineContext.inputs.homeFocusedHeroBackgroundURL, homeItem.heroImageURL)
        XCTAssertEqual(baselineContext.taskID, repeatedContext.taskID)

        let changedContext = viewModel.heroBackgroundContext(
            browseRouteRawValue: "search",
            utilityRouteVisible: false,
            detailTitleID: nil,
            homeFocusedTitleID: TitleID(rawValue: homeItem.titleId),
            libraryFocusedTitleID: nil
        )

        XCTAssertEqual(changedContext.inputs.route, CloudLibrarySceneModel.HeroBackgroundRoute.search)
        XCTAssertEqual(changedContext.inputs.searchHeroBackgroundURL, URL(string: "https://example.com/search-hero.png"))
        XCTAssertNotEqual(changedContext.taskID, baselineContext.taskID)
    }

    func testCloudLibraryViewModelCachesHeroBackgroundContextFromState() {
        let viewModel = CloudLibraryViewModel()
        let detailItem = CloudLibraryItem(
            titleId: "detail-title",
            productId: "detail-product",
            name: "Avowed",
            shortDescription: "Detail hero",
            artURL: URL(string: "https://example.com/detail-art.png"),
            posterImageURL: URL(string: "https://example.com/detail-poster.png"),
            heroImageURL: URL(string: "https://example.com/detail-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )
        let homeItem = CloudLibraryItem(
            titleId: "home-title",
            productId: "home-product",
            name: "Halo Infinite",
            shortDescription: "Home hero",
            artURL: URL(string: "https://example.com/home-art.png"),
            posterImageURL: nil,
            heroImageURL: URL(string: "https://example.com/home-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )

        viewModel.cachedItemsByTitleID = [
            TitleID(detailItem.titleId): detailItem,
            TitleID(homeItem.titleId): homeItem
        ]
        viewModel.cachedHomeState = CloudLibraryHomeViewState(
            heroBackgroundURL: URL(string: "https://example.com/fallback-home-hero.png"),
            carouselItems: [],
            sections: []
        )
        viewModel.cachedLibraryState = CloudLibraryLibraryViewState(
            heroBackdropURL: URL(string: "https://example.com/fallback-library-hero.png"),
            tabs: [
                .init(id: "full-library", title: "Full library")
            ],
            selectedTabID: "full-library",
            filters: [],
            sortLabel: "Sort A-Z",
            displayMode: .grid,
            gridItems: []
        )
        viewModel.cachedSearchHeroURL = URL(string: "https://example.com/search-hero.png")

        let taskID = viewModel.heroBackgroundTaskID(
            browseRouteRawValue: "library",
            utilityRouteVisible: false,
            detailTitleID: TitleID(rawValue: detailItem.titleId),
            homeFocusedTitleID: TitleID(rawValue: homeItem.titleId),
            libraryFocusedTitleID: nil
        )

        viewModel.rebuildHeroBackgroundContext(
            browseRouteRawValue: "library",
            utilityRouteVisible: false,
            detailTitleID: TitleID(rawValue: detailItem.titleId),
            homeFocusedTitleID: TitleID(rawValue: homeItem.titleId),
            libraryFocusedTitleID: nil
        )

        XCTAssertEqual(viewModel.cachedHeroBackgroundContext.taskID, taskID)
        XCTAssertEqual(
            viewModel.cachedHeroBackgroundContext.inputs.detailHeroBackgroundURL,
            detailItem.heroImageURL
        )
        XCTAssertEqual(
            viewModel.cachedHeroBackgroundContext.inputs.homeFocusedHeroBackgroundURL,
            homeItem.heroImageURL
        )
        XCTAssertEqual(viewModel.cachedHeroBackgroundContext.inputs.route, CloudLibrarySceneModel.HeroBackgroundRoute.library)
    }
}
