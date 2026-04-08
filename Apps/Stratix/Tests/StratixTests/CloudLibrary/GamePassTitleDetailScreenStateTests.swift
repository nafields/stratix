// GamePassTitleDetailScreenStateTests.swift
// Exercises game pass title detail screen state behavior.
//

import Foundation
import Testing
import StratixModels
@testable import StratixCore
@testable import Stratix

@MainActor
@Suite
struct GamePassTitleDetailScreenStateTests {
    @Test
    func detailStateCarriesTypedIdentityAndExplicitPanelsWithoutControllers() {
        let item = CloudLibraryTestSupport.makeItem(
            titleID: "halo-title",
            productID: "halo-product",
            name: "Halo Infinite"
        )
        let detail = CloudLibraryProductDetail(
            productId: "halo-product",
            title: "Halo Infinite",
            publisherName: "Xbox Game Studios",
            shortDescription: "Short detail",
            longDescription: "Long detail",
            developerName: "343 Industries",
            releaseDate: "2021-12-08",
            capabilityLabels: ["HDR"],
            genreLabels: ["Shooter"],
            mediaAssets: [
                .init(
                    kind: .image,
                    url: URL(string: "https://example.com/shot.png")!,
                    title: "Screenshot",
                    source: .productDetails
                ),
                .init(
                    kind: .video,
                    url: URL(string: "https://example.com/trailer.mp4")!,
                    thumbnailURL: URL(string: "https://example.com/trailer.png"),
                    title: "Launch Trailer",
                    source: .productDetails
                )
            ],
            galleryImageURLs: [],
            trailers: [],
            achievementSummary: nil
        )
        let snapshot = TitleAchievementSnapshot(
            titleId: item.titleId,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            summary: TitleAchievementSummary(
                titleId: item.titleId,
                titleName: item.name,
                totalAchievements: 50,
                unlockedAchievements: 12,
                totalGamerscore: 1_000,
                unlockedGamerscore: 120,
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            achievements: [
                .init(
                    id: "ach-1",
                    name: "Finish Mission",
                    detail: "Complete the mission",
                    unlocked: true,
                    percentComplete: 100,
                    gamerscore: 20
                )
            ]
        )

        let state = CloudLibraryDataSource.detailState(
            for: item,
            richDetail: detail,
            achievementSnapshot: snapshot,
            achievementErrorText: nil,
            isHydrating: false,
            previousBaseRoute: .home
        )

        #expect(state.titleID == TitleID("halo-title"))
        #expect(state.productID == ProductID("halo-product"))
        #expect(state.gallery.count == 2)
        #expect(state.gallery.map(\.kind) == [.video, .image])
        #expect(state.detailPanels.map(\.id).contains("achievements"))
        #expect(state.detailPanels.map(\.id).contains("catalog"))
    }

    @Test
    func detailStateFallsBackToTileArtworkWhileHydrating() {
        let item = CloudLibraryTestSupport.makeItem(
            titleID: "fallback-title",
            productID: "fallback-product",
            name: "Fallback"
        )

        let state = CloudLibraryDataSource.detailState(
            for: item,
            richDetail: nil,
            achievementSnapshot: nil,
            achievementErrorText: "Achievements loading",
            isHydrating: true,
            previousBaseRoute: .home
        )

        #expect(state.titleID == TitleID("fallback-title"))
        #expect(state.gallery.isEmpty == false)
        #expect(state.detailPanels.map(\.id).contains("achievements"))
        #expect(state.isHydrating == true)
    }

    @Test
    func readinessStateRequiresAllTrackedMediaBeforeReporting() {
        var readiness = CloudLibraryTitleDetailReadinessState()

        let begin = readiness.begin(
            for: "detail-1",
            requiredMediaKeys: ["hero|https://example.com/hero.png", "gallery|https://example.com/shot.png"]
        )
        let heroReady = readiness.markReady("hero|https://example.com/hero.png")
        let galleryReady = readiness.markReady("gallery|https://example.com/shot.png")

        #expect(begin == .waitingForRequiredMedia)
        #expect(heroReady == false)
        #expect(galleryReady == true)
        #expect(readiness.hasReportedInitialMediaReady == true)
    }

    @Test
    func readinessStateIgnoresUnchangedStateIdentityAndSupportsImmediateReady() {
        var readiness = CloudLibraryTitleDetailReadinessState()
        let firstBegin = readiness.begin(for: "detail-1", requiredMediaKeys: [])
        let secondBegin = readiness.begin(for: "detail-1", requiredMediaKeys: ["hero|x"])

        #expect(firstBegin == .readyImmediately)
        #expect(secondBegin == .unchanged)
        #expect(readiness.hasReportedInitialMediaReady == true)
    }
}
