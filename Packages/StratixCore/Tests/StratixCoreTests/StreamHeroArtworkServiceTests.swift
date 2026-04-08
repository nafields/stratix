// StreamHeroArtworkServiceTests.swift
// Exercises stream hero artwork service behavior.
//

import Foundation
import Testing
@testable import StratixCore
import StratixModels
import XCloudAPI

@Suite(.serialized)
struct StreamHeroArtworkServiceTests {
    @Test
    func fetchHeroArt_prefersCachedLibraryItemArtwork() async {
        let expected = URL(string: "https://example.com/hero.jpg")
        let service = StreamHeroArtworkService()
        let url = await service.fetchHeroArt(
            titleId: makeTitleID(),
            environment: makeHeroArtworkEnvironment(
                cachedItem: { _ in
                    CloudLibraryItem(
                        titleId: "1234",
                        productId: "product-1",
                        name: "Halo Infinite",
                        shortDescription: nil,
                        artURL: nil,
                        posterImageURL: nil,
                        heroImageURL: expected,
                        supportedInputTypes: [],
                        isInMRU: false
                    )
                }
            )
        )

        #expect(url == expected)
    }

    @Test
    func fetchHeroArt_fallsBackToProductDetailsFetch() async {
        let service = StreamHeroArtworkService()
        let expected = URL(string: "https://example.com/fallback.jpg")!

        let url = await service.fetchHeroArt(
            titleId: makeTitleID(),
            environment: makeHeroArtworkEnvironment(
                cachedItem: { _ in
                    CloudLibraryItem(
                        titleId: "1234",
                        productId: "product-1",
                        name: "Halo Infinite",
                        shortDescription: nil,
                        artURL: nil,
                        supportedInputTypes: [],
                        isInMRU: false
                    )
                },
                xboxWebCredentials: { _ in
                    XboxWebCredentials(token: "token", uhs: "uhs")
                },
                fetchProductDetails: { _, _, _ in
                    XboxComProductDetails(
                        productId: "product-1",
                        galleryImageURLs: [expected]
                    )
                }
            )
        )

        #expect(url == expected)
    }

    @Test
    func fetchHeroArt_returnsNilWhenCredentialsUnavailable() async {
        let service = StreamHeroArtworkService()
        let url = await service.fetchHeroArt(
            titleId: TitleID("missing"),
            environment: makeHeroArtworkEnvironment()
        )

        #expect(url == nil)
    }

    @Test
    func resolveLaunchHeroURL_preservesCurrentValueWhenAlreadyPresent() async {
        let service = StreamHeroArtworkService()
        let current = URL(string: "https://example.com/current.jpg")

        let url = await service.resolveLaunchHeroURL(
            titleId: makeTitleID(),
            currentHeroURL: current,
            environment: makeHeroArtworkEnvironment()
        )

        #expect(url == current)
    }
}
