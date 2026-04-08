// LibraryHydrationSnapshots.swift
// Defines library hydration snapshots.
//

import Foundation
import StratixModels

enum LibraryHydrationCacheSchema {
    static let currentCacheVersion = 2
}

struct LibrarySectionsDiskCacheSnapshot: Codable, Sendable, Equatable {
    let savedAt: Date
    let sections: [LibrarySectionDiskCacheSnapshot]
    let homeMerchandising: HomeMerchandisingDiskCacheSnapshot?
    let siglDiscovery: HomeMerchandisingDiscoveryDiskCacheSnapshot?
    let isUnifiedHomeReady: Bool
    let cacheVersion: Int
    let metadata: LibraryHydrationMetadata

    private enum CodingKeys: String, CodingKey {
        case savedAt, sections, homeMerchandising, siglDiscovery, isUnifiedHomeReady, cacheVersion, metadata
    }

    init(
        savedAt: Date,
        sections: [LibrarySectionDiskCacheSnapshot],
        homeMerchandising: HomeMerchandisingDiskCacheSnapshot? = nil,
        siglDiscovery: HomeMerchandisingDiscoveryDiskCacheSnapshot? = nil,
        isUnifiedHomeReady: Bool = false,
        cacheVersion: Int = LibraryHydrationCacheSchema.currentCacheVersion,
        metadata: LibraryHydrationMetadata? = nil
    ) {
        self.savedAt = savedAt
        self.sections = sections
        self.homeMerchandising = homeMerchandising
        self.siglDiscovery = siglDiscovery
        self.isUnifiedHomeReady = isUnifiedHomeReady
        self.cacheVersion = cacheVersion
        self.metadata = metadata ?? .compatibility(
            savedAt: savedAt,
            cacheVersion: cacheVersion,
            refreshSource: "snapshot_init",
            homeReady: isUnifiedHomeReady
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        sections = try container.decode([LibrarySectionDiskCacheSnapshot].self, forKey: .sections)
        homeMerchandising = try container.decodeIfPresent(HomeMerchandisingDiskCacheSnapshot.self, forKey: .homeMerchandising)
        siglDiscovery = try container.decodeIfPresent(HomeMerchandisingDiscoveryDiskCacheSnapshot.self, forKey: .siglDiscovery)
        isUnifiedHomeReady = (try? container.decode(Bool.self, forKey: .isUnifiedHomeReady)) ?? false
        cacheVersion = (try? container.decode(Int.self, forKey: .cacheVersion)) ?? 0
        metadata = try container.decodeIfPresent(LibraryHydrationMetadata.self, forKey: .metadata)
            ?? .compatibility(
                savedAt: savedAt,
                cacheVersion: cacheVersion,
                homeReady: isUnifiedHomeReady
            )
    }
}

struct ProductDetailsDiskCacheSnapshot: Codable, Sendable, Equatable {
    let savedAt: Date
    let details: [ProductID: CloudLibraryProductDetail]
    let cacheVersion: Int
    let metadata: LibraryHydrationMetadata

    private enum CodingKeys: String, CodingKey {
        case savedAt, details, cacheVersion, metadata
    }

    init(
        savedAt: Date,
        details: [ProductID: CloudLibraryProductDetail],
        cacheVersion: Int = LibraryHydrationCacheSchema.currentCacheVersion,
        metadata: LibraryHydrationMetadata? = nil
    ) {
        self.savedAt = savedAt
        self.details = details
        self.cacheVersion = cacheVersion
        self.metadata = metadata ?? .compatibility(
            savedAt: savedAt,
            cacheVersion: cacheVersion,
            refreshSource: "snapshot_init"
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        let rawDetails = try container.decode([String: CloudLibraryProductDetail].self, forKey: .details)
        details = LibraryController.normalizeProductDetails(rawDetails)
        cacheVersion = (try? container.decode(Int.self, forKey: .cacheVersion)) ?? 0
        metadata = try container.decodeIfPresent(LibraryHydrationMetadata.self, forKey: .metadata)
            ?? .compatibility(savedAt: savedAt, cacheVersion: cacheVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(
            Dictionary(uniqueKeysWithValues: details.map { ($0.key.rawValue, $0.value) }),
            forKey: .details
        )
        try container.encode(cacheVersion, forKey: .cacheVersion)
        try container.encode(metadata, forKey: .metadata)
    }
}

struct LibrarySectionDiskCacheSnapshot: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let items: [LibraryItemDiskCacheSnapshot]
}

struct LibraryItemDiskCacheSnapshot: Codable, Sendable, Equatable {
    let titleId: TitleID
    let productId: ProductID
    let name: String
    let shortDescription: String?
    let artURL: String?
    let posterImageURL: String?
    let heroImageURL: String?
    let galleryImageURLs: [String]
    let publisherName: String?
    let attributes: [LibraryAttributeDiskCacheSnapshot]
    let supportedInputTypes: [String]
    let isInMRU: Bool

    private enum CodingKeys: String, CodingKey {
        case titleId, productId, name, shortDescription, artURL, posterImageURL, heroImageURL, galleryImageURLs, publisherName, attributes, supportedInputTypes, isInMRU
    }

