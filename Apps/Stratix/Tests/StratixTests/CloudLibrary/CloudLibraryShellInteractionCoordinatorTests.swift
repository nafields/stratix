// CloudLibraryShellInteractionCoordinatorTests.swift
// Exercises cloud library shell interaction coordinator behavior.
//

import XCTest
import StratixModels
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

@MainActor
final class CloudLibraryShellInteractionCoordinatorTests: XCTestCase {
    func testOpenDetail_prewarmsBeforePushingRoute() async {
        let coordinator = CloudLibraryShellInteractionCoordinator()
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()
        let viewModel = CloudLibraryViewModel()
        let titleID = TitleID("halo-title")
        let item = CloudLibraryTestSupport.makeItem(titleID: titleID.rawValue)
        let stateSnapshot = CloudLibraryTestSupport.makeLibraryStateSnapshot(
            sections: [.init(id: "library", name: "Library", items: [item])]
        )
        var steps: [String] = []

        await coordinator.openDetail(
            titleID,
            routeState: routeState,
            focusState: focusState,
            stateSnapshot: stateSnapshot,
            viewModel: viewModel,
            prewarmDetailState: { receivedTitleID in
                XCTAssertEqual(receivedTitleID, titleID)
                steps.append("prewarm")
                XCTAssertTrue(routeState.detailPath.isEmpty)
            }
        )

        steps.append("route")
        XCTAssertEqual(steps, ["prewarm", "route"])
        XCTAssertEqual(routeState.detailPath, [titleID])
        XCTAssertEqual(focusState.focusedTileID(for: .home), titleID)
        XCTAssertEqual(focusState.settledHeroTileID(for: .home), titleID)
    }

    func testApplySceneMutation_rebuildsViewModelFromStateAdapterAndQueryState() {
        let coordinator = CloudLibraryShellInteractionCoordinator()
        let sceneModel = CloudLibrarySceneModel()
        let viewModel = CloudLibraryViewModel()
        let recent = CloudLibraryTestSupport.makeItem(
            titleID: "recent-title",
            productID: "recent-product",
            name: "Recent Game"
        )
        let library = CloudLibraryTestSupport.makeItem(
            titleID: "library-title",
            productID: "library-product",
            name: "Library Game"
        )
        let snapshot = CloudLibraryTestSupport.makeLibraryStateSnapshot(
            sections: [
                CloudLibrarySection(
                    id: "library",
                    name: "Library",
                    items: [recent, library]
                )
            ],
            sceneContentRevision: 3
        )
        var queryState = LibraryQueryState()
        queryState.selectedTabID = "my-games"

        coordinator.applySceneMutation(
            sceneModel: sceneModel,
            stateSnapshot: snapshot,
            queryState: queryState,
            quickResumeTile: true,
            viewModel: viewModel
        )

        XCTAssertEqual(viewModel.cachedLibraryCount, 2)
        XCTAssertEqual(viewModel.cachedItemsByTitleID[TitleID("recent-title")]?.productId, "recent-product")
        XCTAssertEqual(viewModel.cachedLibraryState.selectedTabID, "my-games")
        XCTAssertEqual(viewModel.cachedLibraryState.gridItems.map(\.titleID), [TitleID("library-title"), TitleID("recent-title")])
        XCTAssertTrue(viewModel.cachedHomeState.sections.isEmpty)
    }

