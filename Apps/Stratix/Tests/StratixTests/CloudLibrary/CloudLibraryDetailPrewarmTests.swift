// CloudLibraryDetailPrewarmTests.swift
// Exercises cloud library detail prewarm behavior.
//

import XCTest
import StratixModels
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

@MainActor
final class CloudLibraryDetailPrewarmTests: XCTestCase {
    func testPrewarmDetail_buildsDetailSnapshotBeforeRoutePush() async {
        let coordinator = CloudLibraryDetailPrewarmCoordinator()
        let viewModel = CloudLibraryViewModel()
        let item = CloudLibraryTestSupport.makeItem()
        let titleID = TitleID(rawValue: item.titleId)
        let productID = ProductID(rawValue: item.productId)
        let detail = CloudLibraryTestSupport.makeDetail(productId: item.productId, title: item.name)
        let achievementSnapshot = makeAchievementSnapshot(titleID: titleID)
        var detailLoads = 0
        var achievementLoads = 0

        await coordinator.prewarmDetailState(
            titleID: titleID,
            item: item,
            originRoute: .home,
            viewModel: viewModel,
            loadDetail: { receivedProductID in
                XCTAssertEqual(receivedProductID, productID)
                detailLoads += 1
            },
            loadAchievements: { receivedTitleID in
                XCTAssertEqual(receivedTitleID, titleID)
                achievementLoads += 1
            },
            productDetail: { receivedProductID in
                XCTAssertEqual(receivedProductID, productID)
                return detail
            },
            achievementSnapshot: { receivedTitleID in
                XCTAssertEqual(receivedTitleID, titleID)
                return achievementSnapshot
            },
            achievementErrorText: { _ in nil }
        )

        XCTAssertEqual(detailLoads, 1)
        XCTAssertEqual(achievementLoads, 1)
        XCTAssertNotNil(viewModel.detailStateCache.peek(titleID))
        XCTAssertFalse(viewModel.detailHydrationInFlightTitleIDs.contains(titleID))
    }

    func testPrewarmDetail_reusesFreshCacheWithoutDuplicateDetailAndAchievementLoads() async {
        let coordinator = CloudLibraryDetailPrewarmCoordinator()
        let viewModel = CloudLibraryViewModel()
        let item = CloudLibraryTestSupport.makeItem()
        let titleID = TitleID(rawValue: item.titleId)
        let detail = CloudLibraryTestSupport.makeDetail(productId: item.productId, title: item.name)
        let achievementSnapshot = makeAchievementSnapshot(titleID: titleID)
        var detailLoads = 0
        var achievementLoads = 0

        let loadDetail: @MainActor (ProductID) async -> Void = { _ in
            detailLoads += 1
        }
        let loadAchievements: @MainActor (TitleID) async -> Void = { _ in
            achievementLoads += 1
        }
        let productDetail: @MainActor (ProductID) -> CloudLibraryProductDetail? = { _ in detail }
        let achievementLookup: @MainActor (TitleID) -> TitleAchievementSnapshot? = { _ in achievementSnapshot }

        await coordinator.prewarmDetailState(
            titleID: titleID,
            item: item,
            originRoute: .home,
            viewModel: viewModel,
            loadDetail: loadDetail,
            loadAchievements: loadAchievements,
            productDetail: productDetail,
            achievementSnapshot: achievementLookup,
            achievementErrorText: { _ in nil }
        )
        await coordinator.prewarmDetailState(
            titleID: titleID,
            item: item,
            originRoute: .home,
            viewModel: viewModel,
            loadDetail: loadDetail,
            loadAchievements: loadAchievements,
            productDetail: productDetail,
            achievementSnapshot: achievementLookup,
            achievementErrorText: { _ in nil }
        )

        XCTAssertEqual(detailLoads, 1)
        XCTAssertEqual(achievementLoads, 1)
        XCTAssertNotNil(viewModel.detailStateCache.peek(titleID))
    }

    private func makeAchievementSnapshot(titleID: TitleID) -> TitleAchievementSnapshot {
        TitleAchievementSnapshot(
            titleId: titleID.rawValue,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            summary: TitleAchievementSummary(
                titleId: titleID.rawValue,
                totalAchievements: 10,
                unlockedAchievements: 2,
                totalGamerscore: 100
            ),
            achievements: []
        )
    }
}
