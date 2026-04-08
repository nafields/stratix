// LibraryHydrationDecodedSnapshots.swift
// Defines library hydration decoded snapshots for the Hydration surface.
//

import Foundation
import StratixModels
import XCloudAPI

struct HomeMerchandisingDiscoveryCachePayload: Sendable, Equatable {
    let entries: [GamePassSiglDiscoveryEntry]
    let savedAt: Date
}

struct DecodedLibrarySectionsCacheSnapshot: Sendable, Equatable {
    let savedAt: Date
    let sections: [CloudLibrarySection]
    let homeMerchandising: HomeMerchandisingSnapshot?
    let discovery: HomeMerchandisingDiscoveryCachePayload?
    let isUnifiedHomeReady: Bool
    let cacheVersion: Int
    let metadata: LibraryHydrationMetadata
}

extension LibrarySectionsDiskCacheSnapshot {
    var decodedSnapshot: DecodedLibrarySectionsCacheSnapshot {
        let sections = sections.map { section in
            CloudLibrarySection(
                id: section.id,
                name: section.name,
                items: section.items.map(\.cloudLibraryItem)
            )
        }

        let homeMerchandising = homeMerchandising.map { cached in
            HomeMerchandisingSnapshot(
                recentlyAddedItems: cached.recentlyAddedItems.map(\.cloudLibraryItem),
                rows: cached.rows.compactMap { cachedRow in
                    guard let source = HomeMerchandisingRow.Source(rawValue: cachedRow.source) else {
                        return nil
                    }
                    return HomeMerchandisingRow(
                        alias: cachedRow.alias,
                        label: cachedRow.label,
                        source: source,
                        items: cachedRow.items.map(\.cloudLibraryItem)
                    )
                },
                generatedAt: cached.savedAt
            )
        }

        let discovery = siglDiscovery.map { cached in
            HomeMerchandisingDiscoveryCachePayload(
                entries: cached.entries.compactMap { cachedEntry in
                    guard let source = GamePassSiglDiscoveryEntry.Source(
                        rawValue: cachedEntry.source
                    ) else {
                        return nil
                    }
                    return GamePassSiglDiscoveryEntry(
                        alias: cachedEntry.alias,
                        label: cachedEntry.label,
                        siglID: cachedEntry.siglID,
                        source: source
                    )
                },
                savedAt: cached.savedAt
            )
        }

        return DecodedLibrarySectionsCacheSnapshot(
            savedAt: savedAt,
            sections: sections,
            homeMerchandising: homeMerchandising,
            discovery: discovery,
            isUnifiedHomeReady: isUnifiedHomeReady,
            cacheVersion: cacheVersion,
            metadata: metadata
        )
    }
}

private extension LibraryItemDiskCacheSnapshot {
    var cloudLibraryItem: CloudLibraryItem {
        CloudLibraryItem(
            titleId: titleId.rawValue,
            productId: productId.rawValue,
            name: name,
            shortDescription: shortDescription,
            artURL: artURL.flatMap(URL.init(string:)),
            posterImageURL: posterImageURL.flatMap(URL.init(string:)),
            heroImageURL: heroImageURL.flatMap(URL.init(string:)),
            galleryImageURLs: galleryImageURLs.compactMap(URL.init(string:)),
            publisherName: publisherName,
            attributes: attributes.map { attribute in
                CloudLibraryAttribute(
                    name: attribute.name,
                    localizedName: attribute.localizedName
                )
            },
            supportedInputTypes: supportedInputTypes,
            isInMRU: isInMRU
        )
    }
}
