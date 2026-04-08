// CloudLibraryDataSourceTests.swift
// Exercises cloud library data source behavior.
//

import XCTest
import StratixModels
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

@MainActor
final class CloudLibraryDataSourceTests: XCTestCase {
    func testLibraryCategoryDefinitionsBuildTypedScopedTitleIDs() {
        let recent = CloudLibraryTestSupport.makeItem(titleID: "recent-title", productID: "recent-product")
        let featured = CloudLibraryTestSupport.makeItem(titleID: "featured-title", productID: "featured-product")
        let sections = [
            CloudLibrarySection(id: "mru", name: "Continue", items: [recent]),
            CloudLibrarySection(id: "library", name: "Library", items: [recent, featured])
        ]
        let merchandising = HomeMerchandisingSnapshot(
            recentlyAddedItems: [],
            rows: [
                HomeMerchandisingRow(
                    alias: "featured",
                    label: "Featured",
                    source: .fixedPriority,
                    items: [featured]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let categories = CloudLibraryDataSource.libraryCategoryDefinitions(
            sections: sections,
            merchandising: merchandising
        )

        XCTAssertEqual(categories.first?.context.allowedTitleIDs, [TitleID("recent-title")])
        XCTAssertEqual(categories.last?.context.allowedTitleIDs, [TitleID("featured-title")])
    }

    func testLibraryStateFiltersScopedCategoryUsingTypedTitleIDs() {
        let halo = CloudLibraryTestSupport.makeItem(titleID: "halo-title", productID: "halo-product", name: "Halo")
        let forza = CloudLibraryTestSupport.makeItem(titleID: "forza-title", productID: "forza-product", name: "Forza")
        let index = CloudLibraryDataSource.prepareIndex(
            sections: [CloudLibrarySection(id: "library", name: "Library", items: [halo, forza])],
            merchandising: nil
        )
        var queryState = LibraryQueryState()
        queryState.scopedCategory = LibraryScopedCategoryContext(
            alias: "focus",
            label: "Focus",
            allowedTitleIDs: [TitleID("forza-title")]
        )

        let state = CloudLibraryDataSource.libraryState(
            index: index,
            queryState: queryState,
            showsContinueBadge: true
        )

        XCTAssertEqual(state.gridItems.map(\.titleID), [TitleID("forza-title")])
        XCTAssertEqual(state.activeFilterLabels, ["Focus"])
    }

    func testHomeStateUsesProductIDKeyedDetailMetadataForCarouselProjection() {
        let halo = CloudLibraryTestSupport.makeItem(
            titleID: "halo-title",
            productID: "halo-product",
            name: "Halo Infinite"
        )
        let merchandising = HomeMerchandisingSnapshot(
            recentlyAddedItems: [halo],
            rows: [],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let detail = CloudLibraryProductDetail(
            productId: "halo-product",
            title: "Halo Infinite",
            publisherName: "Xbox Game Studios",
            shortDescription: "Test detail",
            longDescription: "Long test detail",
            developerName: "343 Industries",
            releaseDate: "2021-12-08",
            capabilityLabels: [],
            genreLabels: ["Shooter"],
            mediaAssets: [],
            galleryImageURLs: [],
            trailers: [],
            achievementSummary: nil
        )

        let state = CloudLibraryDataSource.homeState(
            sections: [CloudLibrarySection(id: "library", name: "Library", items: [halo])],
            merchandising: merchandising,
            productDetails: [ProductID("halo-product"): detail]
        )

        XCTAssertEqual(state.carouselItems.first?.titleID, TitleID("halo-title"))
        XCTAssertEqual(state.carouselItems.first?.subtitle, "343 Industries")
        XCTAssertEqual(state.carouselItems.first?.categoryLabel, "Shooter")
    }

    func testPreparedIndexBuildsTypedLookupMaps() {
        let halo = CloudLibraryTestSupport.makeItem(titleID: "halo-title", productID: "halo-product", name: "Halo")
        let forza = CloudLibraryTestSupport.makeItem(titleID: "forza-title", productID: "forza-product", name: "Forza")
        let index = CloudLibraryDataSource.prepareIndex(
            sections: [CloudLibrarySection(id: "library", name: "Library", items: [halo, forza])],
            merchandising: nil
        )

        XCTAssertEqual(index.itemsByTitleID[TitleID("halo-title")]?.productId, "halo-product")
        XCTAssertEqual(index.itemsByProductID[ProductID("forza-product")]?.titleId, "forza-title")
    }

    func testSearchResultItemsUsesTypedSearchDocumentLookups() {
        let racing = CloudLibraryItem(
            titleId: "racing-title",
            productId: "racing-product",
            name: "Forza Horizon",
            shortDescription: "Open-world racing",
            artURL: URL(string: "https://example.com/racing-title.png"),
            posterImageURL: nil,
            heroImageURL: URL(string: "https://example.com/racing-title-hero.png"),
            galleryImageURLs: [],
            publisherName: "Xbox Game Studios",
            attributes: [.init(name: "racing", localizedName: "Racing")],
            supportedInputTypes: [],
            isInMRU: false
        )
        let shooter = CloudLibraryTestSupport.makeItem(titleID: "shooter-title", productID: "shooter-product", name: "Halo Infinite")
        let index = CloudLibraryDataSource.prepareIndex(
            sections: [CloudLibrarySection(id: "library", name: "Library", items: [racing, shooter])],
            merchandising: nil
        )
        var queryState = LibraryQueryState()
        queryState.searchText = "Racing"

        let results = CloudLibraryDataSource.searchResultItems(
            index: index,
            queryState: queryState
        )

        XCTAssertEqual(results.map { $0.typedTitleID }, [TitleID("racing-title")])
    }

    func testSelectedItemsForCurrentTabFallsBackToLibraryWhenMRUEmpty() {
        let first = CloudLibraryTestSupport.makeItem(titleID: "first-title", productID: "first-product", name: "First")
        let second = CloudLibraryTestSupport.makeItem(titleID: "second-title", productID: "second-product", name: "Second")
        let index = CloudLibraryDataSource.prepareIndex(
            sections: [CloudLibrarySection(id: "library", name: "Library", items: [first, second])],
            merchandising: nil
        )

        let selected = CloudLibraryDataSource.selectedItemsForCurrentTab(
            index: index,
            selectedTabID: "my-games"
        )

        XCTAssertEqual(selected.map(\.typedTitleID), [TitleID("first-title"), TitleID("second-title")])
    }

    func testDeduplicate_keepsFirstOccurrencePerTitleID() {
        let first = CloudLibraryTestSupport.makeItem(titleID: "dup-title", productID: "first-product", name: "First")
        let second = CloudLibraryTestSupport.makeItem(titleID: "dup-title", productID: "second-product", name: "Second")
        let unique = CloudLibraryDataSource.deduplicate([first, second])

        XCTAssertEqual(unique.count, 1)
        XCTAssertEqual(unique.first?.productId, "first-product")
    }

    func testUniqueStrings_trimsAndDeduplicatesCaseInsensitively() {
        let values = CloudLibraryDataSource.uniqueStrings(["  Halo  ", "halo", "", " Forza "])

        XCTAssertEqual(values, ["Halo", "Forza"])
    }

    func testUniqueURLs_removesDuplicateAbsoluteStrings() {
        let first = URL(string: "https://example.com/a.png")
        let duplicate = URL(string: "https://example.com/a.png")
        let second = URL(string: "https://example.com/b.png")

        let values = CloudLibraryDataSource.uniqueURLs([first, duplicate, second, nil])

        XCTAssertEqual(values, [first!, second!])
    }

    func testUniqueGalleryItems_deduplicatesByKindAndMediaURL() {
        let url = URL(string: "https://example.com/media.png")!
        let duplicate = CloudLibraryGalleryItemViewState(kind: .image, mediaURL: url, title: "First")
        let sameURLDifferentKind = CloudLibraryGalleryItemViewState(kind: .video, mediaURL: url, title: "Second")
        let unique = CloudLibraryDataSource.uniqueGalleryItems([duplicate, duplicate, sameURLDifferentKind])

        XCTAssertEqual(unique.count, 2)
        XCTAssertEqual(unique.map(\.kind), [.image, .video])
    }

    func testInitials_usesFirstTwoWordsAndFallsBackToP() {
        XCTAssertEqual(CloudLibraryDataSource.initials(from: "Player One"), "PO")
        XCTAssertEqual(CloudLibraryDataSource.initials(from: "   "), "P")
    }
}
