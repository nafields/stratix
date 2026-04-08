// CloudLibrarySceneStateTests.swift
// Exercises cloud library scene state behavior.
//

import XCTest
import StratixModels

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibrarySceneStateTests: XCTestCase {
    func testStatusState_onlyReportsReadyWhenLiveHomeMerchandisingHasContent() {
        let homeState = CloudLibraryHomeViewState(
            heroBackgroundURL: nil,
            carouselItems: [makeCarouselItem(id: "hero")],
            sections: []
        )

        let state = CloudLibrarySceneStatusState.resolve(
            current: .init(),
            isHomeRoute: true,
            loadState: .liveFresh,
            sections: [makeSection(id: "home")],
            hasCompletedInitialHomeMerchandising: true,
            hasRecoveredLiveHomeMerchandisingThisSession: true,
            hasHomeMerchandisingSnapshot: true,
            homeState: homeState
        )

        XCTAssertTrue(state.hasCompletedInitialLibraryLoad)
        XCTAssertTrue(state.homeMerchandisingReady)
        XCTAssertTrue(state.homeMerchandisingStateValue.contains("ready=1"))
    }

    func testRouteState_prefersUtilitySurfaceButKeepsBrowseNavSelection() {
        let state = CloudLibrarySceneRouteState.resolve(
            browseRouteRawValue: "library",
            utilityRouteRawValue: ShellUtilityRoute.settings.rawValue
        )

        XCTAssertEqual(state.currentSurfaceID, ShellUtilityRoute.settings.rawValue)
        XCTAssertEqual(state.selectedSideRailNavID, .library)
    }

    func testHeroBackgroundState_prefersDetailThenFocusedRouteBackground() {
        let detailURL = URL(string: "https://example.com/detail.jpg")
        let homeURL = URL(string: "https://example.com/home.jpg")
        let focusedURL = URL(string: "https://example.com/home-focused.jpg")

        let detailState = CloudLibraryHeroBackgroundState.resolve(
            inputs: .init(
                route: .home,
                utilityRouteVisible: true,
                detailHeroBackgroundURL: detailURL,
                homeFocusedHeroBackgroundURL: focusedURL,
                libraryFocusedHeroBackgroundURL: nil,
                homeHeroBackgroundURL: homeURL,
                libraryHeroBackgroundURL: nil,
                searchHeroBackgroundURL: nil
            )
        )
        XCTAssertEqual(detailState.shellHeroBackgroundURL, detailURL)

        let focusedState = CloudLibraryHeroBackgroundState.resolve(
            inputs: .init(
                route: .home,
                utilityRouteVisible: true,
                detailHeroBackgroundURL: nil,
                homeFocusedHeroBackgroundURL: focusedURL,
                libraryFocusedHeroBackgroundURL: nil,
                homeHeroBackgroundURL: homeURL,
                libraryHeroBackgroundURL: nil,
                searchHeroBackgroundURL: nil
            )
        )
        XCTAssertEqual(focusedState.shellHeroBackgroundURL, focusedURL)
    }

    @MainActor
    func testCloudLibrarySceneModelMarksInitialLoadCompleteFromLoadStateTransitions() {
        let sceneModel = CloudLibrarySceneModel()
        XCTAssertFalse(sceneModel.statusState.hasCompletedInitialLibraryLoad)

        sceneModel.reconcileInitialLibraryLoadState(loadState: .notLoaded)
        XCTAssertFalse(sceneModel.statusState.hasCompletedInitialLibraryLoad)

        sceneModel.reconcileInitialLibraryLoadState(loadState: .restoredCached(ageSeconds: 60))
        XCTAssertTrue(sceneModel.statusState.hasCompletedInitialLibraryLoad)

        sceneModel.statusState.hasCompletedInitialLibraryLoad = false
        sceneModel.reconcileInitialLibraryLoadState(loadState: .failedNoCache(error: "network_failed"))
        XCTAssertTrue(sceneModel.statusState.hasCompletedInitialLibraryLoad)
    }

    @MainActor
    func testCloudLibrarySceneModelPublishesStoredRouteState() {
        let sceneModel = CloudLibrarySceneModel()

        sceneModel.applyRouteMutation(
            browseRouteRawValue: "library",
            utilityRouteRawValue: nil
        )
        XCTAssertEqual(sceneModel.routeState.selectedSideRailNavID, .library)
        XCTAssertEqual(sceneModel.routeState.currentSurfaceID, "library")

        sceneModel.applyRouteMutation(
            browseRouteRawValue: "home",
            utilityRouteRawValue: "settings"
        )
        XCTAssertEqual(sceneModel.routeState.selectedSideRailNavID, .home)
        XCTAssertEqual(sceneModel.routeState.currentSurfaceID, "settings")

        sceneModel.applyRouteMutation(
            browseRouteRawValue: "unknown",
            utilityRouteRawValue: nil
        )
        XCTAssertEqual(sceneModel.routeState.selectedSideRailNavID, .home)
        XCTAssertEqual(sceneModel.routeState.currentSurfaceID, "unknown")
    }

    @MainActor
    func testCloudLibrarySceneModelClassifiesMajorRefreshWhenHydrationMarkerChanges() {
        let sceneModel = CloudLibrarySceneModel()
        let hydratedAt = Date(timeIntervalSince1970: 1_000)
        let sections = [
            CloudLibrarySection(
                id: "library",
                name: "Library",
                items: [
                    CloudLibraryItem(
                        titleId: "forza-title",
                        productId: "forza-product",
                        name: "Forza Horizon 5",
                        shortDescription: "Arcade racing",
                        artURL: URL(string: "https://example.com/forza-art.png"),
                        posterImageURL: nil,
                        heroImageURL: nil,
                        galleryImageURLs: [],
                        publisherName: "Xbox Game Studios",
                        attributes: [],
                        supportedInputTypes: [],
                        isInMRU: false
                    )
                ]
            )
        ]

        sceneModel.noteHydrationMarker(hydratedAt)

        XCTAssertFalse(
            sceneModel.isMajorLibraryRefresh(
                oldSections: sections,
                newSections: sections,
                currentHydratedAt: hydratedAt
            )
        )

        XCTAssertTrue(
            sceneModel.isMajorLibraryRefresh(
                oldSections: sections,
                newSections: sections,
                currentHydratedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
    }

    @MainActor
    func testCloudLibrarySceneModelStatusMutationPublishesStoredStatusState() {
        let sceneModel = CloudLibrarySceneModel()
        let readyHomeState = CloudLibraryHomeViewState(
            heroBackgroundURL: URL(string: "https://example.com/hero.png"),
            carouselItems: [],
            sections: [
                CloudLibraryRailSectionViewState(
                    id: "recent",
                    alias: "recent",
                    title: "Jump Back In",
                    subtitle: nil,
                    items: [
                        .title(
                            .init(
                                id: "forza-tile",
                                tile: .init(
                                    id: "forza-tile",
                                    titleID: TitleID("forza-title"),
                                    title: "Forza Horizon 5",
                                    subtitle: "Arcade racing",
                                    artworkURL: URL(string: "https://example.com/hero.png")
                                ),
                                action: .openDetail
                            )
                        )
                    ]
                )
            ]
        )

        sceneModel.applyStatusMutation(
            isHomeRoute: true,
            loadState: .notLoaded,
            sections: [],
            hasCompletedInitialHomeMerchandising: false,
            hasRecoveredLiveHomeMerchandisingThisSession: false,
            hasHomeMerchandisingSnapshot: false,
            homeState: readyHomeState
        )
        XCTAssertFalse(sceneModel.statusState.homeMerchandisingReady)
        XCTAssertEqual(
            sceneModel.statusState.homeMerchandisingStateValue,
            "route=home;ready=0;loadState=notLoaded;libraryLoaded=0;initial=0;live=0;snapshot=0;catalogSections=0;catalogItems=0;carousel=0;rails=1"
        )

        sceneModel.applyStatusMutation(
            isHomeRoute: true,
            loadState: .degradedCached(error: "offline_error", ageSeconds: 90),
            sections: [
                CloudLibrarySection(id: "library", name: "Library", items: [])
            ],
            hasCompletedInitialHomeMerchandising: false,
            hasRecoveredLiveHomeMerchandisingThisSession: false,
            hasHomeMerchandisingSnapshot: false,
            homeState: readyHomeState
        )
        XCTAssertFalse(sceneModel.statusState.homeMerchandisingReady)
        XCTAssertEqual(
            sceneModel.statusState.homeMerchandisingStateValue,
            "route=home;ready=0;loadState=degradedCached(90);libraryLoaded=1;initial=0;live=0;snapshot=0;catalogSections=1;catalogItems=0;carousel=0;rails=1"
        )

        sceneModel.applyStatusMutation(
            isHomeRoute: true,
            loadState: .liveFresh,
            sections: [
                CloudLibrarySection(id: "library", name: "Library", items: [])
            ],
            hasCompletedInitialHomeMerchandising: true,
            hasRecoveredLiveHomeMerchandisingThisSession: true,
            hasHomeMerchandisingSnapshot: true,
            homeState: readyHomeState
        )
        XCTAssertTrue(sceneModel.statusState.homeMerchandisingReady)
        XCTAssertEqual(
            sceneModel.statusState.homeMerchandisingStateValue,
            "route=home;ready=1;loadState=liveFresh;libraryLoaded=1;initial=1;live=1;snapshot=1;catalogSections=1;catalogItems=0;carousel=0;rails=1"
        )

        sceneModel.applyStatusMutation(
            isHomeRoute: false,
            loadState: .liveFresh,
            sections: [
                CloudLibrarySection(id: "library", name: "Library", items: [])
            ],
            hasCompletedInitialHomeMerchandising: true,
            hasRecoveredLiveHomeMerchandisingThisSession: true,
            hasHomeMerchandisingSnapshot: true,
            homeState: readyHomeState
        )
        XCTAssertFalse(sceneModel.statusState.homeMerchandisingReady)
        XCTAssertEqual(
            sceneModel.statusState.homeMerchandisingStateValue,
            "route=other;ready=0;loadState=liveFresh;libraryLoaded=1;initial=1;live=1;snapshot=1;catalogSections=1;catalogItems=0;carousel=0;rails=1"
        )
    }

    @MainActor
    func testCloudLibrarySceneModelStatusMutationTaskIDTracksLoadStateContract() throws {
        let sceneModel = CloudLibrarySceneModel()
        let homeState = CloudLibraryHomeViewState(heroBackgroundURL: nil, carouselItems: [], sections: [])
        let sections = [CloudLibrarySection(id: "library", name: "Library", items: [])]

        let notLoadedID = sceneModel.statusMutationTaskID(
            isHomeRoute: true,
            loadState: .notLoaded,
            sections: sections,
            hasCompletedInitialHomeMerchandising: false,
            hasRecoveredLiveHomeMerchandisingThisSession: false,
            hasHomeMerchandisingSnapshot: false,
            homeState: homeState
        )
        let refreshingID = sceneModel.statusMutationTaskID(
            isHomeRoute: true,
            loadState: .refreshingFromCache(ageSeconds: 30),
            sections: sections,
            hasCompletedInitialHomeMerchandising: false,
            hasRecoveredLiveHomeMerchandisingThisSession: false,
            hasHomeMerchandisingSnapshot: false,
            homeState: homeState
        )

        XCTAssertNotEqual(notLoadedID, refreshingID)
    }

    @MainActor
    func testCloudLibrarySceneModelPublishesShellHeroBackgroundState() throws {
        let sceneModel = CloudLibrarySceneModel()

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
        let libraryItem = CloudLibraryItem(
            titleId: "library-title",
            productId: "library-product",
            name: "Forza Horizon 5",
            shortDescription: "Library hero",
            artURL: URL(string: "https://example.com/library-art.png"),
            posterImageURL: nil,
            heroImageURL: URL(string: "https://example.com/library-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )
        let detailItem = CloudLibraryItem(
            titleId: "detail-title",
            productId: "detail-product",
            name: "Avowed",
            shortDescription: "Detail hero",
            artURL: URL(string: "https://example.com/detail-art.png"),
            posterImageURL: nil,
            heroImageURL: URL(string: "https://example.com/detail-hero.png"),
            galleryImageURLs: [],
            publisherName: nil,
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )
        sceneModel.applyHeroBackgroundMutation(
            inputs: .init(
                route: .home,
                utilityRouteVisible: false,
                detailHeroBackgroundURL: nil,
                homeFocusedHeroBackgroundURL: homeItem.heroImageURL,
                libraryFocusedHeroBackgroundURL: nil,
                homeHeroBackgroundURL: URL(string: "https://example.com/fallback-home-hero.png"),
                libraryHeroBackgroundURL: URL(string: "https://example.com/fallback-library-hero.png"),
                searchHeroBackgroundURL: URL(string: "https://example.com/search-hero.png")
            )
        )
        XCTAssertNil(sceneModel.heroBackgroundState.shellHeroBackgroundURL)

        sceneModel.applyHeroBackgroundMutation(
            inputs: .init(
                route: .home,
                utilityRouteVisible: true,
                detailHeroBackgroundURL: nil,
                homeFocusedHeroBackgroundURL: homeItem.heroImageURL,
                libraryFocusedHeroBackgroundURL: nil,
                homeHeroBackgroundURL: URL(string: "https://example.com/fallback-home-hero.png"),
                libraryHeroBackgroundURL: URL(string: "https://example.com/fallback-library-hero.png"),
                searchHeroBackgroundURL: URL(string: "https://example.com/search-hero.png")
            )
        )
        XCTAssertEqual(
            sceneModel.heroBackgroundState.shellHeroBackgroundURL,
            URL(string: "https://example.com/home-hero.png")
        )

        sceneModel.applyHeroBackgroundMutation(
            inputs: .init(
                route: .library,
                utilityRouteVisible: false,
                detailHeroBackgroundURL: nil,
                homeFocusedHeroBackgroundURL: nil,
                libraryFocusedHeroBackgroundURL: libraryItem.heroImageURL,
                homeHeroBackgroundURL: URL(string: "https://example.com/fallback-home-hero.png"),
                libraryHeroBackgroundURL: URL(string: "https://example.com/fallback-library-hero.png"),
                searchHeroBackgroundURL: URL(string: "https://example.com/search-hero.png")
            )
        )
        XCTAssertEqual(
            sceneModel.heroBackgroundState.shellHeroBackgroundURL,
            URL(string: "https://example.com/library-hero.png")
        )

        sceneModel.applyHeroBackgroundMutation(
            inputs: .init(
                route: .library,
                utilityRouteVisible: false,
                detailHeroBackgroundURL: detailItem.heroImageURL,
                homeFocusedHeroBackgroundURL: nil,
                libraryFocusedHeroBackgroundURL: libraryItem.heroImageURL,
                homeHeroBackgroundURL: URL(string: "https://example.com/fallback-home-hero.png"),
                libraryHeroBackgroundURL: URL(string: "https://example.com/fallback-library-hero.png"),
                searchHeroBackgroundURL: URL(string: "https://example.com/search-hero.png")
            )
        )
        XCTAssertEqual(
            sceneModel.heroBackgroundState.shellHeroBackgroundURL,
            URL(string: "https://example.com/detail-hero.png")
        )
    }

    private func makeSection(id: String) -> CloudLibrarySection {
        CloudLibrarySection(
            id: id,
            name: id,
            items: [
                CloudLibraryItem(
                    titleId: "title-\(id)",
                    productId: "product-\(id)",
                    name: "Title \(id)",
                    shortDescription: nil,
                    artURL: nil,
                    supportedInputTypes: ["gamepad"],
                    isInMRU: false
                )
            ]
        )
    }

    private func makeCarouselItem(id: String) -> CloudLibraryHomeCarouselItemViewState {
        .init(
            id: id,
            titleID: TitleID(rawValue: id),
            title: "Hero \(id)",
            subtitle: nil,
            categoryLabel: nil,
            ratingBadgeText: nil,
            description: nil,
            heroBackgroundURL: nil,
            artworkURL: nil
        )
    }
}
