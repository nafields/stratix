// XboxComProductDetailsResponseDecoding.swift
// Defines xbox com product details response decoding.
//

import Foundation
import StratixModels

extension XboxComProductDetailsClient {
    static func parseProductDetails(
        data: Data,
        fallbackProductID: String,
        locale: String
    ) throws -> XboxComProductDetails {
        let json = try JSONSerialization.jsonObject(with: data)
        let root = try rootObject(from: json)
        let productRoot = productObject(from: root, fallbackProductID: fallbackProductID)

        let localized = localizedDictionaries(from: productRoot, locale: locale)
        let searchDictionaries = localized
            + [productRoot]
            + allDictionaries(in: productRoot)
            + [root]

        let resolvedProductID = firstString(
            keys: ["ProductId", "StoreId", "productId", "id"],
            in: searchDictionaries
        ) ?? fallbackProductID

        let title = firstString(
            keys: ["ProductTitle", "Title", "title", "Name", "name"],
            in: searchDictionaries
        )
        let publisherName = firstString(
            keys: ["PublisherName", "Publisher", "publisherName", "publisher"],
            in: searchDictionaries
        )
        let shortDescription = firstString(
            keys: ["ProductDescriptionShort", "ShortDescription", "shortDescription"],
            in: searchDictionaries
        )
        let longDescription = firstString(
            keys: ["ProductDescription", "LongDescription", "Description", "description"],
            in: searchDictionaries
        )
        let developerName = firstString(
            keys: ["DeveloperName", "Developer", "developerName", "developer"],
            in: searchDictionaries
        )
        let releaseDate = firstString(
            keys: ["OriginalReleaseDate", "ReleaseDate", "releaseDate", "AvailabilityDate"],
            in: searchDictionaries
        )

        let capabilityLabels = collectStringValues(
            from: searchDictionaries,
            containerKeyFragments: ["attribute", "capability", "feature", "tag"],
            labelKeys: ["LocalizedName", "DisplayName", "Name", "Title", "Value"]
        )
        let genreLabels = collectStringValues(
            from: searchDictionaries,
            containerKeyFragments: ["genre", "category"],
            labelKeys: ["LocalizedName", "DisplayName", "Name", "Title", "Value"]
        )

        let structuredMediaAssets = collectStructuredMediaAssets(from: productRoot)
        let mediaAssets = structuredMediaAssets.isEmpty
            ? collectMediaAssets(from: searchDictionaries)
            : structuredMediaAssets
        let galleryImageURLs = mediaAssets
            .filter { $0.kind == .image }
            .map(\.url)
        let trailers = mediaAssets
            .filter { $0.kind == .video }
            .map { asset in
                XboxComTrailer(
                    title: asset.title ?? "Trailer",
                    playbackURL: asset.url,
                    thumbnailURL: asset.thumbnailURL
                )
            }

        return XboxComProductDetails(
            productId: resolvedProductID,
            title: title,
            publisherName: publisherName,
            shortDescription: shortDescription,
            longDescription: longDescription,
            developerName: developerName,
            releaseDate: releaseDate,
            capabilityLabels: capabilityLabels,
            genreLabels: genreLabels,
            mediaAssets: mediaAssets,
            galleryImageURLs: galleryImageURLs,
            trailers: trailers
        )
    }

    static func rootObject(from json: Any) throws -> [String: Any] {
        if let dict = json as? [String: Any] {
            return dict
        }
        if let array = json as? [Any],
           let first = array.compactMap({ $0 as? [String: Any] }).first {
            return first
        }
        throw APIError.decodingError("Product details root is not an object")
    }

    static func productObject(from root: [String: Any], fallbackProductID: String) -> [String: Any] {
        if looksLikeProductObject(root) {
            return root
        }

        let likelyContainers = [
            "ProductDetails", "productDetails",
            "ProductDetail", "productDetail",
            "Product", "product",
            "Products", "products",
            "Result", "result",
            "Data", "data",
            "Value", "value"
        ]

        for key in likelyContainers {
            guard let raw = value(forKey: key, in: root) else { continue }
            if let resolved = firstProductObject(in: raw, preferredProductID: fallbackProductID) {
                return resolved
            }
        }

        if let resolved = firstProductObject(in: root, preferredProductID: fallbackProductID) {
            return resolved
        }

        return root
    }