    init(
        titleId: TitleID,
        productId: ProductID,
        name: String,
        shortDescription: String?,
        artURL: String?,
        posterImageURL: String?,
        heroImageURL: String?,
        galleryImageURLs: [String],
        publisherName: String?,
        attributes: [LibraryAttributeDiskCacheSnapshot],
        supportedInputTypes: [String],
        isInMRU: Bool
    ) {
        self.titleId = titleId
        self.productId = productId
        self.name = name
        self.shortDescription = shortDescription
        self.artURL = artURL
        self.posterImageURL = posterImageURL
        self.heroImageURL = heroImageURL
        self.galleryImageURLs = galleryImageURLs
        self.publisherName = publisherName
        self.attributes = attributes
        self.supportedInputTypes = supportedInputTypes
        self.isInMRU = isInMRU
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        titleId = TitleID(try container.decode(String.self, forKey: .titleId))
        productId = ProductID(try container.decode(String.self, forKey: .productId))
        name = try container.decode(String.self, forKey: .name)
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        artURL = try container.decodeIfPresent(String.self, forKey: .artURL)
        posterImageURL = try container.decodeIfPresent(String.self, forKey: .posterImageURL)
        heroImageURL = try container.decodeIfPresent(String.self, forKey: .heroImageURL)
        galleryImageURLs = try container.decode([String].self, forKey: .galleryImageURLs)
        publisherName = try container.decodeIfPresent(String.self, forKey: .publisherName)
        attributes = try container.decode([LibraryAttributeDiskCacheSnapshot].self, forKey: .attributes)
        supportedInputTypes = try container.decode([String].self, forKey: .supportedInputTypes)
        isInMRU = try container.decode(Bool.self, forKey: .isInMRU)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(titleId.rawValue, forKey: .titleId)
        try container.encode(productId.rawValue, forKey: .productId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(shortDescription, forKey: .shortDescription)
        try container.encodeIfPresent(artURL, forKey: .artURL)
        try container.encodeIfPresent(posterImageURL, forKey: .posterImageURL)
        try container.encodeIfPresent(heroImageURL, forKey: .heroImageURL)
        try container.encode(galleryImageURLs, forKey: .galleryImageURLs)
        try container.encodeIfPresent(publisherName, forKey: .publisherName)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(supportedInputTypes, forKey: .supportedInputTypes)
        try container.encode(isInMRU, forKey: .isInMRU)
    }
}

struct LibraryAttributeDiskCacheSnapshot: Codable, Sendable, Equatable {
    let name: String
    let localizedName: String
}

struct HomeMerchandisingDiskCacheSnapshot: Codable, Sendable, Equatable {
    let savedAt: Date
    let recentlyAddedItems: [LibraryItemDiskCacheSnapshot]
    let rows: [HomeMerchandisingRowDiskCacheSnapshot]
    let cacheVersion: Int
    let metadata: LibraryHydrationMetadata

    private enum CodingKeys: String, CodingKey {
        case savedAt, recentlyAddedItems, rows, cacheVersion, metadata
    }

    init(
        savedAt: Date,
        recentlyAddedItems: [LibraryItemDiskCacheSnapshot],
        rows: [HomeMerchandisingRowDiskCacheSnapshot],
        cacheVersion: Int = LibraryHydrationCacheSchema.currentCacheVersion,
        metadata: LibraryHydrationMetadata? = nil
    ) {
        self.savedAt = savedAt
        self.recentlyAddedItems = recentlyAddedItems
        self.rows = rows
        self.cacheVersion = cacheVersion
        self.metadata = metadata ?? .compatibility(
            savedAt: savedAt,
            cacheVersion: cacheVersion,
            refreshSource: "snapshot_init"
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        recentlyAddedItems = try container.decode([LibraryItemDiskCacheSnapshot].self, forKey: .recentlyAddedItems)
        rows = try container.decode([HomeMerchandisingRowDiskCacheSnapshot].self, forKey: .rows)
        cacheVersion = (try? container.decode(Int.self, forKey: .cacheVersion)) ?? 0
        metadata = try container.decodeIfPresent(LibraryHydrationMetadata.self, forKey: .metadata)
            ?? .compatibility(savedAt: savedAt, cacheVersion: cacheVersion)
    }
}

struct HomeMerchandisingRowDiskCacheSnapshot: Codable, Sendable, Equatable {
    let alias: String
    let label: String
    let source: String
    let items: [LibraryItemDiskCacheSnapshot]
}

struct HomeMerchandisingDiscoveryDiskCacheSnapshot: Codable, Sendable, Equatable {
    let savedAt: Date
    let entries: [HomeMerchandisingDiscoveryEntryDiskCacheSnapshot]
    let cacheVersion: Int
    let metadata: LibraryHydrationMetadata

    private enum CodingKeys: String, CodingKey {
        case savedAt, entries, cacheVersion, metadata
    }

    init(
        savedAt: Date,
        entries: [HomeMerchandisingDiscoveryEntryDiskCacheSnapshot],
        cacheVersion: Int = LibraryHydrationCacheSchema.currentCacheVersion,
        metadata: LibraryHydrationMetadata? = nil
    ) {
        self.savedAt = savedAt
        self.entries = entries
        self.cacheVersion = cacheVersion
        self.metadata = metadata ?? .compatibility(
            savedAt: savedAt,
            cacheVersion: cacheVersion,
            refreshSource: "snapshot_init"
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        entries = try container.decode([HomeMerchandisingDiscoveryEntryDiskCacheSnapshot].self, forKey: .entries)
        cacheVersion = (try? container.decode(Int.self, forKey: .cacheVersion)) ?? 0
        metadata = try container.decodeIfPresent(LibraryHydrationMetadata.self, forKey: .metadata)
            ?? .compatibility(savedAt: savedAt, cacheVersion: cacheVersion)
    }
}

struct HomeMerchandisingDiscoveryEntryDiskCacheSnapshot: Codable, Sendable, Equatable {
    let alias: String
    let label: String
    let siglID: String
    let source: String
}