    func testApplyStatusMutation_usesHomeRouteAndCachedHomeState() {
        let coordinator = CloudLibraryShellInteractionCoordinator()
        let sceneModel = CloudLibrarySceneModel()
        let routeState = CloudLibraryRouteState()
        let item = CloudLibraryTestSupport.makeItem()
        let state = LibraryState(
            sections: [CloudLibrarySection(id: "library", name: "Library", items: [item])],
            itemsByTitleID: [TitleID(item.titleId): item],
            itemsByProductID: [ProductID(item.productId): item],
            productDetails: [:],
            isLoading: false,
            lastError: nil,
            needsReauth: false,
            lastHydratedAt: nil,
            cacheSavedAt: nil,
            isArtworkPrefetchThrottled: false,
            homeMerchandising: HomeMerchandisingSnapshot(
                recentlyAddedItems: [item],
                rows: [.init(alias: "featured", label: "Featured", source: .fixedPriority, items: [item])]
            ),
            discoveryEntries: [],
            isHomeMerchandisingLoading: false,
            hasCompletedInitialHomeMerchandising: true,
            homeMerchandisingSessionSource: .liveRecovery,
            hasRecoveredLiveHomeMerchandisingThisSession: true,
            catalogRevision: 1,
            detailRevision: 0,
            homeRevision: 1,
            sceneContentRevision: 1
        )
        let snapshot = CloudLibraryStateSnapshot(state: state)
        let loadState = CloudLibraryLoadStateBuilder().makeLoadState(from: snapshot)
        let viewModel = CloudLibraryViewModel()
        viewModel.cachedHomeState = CloudLibraryHomeViewState(
            heroBackgroundURL: nil,
            carouselItems: [
                .init(
                    id: "carousel:\(item.titleId)",
                    titleID: item.typedTitleID,
                    title: item.name,
                    subtitle: nil,
                    categoryLabel: nil,
                    ratingBadgeText: nil,
                    description: nil,
                    heroBackgroundURL: item.heroImageURL,
                    artworkURL: item.artURL
                )
            ],
            sections: []
        )

        coordinator.applyStatusMutation(
            sceneModel: sceneModel,
            routeState: routeState,
            loadState: loadState,
            stateSnapshot: snapshot,
            viewModel: viewModel
        )

        XCTAssertTrue(sceneModel.statusState.homeMerchandisingReady)
        XCTAssertTrue(sceneModel.statusState.homeMerchandisingStateValue.contains("route=home"))
        XCTAssertTrue(sceneModel.statusState.homeMerchandisingStateValue.contains("ready=1"))

        routeState.setBrowseRoute(.library)
        coordinator.applyStatusMutation(
            sceneModel: sceneModel,
            routeState: routeState,
            loadState: loadState,
            stateSnapshot: snapshot,
            viewModel: viewModel
        )

        XCTAssertFalse(sceneModel.statusState.homeMerchandisingReady)
        XCTAssertTrue(sceneModel.statusState.homeMerchandisingStateValue.contains("route=other"))
    }

    func testApplyRouteMutation_forwardsBrowseAndUtilityRawValues() {
        let coordinator = CloudLibraryShellInteractionCoordinator()
        let sceneModel = CloudLibrarySceneModel()
        let routeState = CloudLibraryRouteState()

        routeState.setBrowseRoute(.library)
        routeState.openUtilityRoute(.settings)

        coordinator.applyRouteMutation(
            sceneModel: sceneModel,
            routeState: routeState
        )

        XCTAssertEqual(sceneModel.routeState.currentSurfaceID, ShellUtilityRoute.settings.rawValue)
        XCTAssertEqual(sceneModel.routeState.selectedSideRailNavID, .library)
    }

    func testRebuildHeroBackgroundContext_usesDetailAndFocusedTileIDs() {
        let coordinator = CloudLibraryShellInteractionCoordinator()
        let viewModel = CloudLibraryViewModel()
        let routeState = CloudLibraryRouteState()
        let focusState = CloudLibraryFocusState()
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
        routeState.setBrowseRoute(.home)
        routeState.pushDetail(TitleID(detailItem.titleId))
        focusState.setFocusedTileID(TitleID(homeItem.titleId), for: .home)
        focusState.setSettledHeroTileID(TitleID(homeItem.titleId), for: .home)

        coordinator.rebuildHeroBackgroundContext(
            viewModel: viewModel,
            routeState: routeState,
            focusState: focusState
        )

        XCTAssertEqual(viewModel.cachedHeroBackgroundContext.inputs.route, .home)
        XCTAssertEqual(
            viewModel.cachedHeroBackgroundContext.inputs.detailHeroBackgroundURL,
            detailItem.heroImageURL
        )
        XCTAssertEqual(
            viewModel.cachedHeroBackgroundContext.inputs.homeFocusedHeroBackgroundURL,
            homeItem.heroImageURL
        )
    }

    func testApplyHeroBackgroundMutation_forwardsCachedHeroBackgroundInputs() {
        let coordinator = CloudLibraryShellInteractionCoordinator()
        let sceneModel = CloudLibrarySceneModel()
        let viewModel = CloudLibraryViewModel()
        let expectedURL = URL(string: "https://example.com/detail-hero.png")
        viewModel.cachedHeroBackgroundContext = CloudLibraryHeroBackgroundContext(
            inputs: .init(
                route: .library,
                utilityRouteVisible: false,
                detailHeroBackgroundURL: expectedURL,
                homeFocusedHeroBackgroundURL: nil,
                libraryFocusedHeroBackgroundURL: nil,
                homeHeroBackgroundURL: nil,
                libraryHeroBackgroundURL: nil,
                searchHeroBackgroundURL: nil
            ),
            taskID: 42
        )

        coordinator.applyHeroBackgroundMutation(
            sceneModel: sceneModel,
            viewModel: viewModel
        )

        XCTAssertEqual(sceneModel.heroBackgroundState.shellHeroBackgroundURL, expectedURL)
    }
}
