// LibraryHydrationPublicationCoordinatorTests.swift
// Exercises library hydration publication coordinator behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing

@MainActor
@Suite(.serialized)
struct LibraryHydrationPublicationCoordinatorTests {
    @Test
    func publish_appliesRouteRestoreBeforeDetailsStage() async {
        let controller = LibraryController()
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date(timeIntervalSince1970: 1_701_111_111))
        let actions: [LibraryAction] = [
            .hydrationProductDetailsStateApplied(
                .liveRecovery(details: [ProductID("product-1"): CloudLibraryProductDetail(productId: "product-1", title: "Halo Infinite")])
            ),
            .hydrationPublishedStateApplied(.cacheRestore(snapshot: snapshot))
        ]

        let result = await LibraryHydrationPublicationCoordinator().publish(
            actions: actions,
            plan: LibraryHydrationPublicationPlan(stages: [.routeRestore, .detailsAndSecondaryRows]),
            controller: controller
        )

        #expect(result.completedStages == [.routeRestore, .detailsAndSecondaryRows])
        #expect(controller.sections.map(\.id) == ["library"])
        #expect(controller.productDetails[ProductID("product-1")]?.title == "Halo Infinite")
    }

    @Test
    func publish_skipsDetailsStage_whenNoDetailActionsExist() async {
        let controller = LibraryController()
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date(timeIntervalSince1970: 1_702_222_222))

        let result = await LibraryHydrationPublicationCoordinator().publish(
            actions: [.hydrationPublishedStateApplied(.cacheRestore(snapshot: snapshot))],
            plan: LibraryHydrationPublicationPlan(stages: [.routeRestore, .detailsAndSecondaryRows]),
            controller: controller
        )

        #expect(result.completedStages == [.routeRestore])
        #expect(controller.sections.map(\.id) == ["library"])
    }

    @Test
    func publish_runsBackgroundArtworkLast() async {
        let controller = LibraryController()
        let snapshot = TestHydrationFixtures.unifiedSnapshot(savedAt: Date(timeIntervalSince1970: 1_703_333_333))

        let result = await LibraryHydrationPublicationCoordinator().publish(
            actions: [.hydrationPublishedStateApplied(.cacheRestore(snapshot: snapshot))],
            plan: LibraryHydrationPublicationPlan(stages: [.routeRestore, .visibleRows, .backgroundArtwork]),
            controller: controller
        )

        #expect(result.completedStages.last == .backgroundArtwork)
        #expect(controller.sections.map(\.id) == ["library"])
    }
}
