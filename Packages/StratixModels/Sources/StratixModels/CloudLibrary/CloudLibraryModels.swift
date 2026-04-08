// CloudLibraryModels.swift
// Defines the cloud library models.
//

import Foundation

/// Minimal cloud-title projection used by lightweight title lists and lookups.
public struct XCloudTitle: Codable, Sendable, Equatable {
    public let titleId: String
    public let name: String
    public let imageURL: URL?

    public init(titleId: String, name: String, imageURL: URL?) {
        self.titleId = titleId
        self.name = name
        self.imageURL = imageURL
    }
}

/// App-facing library item built from catalog and product-detail data for browse surfaces.
public struct CloudLibraryItem: Identifiable, Sendable, Equatable {
    /// Uses the title identifier as the stable identity across browse and detail surfaces.
    public var id: String { titleId }

    public let titleId: String
    public let productId: String
    public let name: String
    public let shortDescription: String?
    public let artURL: URL?
    public let posterImageURL: URL?
    public let heroImageURL: URL?
    public let galleryImageURLs: [URL]
    public let publisherName: String?
    public let attributes: [CloudLibraryAttribute]
    public let supportedInputTypes: [String]
    public let isInMRU: Bool

    public init(
        titleId: String,
        productId: String,
        name: String,
        shortDescription: String?,
        artURL: URL?,
        posterImageURL: URL? = nil,
        heroImageURL: URL? = nil,
        galleryImageURLs: [URL] = [],
        publisherName: String? = nil,
        attributes: [CloudLibraryAttribute] = [],
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
}

public enum CloudLibraryMediaKind: String, Sendable, Equatable, Codable {
    case image
    case video
}

/// Describes where a media asset originated so UI can reason about trust and fallback quality.
public enum CloudLibraryMediaSource: String, Sendable, Equatable, Codable {
    case productDetails
    case catalog
    case inferred
}

/// Normalized gallery asset used by detail screens regardless of whether it came from catalog or product details.
public struct CloudLibraryMediaAsset: Identifiable, Sendable, Equatable, Codable {
    public var id: String {
        "\(kind.rawValue):\(url.absoluteString)"
    }

    public let kind: CloudLibraryMediaKind
    public let url: URL
    public let thumbnailURL: URL?
    public let title: String?
    public let priority: Int
    public let source: CloudLibraryMediaSource

    public init(
        kind: CloudLibraryMediaKind,
        url: URL,
        thumbnailURL: URL? = nil,
        title: String? = nil,
        priority: Int = 0,
        source: CloudLibraryMediaSource
    ) {
        self.kind = kind
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.priority = priority
        self.source = source
    }
}

/// Trailer metadata associated with a library title's detail presentation.
public struct CloudLibraryTrailer: Identifiable, Sendable, Equatable, Codable {
    /// Prefers playback URL identity, then thumbnail, then title for stable list diffing.
    public var id: String {
        playbackURL?.absoluteString
            ?? thumbnailURL?.absoluteString
            ?? title
    }

    public let title: String
    public let playbackURL: URL?
    public let thumbnailURL: URL?

    public init(
        title: String,
        playbackURL: URL?,
        thumbnailURL: URL? = nil
    ) {
        self.title = title
        self.playbackURL = playbackURL
        self.thumbnailURL = thumbnailURL
    }
}

/// Enriched product-detail payload used by the app's detail route and hydration cache.
public struct CloudLibraryProductDetail: Sendable, Equatable, Codable {
    public let productId: String
    public let title: String?
    public let publisherName: String?
    public let shortDescription: String?
    public let longDescription: String?
    public let developerName: String?
    public let releaseDate: String?
    public let capabilityLabels: [String]
    public let genreLabels: [String]
    public let mediaAssets: [CloudLibraryMediaAsset]
    public let galleryImageURLs: [URL]
    public let trailers: [CloudLibraryTrailer]
    public let achievementSummary: TitleAchievementSummary?

    public init(
        productId: String,
        title: String? = nil,
        publisherName: String? = nil,
        shortDescription: String? = nil,
        longDescription: String? = nil,
        developerName: String? = nil,
        releaseDate: String? = nil,
        capabilityLabels: [String] = [],
        genreLabels: [String] = [],
        mediaAssets: [CloudLibraryMediaAsset] = [],
        galleryImageURLs: [URL] = [],
        trailers: [CloudLibraryTrailer] = [],
        achievementSummary: TitleAchievementSummary? = nil
    ) {
        self.productId = productId
        self.title = title
        self.publisherName = publisherName
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.developerName = developerName
        self.releaseDate = releaseDate
        self.capabilityLabels = capabilityLabels
        self.genreLabels = genreLabels
        self.mediaAssets = mediaAssets
        self.galleryImageURLs = galleryImageURLs
        self.trailers = trailers
        self.achievementSummary = achievementSummary
    }

    private enum CodingKeys: String, CodingKey {
        case productId
        case title
        case publisherName
        case shortDescription
        case longDescription
        case developerName
        case releaseDate
        case capabilityLabels
        case genreLabels
        case mediaAssets
        case galleryImageURLs
        case trailers
        case achievementSummary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.productId = try container.decode(String.self, forKey: .productId)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.publisherName = try container.decodeIfPresent(String.self, forKey: .publisherName)
        self.shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        self.longDescription = try container.decodeIfPresent(String.self, forKey: .longDescription)
        self.developerName = try container.decodeIfPresent(String.self, forKey: .developerName)
        self.releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        self.capabilityLabels = try container.decodeIfPresent([String].self, forKey: .capabilityLabels) ?? []
        self.genreLabels = try container.decodeIfPresent([String].self, forKey: .genreLabels) ?? []
        self.mediaAssets = try container.decodeIfPresent([CloudLibraryMediaAsset].self, forKey: .mediaAssets) ?? []
        self.galleryImageURLs = try container.decodeIfPresent([URL].self, forKey: .galleryImageURLs) ?? []
        self.trailers = try container.decodeIfPresent([CloudLibraryTrailer].self, forKey: .trailers) ?? []
        self.achievementSummary = try container.decodeIfPresent(TitleAchievementSummary.self, forKey: .achievementSummary)
    }
}

/// Small display attribute attached to a library item, such as capability or genre labeling.
public struct CloudLibraryAttribute: Sendable, Equatable {
    public let name: String
    public let localizedName: String

    public init(name: String, localizedName: String) {
        self.name = name
        self.localizedName = localizedName
    }
}

/// Named collection of library items used to drive browse sections and shelves.
public struct CloudLibrarySection: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let items: [CloudLibraryItem]

    public init(id: String, name: String, items: [CloudLibraryItem]) {
        self.id = id
        self.name = name
        self.items = items
    }
}