    static func firstProductObject(
        in raw: Any,
        preferredProductID: String
    ) -> [String: Any]? {
        let dictionaries = allDictionaries(in: raw)
        if dictionaries.isEmpty { return nil }

        let normalizedID = preferredProductID.lowercased()

        if let exact = dictionaries.first(where: { dict in
            let productID = firstString(keys: ["ProductId", "StoreId", "productId"], in: [dict])?.lowercased()
            return productID == normalizedID
        }) {
            return exact
        }

        return dictionaries.first(where: looksLikeProductObject) ?? dictionaries.first
    }

    static func looksLikeProductObject(_ dict: [String: Any]) -> Bool {
        let keys = dict.keys.map { $0.lowercased() }
        return keys.contains(where: { key in
            key == "productid"
                || key == "storeid"
                || key == "producttitle"
                || key == "localizedproperties"
                || key == "publishername"
                || key == "images"
                || key == "shortdescription"
        })
    }

    static func localizedDictionaries(from product: [String: Any], locale: String) -> [[String: Any]] {
        guard let raw = value(forKey: "LocalizedProperties", in: product) else {
            return []
        }

        let normalizedLocale = locale.lowercased()
        var candidates: [[String: Any]] = []

        if let array = raw as? [Any] {
            candidates = array.compactMap { $0 as? [String: Any] }
        } else if let dict = raw as? [String: Any] {
            if dict.values.contains(where: { $0 is [String: Any] }) {
                candidates = dict.values.compactMap { $0 as? [String: Any] }
            } else {
                candidates = [dict]
            }
        }

        guard !candidates.isEmpty else { return [] }

        if let preferred = candidates.first(where: { dict in
            let language = firstString(
                keys: ["Locale", "locale", "Language", "language", "LanguageCode", "languageCode"],
                in: [dict]
            )?.lowercased()
            if let language {
                return language == normalizedLocale || language.hasPrefix(String(normalizedLocale.prefix(2)))
            }
            return false
        }) {
            return [preferred] + candidates
        }

        return candidates
    }

