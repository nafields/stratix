// CloudLibraryDataSourceHomeProjection.swift
// Defines cloud library data source home projection for the CloudLibrary / CloudLibraryDataSource surface.
//

import Foundation
import DiagnosticsKit
import StratixCore
import StratixModels

extension CloudLibraryDataSource {
    /// Builds the home-screen projection directly from sections and merchandising when no prepared index is being reused.
    static func homeState(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot?,
        productDetails: [ProductID: CloudLibraryProductDetail] = [:],
        showsContinueBadge: Bool = true
    ) -> CloudLibraryHomeViewState {
        homeState(
            index: prepareIndex(sections: sections, merchandising: merchandising),
            productDetails: productDetails,
            showsContinueBadge: showsContinueBadge
        )
    }

    /// Builds the home-screen projection from the prepared index plus optional rich product details.
    static func homeState(
        index: PreparedLibraryIndex,
        productDetails: [ProductID: CloudLibraryProductDetail] = [:],
        showsContinueBadge: Bool = true
    ) -> CloudLibraryHomeViewState {
        let mruItems = index.mruItems
        let allItems = index.allItems
        let recentlyAddedItems = index.merchandising?.recentlyAddedItems ?? []
        let merchandisingRows = index.merchandising?.rows ?? []
        logHomeProjection(
            "input libraryTitles=\(allItems.count) mru=\(mruItems.count) merchRows=\(merchandisingRows.count) recent=\(recentlyAddedItems.count) sections=[\(sectionSummary(index.sections))] recentSample=[\(itemSample(recentlyAddedItems))] mruSample=[\(itemSample(mruItems))]"
        )
        let featuredItem = recentlyAddedItems.first ?? index.featuredItem
        let carouselItems = recentlyAddedItems
            .prefix(5)
            .map { item in
                let richDetail = productDetails[item.typedProductID]
                let creatorLine = [richDetail?.developerName, richDetail?.publisherName, item.publisherName]
                    .compactMap { value -> String? in
                        guard let value else { return nil }
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    .first
                let category = uniqueStrings((richDetail?.genreLabels ?? []) + [primaryGenre(for: item)])
                    .first(where: { $0 != "More games" })
                return CloudLibraryHomeCarouselItemViewState(
                    id: "carousel:\(item.titleId)",
                    titleID: item.typedTitleID,
                    title: item.name,
                    subtitle: creatorLine,
                    categoryLabel: category,
                    ratingBadgeText: nil,
                    description: item.shortDescription,
                    heroBackgroundURL: item.heroImageURL ?? item.artURL,
                    artworkURL: item.posterImageURL ?? item.artURL ?? item.heroImageURL
                )
            }

        var railSections: [CloudLibraryRailSectionViewState] = []
        if !mruItems.isEmpty {
            railSections.append(
                CloudLibraryRailSectionViewState(
                    id: "mru",
                    alias: "mru",
                    title: "Jump back in",
                    subtitle: "Recently played cloud titles",
                    items: deduplicate(mruItems).map { item in
                        .title(
                            CloudLibraryHomeTitleRailItemViewState(
                                id: "home-mru:\(item.titleId)",
                                tile: tileState(
                                    for: item,
                                    aspect: .portrait,
                                    idPrefix: "home-mru",
                                    showsContinueBadge: showsContinueBadge
                                ),
                                action: .launchStream(source: "home_mru")
                            )
                        )
                    }
                )
            )
        }

        for row in merchandisingRows {
            var railItems: [CloudLibraryHomeRailItemViewState] = row.items.prefix(10).map { item in
                .title(
                    CloudLibraryHomeTitleRailItemViewState(
                        id: "home-sigl:\(row.alias):\(item.titleId)",
                        tile: tileState(
                            for: item,
                            aspect: .portrait,
                            idPrefix: "home-sigl-\(row.alias)",
                            showsContinueBadge: showsContinueBadge
                        ),
                        action: .openDetail
                    )
                )
            }
            if row.items.count > 10 {
                railItems.append(
                    .showAll(
                        CloudLibraryHomeShowAllCardViewState(
                            id: "home-show-all:\(row.alias)",
                            alias: row.alias,
                            label: row.label,
                            totalCount: row.items.count
                        )
                    )
                )
            }

            railSections.append(
                CloudLibraryRailSectionViewState(
                    id: "sigl-\(row.alias)",
                    alias: row.alias,
                    title: row.label,
                    subtitle: "\(row.items.count) games",
                    items: railItems
                )
            )
        }

        let state = CloudLibraryHomeViewState(
            heroBackgroundURL: carouselItems.first?.heroBackgroundURL ?? featuredItem?.heroImageURL ?? featuredItem?.artURL,
            carouselItems: Array(carouselItems),
            sections: railSections
        )
        logHomeProjection(
            "output hero=\(state.carouselItems.first?.titleID.rawValue ?? featuredItem?.titleId ?? "none") carousel=\(state.carouselItems.count) rails=\(state.sections.count) carouselSample=[\(carouselSample(state.carouselItems))] railSummary=[\(railSummary(state.sections))]"
        )
        return state
    }

    /// Builds genre-based fallback rail sections from a flat item list when curated merchandising is unavailable.
    static func homeGenreSections(
        items: [CloudLibraryItem],
        showsContinueBadge: Bool = true
    ) -> [CloudLibraryRailSectionViewState] {
        guard !items.isEmpty else { return [] }

        var itemsByGenre: [String: [CloudLibraryItem]] = [:]
        for item in items {
            let genre = primaryGenre(for: item)
            itemsByGenre[genre, default: []].append(item)
        }

        return itemsByGenre
            .map { genre, genreItems in
                let genreKey = genre.lowercased()
                return CloudLibraryRailSectionViewState(
                    id: "genre-\(genreKey)",
                    alias: nil,
                    title: genre,
                    subtitle: "\(genreItems.count) games",
                    items: genreItems
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                        .map {
                            .title(
                                CloudLibraryHomeTitleRailItemViewState(
                                    id: "home-genre-\(genreKey):\($0.titleId)",
                                    tile: tileState(
                                        for: $0,
                                        aspect: .portrait,
                                        idPrefix: "home-genre-\(genreKey)",
                                        showsContinueBadge: showsContinueBadge
                                    ),
                                    action: .openDetail
                                )
                            )
                        }
                )
            }
            .sorted { lhs, rhs in
                if lhs.title == "More games" { return false }
                if rhs.title == "More games" { return true }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    /// Chooses the best genre label to drive home fallback grouping for one title.
    static func primaryGenre(for item: CloudLibraryItem) -> String {
        guard let genre = item.attributes
            .map(\.localizedName)
            .first(where: { isLikelyGenreAttribute($0) }) else {
            return "More games"
        }
        return genre
    }

    /// Filters out attribute labels that look like platform/capability metadata rather than a real genre.
    static func isLikelyGenreAttribute(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let nonGenreFragments = [
            "xbox", "cloud", "save", "achieve", "club", "play anywhere",
            "optimized", "series x", "series s", "ultra hd", "4k", "hdr",
            "fps boost", "smart delivery", "dolby", "spatial sound", "touch"
        ]
        return !nonGenreFragments.contains(where: { lowercased.contains($0) })
    }

    private static func logHomeProjection(_ message: @autoclosure () -> String) {
        guard GLogger.isEnabled else { return }
        logger.info("Home projection datasource: \(message())")
    }

    private static func itemSample(_ items: [CloudLibraryItem], limit: Int = 5) -> String {
        items.prefix(limit)
            .map { "\($0.titleId)|\($0.productId)|\($0.name.replacingOccurrences(of: "\"", with: "'"))" }
            .joined(separator: ", ")
    }

    private static func carouselSample(_ items: [CloudLibraryHomeCarouselItemViewState], limit: Int = 5) -> String {
        items.prefix(limit)
            .map { "\($0.titleID.rawValue)|\($0.title.replacingOccurrences(of: "\"", with: "'"))" }
            .joined(separator: ", ")
    }

    private static func sectionSummary(_ sections: [CloudLibrarySection], limit: Int = 6) -> String {
        sections.prefix(limit)
            .map { "\($0.id):\($0.items.count)" }
            .joined(separator: ", ")
    }

    private static func railSummary(_ sections: [CloudLibraryRailSectionViewState], limit: Int = 8) -> String {
        sections.prefix(limit)
            .map { "\($0.alias ?? $0.id):\($0.items.count)" }
            .joined(separator: ", ")
    }
}
