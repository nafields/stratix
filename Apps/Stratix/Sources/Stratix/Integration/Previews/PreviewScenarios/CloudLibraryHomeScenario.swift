// CloudLibraryHomeScenario.swift
// Defines cloud library home scenario for the Previews / PreviewScenarios surface.
//

import Foundation
import StratixCore
import StratixModels
import XCloudAPI

enum CloudLibraryHomeScenario {
    static let cloudItems: [CloudLibraryItem] = CloudLibraryCatalogFixtures.capturedCatalog.map(\.asCloudLibraryItem)

    private static var mruItems: [CloudLibraryItem] {
        cloudItems.filter(\.isInMRU)
    }

    private static var libraryItems: [CloudLibraryItem] {
        cloudItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static let cloudSections: [CloudLibrarySection] = [
        .init(id: "mru", name: "Continue Playing", items: mruItems),
        .init(id: "library", name: "Cloud Library", items: libraryItems)
    ]

    private static let defaultLibraryQueryState = LibraryQueryState()
    private static let homeMerchandising = HomeMerchandisingSnapshot(
        recentlyAddedItems: Array(libraryItems.prefix(5)),
        rows: [
            HomeMerchandisingRow(
                alias: "recently-added",
                label: "Recently Added",
                source: .fixedPriority,
                items: Array(libraryItems.prefix(12))
            ),
            HomeMerchandisingRow(
                alias: "popular",
                label: "Popular",
                source: .fixedPriority,
                items: Array(libraryItems.dropFirst(2).prefix(12))
            )
        ]
    )

    static let home = CloudLibraryDataSource.homeState(
        sections: cloudSections,
        merchandising: homeMerchandising,
        showsContinueBadge: true
    )

    static let homeEmpty = CloudLibraryDataSource.homeState(
        sections: [],
        merchandising: nil,
        showsContinueBadge: true
    )

    static let library = CloudLibraryDataSource.libraryState(
        sections: cloudSections,
        merchandising: homeMerchandising,
        queryState: defaultLibraryQueryState,
        showsContinueBadge: true
    )

    static let libraryEmpty = CloudLibraryDataSource.libraryState(
        sections: [],
        merchandising: nil,
        queryState: defaultLibraryQueryState,
        showsContinueBadge: true
    )

    static let detail = CloudLibraryDataSource.detailState(
        from: detailSnapshot(for: primaryDetailItem)
    )

    static let detailLongTitle: CloudLibraryTitleDetailViewState = {
        let source = secondaryDetailItem
        let longTitleItem = CloudLibraryItem(
            titleId: source.titleId,
            productId: source.productId,
            name: "\(source.name): Definitive Cloud Preview Edition",
            shortDescription: source.shortDescription,
            artURL: source.artURL,
            posterImageURL: source.posterImageURL,
            heroImageURL: source.heroImageURL,
            galleryImageURLs: source.galleryImageURLs,
            publisherName: source.publisherName,
            attributes: source.attributes,
            supportedInputTypes: source.supportedInputTypes,
            isInMRU: source.isInMRU
        )
        return CloudLibraryDataSource.detailState(
            from: detailSnapshot(for: longTitleItem)
        )
    }()

    static var tileStates: [MediaTileViewState] {
        if !library.gridItems.isEmpty {
            return library.gridItems
        }
        return [
            MediaTileViewState(id: "preview-fallback-1", titleID: TitleID("preview-fallback-1"), title: "Preview Tile 1"),
            MediaTileViewState(id: "preview-fallback-2", titleID: TitleID("preview-fallback-2"), title: "Preview Tile 2")
        ]
    }

    private static var primaryDetailItem: CloudLibraryItem {
        mruItems.first ?? libraryItems.first ?? fallbackItem
    }

    private static var secondaryDetailItem: CloudLibraryItem {
        libraryItems.first(where: { $0.name.localizedCaseInsensitiveContains("Cities") })
            ?? libraryItems.dropFirst().first
            ?? fallbackItem
    }

    private static var fallbackItem: CloudLibraryItem {
        CloudLibraryItem(
            titleId: "fallback",
            productId: "fallback",
            name: "Game Pass",
            shortDescription: "Fallback preview item",
            artURL: nil,
            posterImageURL: nil,
            heroImageURL: nil,
            publisherName: "Xbox",
            attributes: [],
            supportedInputTypes: ["Controller"],
            isInMRU: false
        )
    }

    private static func detailSnapshot(for item: CloudLibraryItem) -> CloudLibraryDataSource.DetailStateSnapshot {
        let mediaAssets = libraryItems
            .compactMap { $0.posterImageURL ?? $0.artURL ?? $0.heroImageURL }
            .prefix(3)
            .enumerated()
            .map { index, url in
                CloudLibraryMediaAsset(
                    kind: .image,
                    url: url,
                    priority: index,
                    source: .catalog
                )
            }
        let richDetail = CloudLibraryProductDetail(
            productId: item.productId,
            title: item.name,
            publisherName: item.publisherName,
            shortDescription: item.shortDescription,
            longDescription: item.shortDescription,
            developerName: item.publisherName,
            releaseDate: "2026-03-06",
            capabilityLabels: item.attributes.map(\.localizedName),
            genreLabels: ["Action", "Cloud"],
            mediaAssets: mediaAssets
        )
        return .init(
            item: item,
            richDetail: richDetail,
            achievementSnapshot: nil,
            achievementErrorText: nil,
            isHydrating: false,
            previousBaseRoute: .home
        )
    }
}