    static func collectStructuredMediaAssets(from product: [String: Any]) -> [CloudLibraryMediaAsset] {
        var assets: [CloudLibraryMediaAsset] = []
        var seen = Set<String>()

        var screenshotURLs: [URL] = []
        if let imagesObject = value(forKey: "images", in: product) as? [String: Any] {
            let screenshotDictionaries = dictionaryArray(from: value(forKey: "screenshots", in: imagesObject))
            for (index, screenshot) in screenshotDictionaries.enumerated() {
                guard let url = firstURL(keys: ["url", "uri", "Url", "Uri"], in: [screenshot]) else { continue }
                let id = "image:\(url.absoluteString)"
                guard seen.insert(id).inserted else { continue }
                screenshotURLs.append(url)
                assets.append(
                    CloudLibraryMediaAsset(
                        kind: .image,
                        url: url,
                        thumbnailURL: nil,
                        title: nil,
                        priority: index,
                        source: .productDetails
                    )
                )
            }
        }

        let defaultTrailerThumbnail = screenshotURLs.first
        let videoContainerKeys = ["cmsVideos", "videos", "trailers", "Trailers", "Videos", "CmsVideos"]
        for containerKey in videoContainerKeys {
            guard let raw = value(forKey: containerKey, in: product) else { continue }
            for (index, entry) in dictionaryArray(from: raw).enumerated() {
                guard let playbackURL = firstURL(
                    keys: [
                        "url", "uri", "Url", "Uri",
                        "videoUrl", "VideoUrl",
                        "playbackURL", "playbackUrl", "PlaybackURL", "PlaybackUrl",
                        "streamingUrl", "StreamingUrl",
                        "manifestUrl", "ManifestUrl"
                    ],
                    in: [entry]
                ) else {
                    continue
                }

                let id = "video:\(playbackURL.absoluteString)"
                guard seen.insert(id).inserted else { continue }

                let explicitThumbnail = firstURL(
                    keys: [
                        "thumbnailUrl", "thumbnailURL", "ThumbnailUrl", "ThumbnailURL",
                        "posterUrl", "posterURL", "PosterUrl", "PosterURL",
                        "imageUrl", "imageURL", "ImageUrl", "ImageURL"
                    ],
                    in: [entry]
                )
                let nestedPreviewThumbnail = value(forKey: "previewImage", in: entry)
                    .flatMap { dictionaryArray(from: $0).first }
                    .flatMap { preview in
                        firstURL(keys: ["url", "uri", "Url", "Uri"], in: [preview])
                    }
                let nestedThumbnail = value(forKey: "thumbnail", in: entry)
                    .flatMap { dictionaryArray(from: $0).first }
                    .flatMap { thumbnail in
                        firstURL(keys: ["url", "uri", "Url", "Uri"], in: [thumbnail])
                    }

                let title = firstString(
                    keys: ["title", "Title", "name", "Name", "caption", "Caption"],
                    in: [entry]
                ) ?? "Trailer"
                let purpose = firstString(
                    keys: ["purpose", "Purpose", "videoType", "VideoType", "type", "Type"],
                    in: [entry]
                )

                assets.append(
                    CloudLibraryMediaAsset(
                        kind: .video,
                        url: playbackURL,
                        thumbnailURL: explicitThumbnail ?? nestedPreviewThumbnail ?? nestedThumbnail ?? defaultTrailerThumbnail,
                        title: title,
                        priority: structuredVideoPriority(purpose: purpose, containerKey: containerKey, index: index),
                        source: .productDetails
                    )
                )
            }
        }

        return assets.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            if lhs.kind != rhs.kind {
                return lhs.kind == .video
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    static func structuredVideoPriority(purpose: String?, containerKey: String, index: Int) -> Int {
        let probe = "\(purpose ?? "") \(containerKey)".lowercased()
        if probe.contains("launch") { return index }
        if probe.contains("hero") { return 10 + index }
        if probe.contains("trailer") { return 20 + index }
        if probe.contains("video") { return 30 + index }
        return 40 + index
    }

    static func collectMediaAssets(from dictionaries: [[String: Any]]) -> [CloudLibraryMediaAsset] {
        var assets: [CloudLibraryMediaAsset] = []
        var seen = Set<String>()
        let globalVideoThumbnail = preferredGlobalVideoThumbnail(from: dictionaries)

        for dict in dictionaries {
            let purpose = firstString(
                keys: ["ImagePurpose", "Purpose", "purpose", "Type", "AssetType"],
                in: [dict]
            )
            let fields = urlFields(in: dict)

            let thumbnail = fields.first(where: { field in
                shouldTreatAsImage(key: field.key, url: field.url, purpose: purpose)
                    && isLikelyVideoThumbnailAsset(url: field.url, purpose: purpose, key: field.key)
            })?.url ?? fields.first(where: { field in
                shouldTreatAsImage(key: field.key, url: field.url, purpose: purpose)
            })?.url ?? globalVideoThumbnail

            for field in fields {
                if shouldTreatAsVideo(key: field.key, url: field.url) {
                    let id = "video:\(field.url.absoluteString)"
                    guard seen.insert(id).inserted else { continue }
                    let title = firstString(
                        keys: ["Title", "title", "Name", "name", "DisplayName", "displayName", "Label"],
                        in: [dict]
                    ) ?? (keyContains(field.key, fragments: ["trailer"]) ? "Trailer" : "Video")
                    assets.append(
                        CloudLibraryMediaAsset(
                            kind: .video,
                            url: field.url,
                            thumbnailURL: thumbnail,
                            title: title,
                            priority: videoPriority(for: field.key),
                            source: .productDetails
                        )
                    )
                    continue
                }

                guard shouldTreatAsImage(key: field.key, url: field.url, purpose: purpose) else { continue }
                guard isLikelyGameplayScreenshotAsset(url: field.url, purpose: purpose, key: field.key) else { continue }

                let id = "image:\(field.url.absoluteString)"
                guard seen.insert(id).inserted else { continue }
                assets.append(
                    CloudLibraryMediaAsset(
                        kind: .image,
                        url: field.url,
                        thumbnailURL: nil,
                        title: nil,
                        priority: imagePurposePriority(purpose),
                        source: .productDetails
                    )
                )
            }
        }

        return assets.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            if lhs.kind != rhs.kind {
                return lhs.kind == .video
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    static func preferredGlobalVideoThumbnail(from dictionaries: [[String: Any]]) -> URL? {
        var best: (url: URL, score: Int)?
        var seen = Set<String>()

        for dict in dictionaries {
            let purpose = firstString(
                keys: ["ImagePurpose", "Purpose", "purpose", "Type", "AssetType"],
                in: [dict]
            )
            for field in urlFields(in: dict) {
                guard shouldTreatAsImage(key: field.key, url: field.url, purpose: purpose) else { continue }
                let id = field.url.absoluteString
                guard seen.insert(id).inserted else { continue }

                let score: Int
                if isLikelyVideoThumbnailAsset(url: field.url, purpose: purpose, key: field.key) {
                    score = 0
                } else if isLikelyGameplayScreenshotAsset(url: field.url, purpose: purpose, key: field.key) {
                    score = 1
                } else {
                    score = 2
                }

                if let best, best.score <= score {
                    continue
                }
                best = (field.url, score)
            }
        }

        return best?.url
    }
}
