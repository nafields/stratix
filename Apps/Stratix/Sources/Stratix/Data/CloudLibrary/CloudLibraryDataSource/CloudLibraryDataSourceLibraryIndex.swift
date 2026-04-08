// CloudLibraryDataSourceLibraryIndex.swift
// Defines cloud library data source library index for the CloudLibrary / CloudLibraryDataSource surface.
//

import Foundation
import StratixCore
import StratixModels

extension CloudLibraryDataSource {
    /// Builds the reusable library index shared by the home, library, search, and detail projection layers.
    static func prepareIndex(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot?
    ) -> PreparedLibraryIndex {
        let mru = deduplicate(mruItems(from: sections))
        let all = allLibraryItems(from: sections)
        let featured = mru.first ?? all.first
        let itemsByTitleID = Dictionary(
            all.map { ($0.typedTitleID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let itemsByProductID = Dictionary(
            all.compactMap { item -> (ProductID, CloudLibraryItem)? in
                let productID = item.typedProductID
                guard !productID.rawValue.isEmpty else { return nil }
                return (productID, item)
            },
            uniquingKeysWith: { current, _ in current }
        )
        let categories = libraryCategoryDefinitions(sections: sections, merchandising: merchandising)
        let searchDocuments = Dictionary(
            all.map { item in
                (
                    item.typedTitleID,
                    [
                        item.name,
                        item.publisherName,
                        item.shortDescription,
                        item.attributes.map(\.localizedName).joined(separator: " "),
                        item.supportedInputTypes.joined(separator: " ")
                    ]
                    .compactMap { $0 }
                    .joined(separator: " ")
                )
            },
            uniquingKeysWith: { current, _ in current }
        )

        return PreparedLibraryIndex(
            sections: sections,
            merchandising: merchandising,
            allItems: all,
            mruItems: mru,
            featuredItem: featured,
            itemsByTitleID: itemsByTitleID,
            itemsByProductID: itemsByProductID,
            categoryDefinitions: categories,
            searchDocumentsByTitleID: searchDocuments,
            libraryCount: all.count
        )
    }

    /// Returns the MRU subset, preferring the explicit MRU section when one exists.
    static func mruItems(from sections: [CloudLibrarySection]) -> [CloudLibraryItem] {
        if let section = sections.first(where: { $0.id == "mru" || $0.name.localizedCaseInsensitiveContains("continue") }) {
            return section.items
        }
        return allLibraryItems(from: sections).filter(\.isInMRU)
    }

    /// Returns the canonical library item set, preferring the explicit library section before falling back to every section.
    static func allLibraryItems(from sections: [CloudLibrarySection]) -> [CloudLibraryItem] {
        if let library = sections.first(where: { $0.id == "library" }) {
            return deduplicate(library.items)
        }
        return deduplicate(sections.flatMap(\.items))
    }

    /// Chooses the best featured item candidate from the live sections.
    static func featuredItem(from sections: [CloudLibrarySection]) -> CloudLibraryItem? {
        mruItems(from: sections).first ?? allLibraryItems(from: sections).first
    }

    /// Returns the precomputed featured item from the prepared index.
    static func featuredItem(from index: PreparedLibraryIndex) -> CloudLibraryItem? {
        index.featuredItem
    }

    /// Builds the filter-chip category definitions that the library screen uses for scoped browsing.
    static func libraryCategoryDefinitions(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot?
    ) -> [LibraryCategoryDefinition] {
        var definitions: [LibraryCategoryDefinition] = []
        var seenAliases = Set<String>()

        let recentItems = deduplicate(mruItems(from: sections))
        if !recentItems.isEmpty {
            let titleIDs = Set(recentItems.map(\.typedTitleID))
            if !titleIDs.isEmpty, seenAliases.insert("mru").inserted {
                definitions.append(
                    LibraryCategoryDefinition(
                        context: LibraryScopedCategoryContext(
                            alias: "mru",
                            label: "Jump back in",
                            allowedTitleIDs: titleIDs
                        ),
                        systemImage: "play.fill"
                    )
                )
            }
        }

        for row in merchandising?.rows ?? [] {
            let titleIDs = Set(row.items.map(\.typedTitleID))
            guard !titleIDs.isEmpty else { continue }
            guard seenAliases.insert(row.alias).inserted else { continue }
            definitions.append(
                LibraryCategoryDefinition(
                    context: LibraryScopedCategoryContext(
                        alias: row.alias,
                        label: row.label,
                        allowedTitleIDs: titleIDs
                    ),
                    systemImage: row.alias == "free-to-play" ? "sparkles.rectangle.stack.fill" : nil
                )
            )
        }

        return definitions
    }

    /// Deduplicates library items by typed title ID while preserving first-seen order.
    static func deduplicate(_ items: [CloudLibraryItem]) -> [CloudLibraryItem] {
        var seen = Set<TitleID>()
        var uniqueItems: [CloudLibraryItem] = []
        uniqueItems.reserveCapacity(items.count)
        for item in items {
            if seen.insert(item.typedTitleID).inserted {
                uniqueItems.append(item)
            }
        }
        return uniqueItems
    }

    /// Deduplicates non-empty strings case-insensitively while preserving display-friendly trimmed values.
    static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueValues: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                uniqueValues.append(trimmed)
            }
        }
        return uniqueValues
    }

    /// Deduplicates URLs by absolute string while preserving first-seen order.
    static func uniqueURLs(_ urls: [URL?]) -> [URL] {
        var seen = Set<String>()
        var uniqueURLs: [URL] = []
        for url in urls.compactMap({ $0 }) {
            if seen.insert(url.absoluteString).inserted {
                uniqueURLs.append(url)
            }
        }
        return uniqueURLs
    }

    /// Deduplicates gallery items by media kind plus URL so image and video entries do not collide.
    static func uniqueGalleryItems(_ items: [CloudLibraryGalleryItemViewState]) -> [CloudLibraryGalleryItemViewState] {
        var seen = Set<String>()
        var uniqueItems: [CloudLibraryGalleryItemViewState] = []
        for item in items {
            let key = "\(item.kind.rawValue):\(item.mediaURL.absoluteString)"
            if seen.insert(key).inserted {
                uniqueItems.append(item)
            }
        }
        return uniqueItems
    }

    /// Builds a short initials string for profile and shell fallbacks.
    static func initials(from name: String) -> String {
        let pieces = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let initials = pieces.joined()
        return initials.isEmpty ? "P" : initials.uppercased()
    }
}
