// CatalogProductDetailHydrator.swift
// Defines catalog product detail hydrator for the Hydration surface.
//

import Foundation
import StratixModels
import XCloudAPI

enum CatalogProductDetailHydrator {
    static func seededProductDetails(
        products: [GamePassCatalogClient.CatalogProduct],
        titleByProductId: [ProductID: TitleEntry],
        existingProductDetails: [ProductID: CloudLibraryProductDetail],
        cacheSizeLimit: Int
    ) -> CatalogProductDetailsSeedState {
        guard !products.isEmpty else {
            return CatalogProductDetailsSeedState(
                details: existingProductDetails,
                upsertedCount: 0
            )
        }

        var seenProductIds = Set<ProductID>()
        var updates: [ProductID: CloudLibraryProductDetail] = [:]

        for product in products {
            let productId = product.ProductId.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedProductID = ProductID(productId)
            guard !normalizedProductID.rawValue.isEmpty else { continue }
            guard seenProductIds.insert(normalizedProductID).inserted else { continue }

            let mapped = makeCloudLibraryProductDetail(
                from: product,
                fallbackTitle: titleByProductId[normalizedProductID]?.fallbackName
            )
            let hasRenderableContent = mapped.title != nil
                || mapped.shortDescription != nil
                || mapped.publisherName != nil
                || !mapped.galleryImageURLs.isEmpty
            guard hasRenderableContent else { continue }

            let existing = updates[normalizedProductID] ?? existingProductDetails[normalizedProductID]
            if let existing {
                let merged = mergeCatalogDetail(existing: existing, incomingCatalog: mapped)
                if existing != merged {
                    updates[normalizedProductID] = merged
                }
            } else {
                updates[normalizedProductID] = mapped
            }
        }

        guard !updates.isEmpty else {
            return CatalogProductDetailsSeedState(
                details: existingProductDetails,
                upsertedCount: 0
            )
        }

        var mergedProductDetails = existingProductDetails
        mergedProductDetails.merge(updates) { _, new in new }
        while mergedProductDetails.count > cacheSizeLimit,
              let evict = mergedProductDetails.keys.first {
            mergedProductDetails.removeValue(forKey: evict)
        }

        return CatalogProductDetailsSeedState(
            details: mergedProductDetails,
            upsertedCount: updates.count
        )
    }

    static func makeCloudLibraryProductDetail(
        from product: GamePassCatalogClient.CatalogProduct,
        fallbackTitle: String?
    ) -> CloudLibraryProductDetail {
        let capabilityLabels = deduplicatedLabels(productAttributes(product).map(\.localizedName))
        let galleryURLs = galleryImageURLs(product)
        let trailers = catalogTrailers(product)

        var mediaAssets: [CloudLibraryMediaAsset] = []
        mediaAssets.reserveCapacity(trailers.count + galleryURLs.count)
        mediaAssets.append(contentsOf: trailers.enumerated().compactMap { index, trailer in
            guard let playbackURL = trailer.playbackURL else { return nil }
            return CloudLibraryMediaAsset(
                kind: .video,
                url: playbackURL,
                thumbnailURL: trailer.thumbnailURL,
                title: trailer.title,
                priority: index,
                source: .catalog
            )
        })
        mediaAssets.append(contentsOf: galleryURLs.enumerated().map { index, url in
            CloudLibraryMediaAsset(
                kind: .image,
                url: url,
                priority: 100 + index,
                source: .catalog
            )
        })

        return CloudLibraryProductDetail(
            productId: product.ProductId,
            title: productTitle(product) ?? fallbackTitle,
            publisherName: productPublisherName(product),
            shortDescription: productShortDescription(product),
            longDescription: nil,
            developerName: product.DeveloperName,
            releaseDate: product.OriginalReleaseDate,
            capabilityLabels: capabilityLabels,
            genreLabels: [],
            mediaAssets: mediaAssets,
            galleryImageURLs: galleryURLs,
            trailers: trailers,
            achievementSummary: nil
        )
    }

    static func mergeCatalogDetail(
        existing: CloudLibraryProductDetail,
        incomingCatalog: CloudLibraryProductDetail
    ) -> CloudLibraryProductDetail {
        let keepExistingMedia = LibraryController.detailMediaRichness(existing)
            > LibraryController.detailMediaRichness(incomingCatalog)
        let mergedMediaAssets: [CloudLibraryMediaAsset] = {
            if keepExistingMedia {
                return existing.mediaAssets
            }
            return incomingCatalog.mediaAssets.isEmpty ? existing.mediaAssets : incomingCatalog.mediaAssets
        }()
        let mergedGalleryURLs: [URL] = {
            if keepExistingMedia {
                return existing.galleryImageURLs
            }
            return incomingCatalog.galleryImageURLs.isEmpty ? existing.galleryImageURLs : incomingCatalog.galleryImageURLs
        }()
        let mergedTrailers: [CloudLibraryTrailer] = {
            if keepExistingMedia {
                return existing.trailers
            }
            return incomingCatalog.trailers.isEmpty ? existing.trailers : incomingCatalog.trailers
        }()

        return CloudLibraryProductDetail(
            productId: incomingCatalog.productId,
            title: preferredNonEmpty(incomingCatalog.title, fallback: existing.title),
            publisherName: preferredNonEmpty(incomingCatalog.publisherName, fallback: existing.publisherName),
            shortDescription: preferredNonEmpty(incomingCatalog.shortDescription, fallback: existing.shortDescription),
            longDescription: preferredLongText(incomingCatalog.longDescription, fallback: existing.longDescription),
            developerName: preferredNonEmpty(incomingCatalog.developerName, fallback: existing.developerName),
            releaseDate: preferredNonEmpty(incomingCatalog.releaseDate, fallback: existing.releaseDate),
            capabilityLabels: deduplicatedLabels(existing.capabilityLabels + incomingCatalog.capabilityLabels),
            genreLabels: deduplicatedLabels(existing.genreLabels + incomingCatalog.genreLabels),
            mediaAssets: mergedMediaAssets,
            galleryImageURLs: mergedGalleryURLs,
            trailers: mergedTrailers,
            achievementSummary: existing.achievementSummary ?? incomingCatalog.achievementSummary
        )
    }

    private static func productTitle(_ product: GamePassCatalogClient.CatalogProduct?) -> String? {
        product?.ProductTitle ?? product?.LocalizedProperties?.first?.ProductTitle
    }

    private static func productShortDescription(_ product: GamePassCatalogClient.CatalogProduct?) -> String? {
        product?.ProductDescriptionShort ?? product?.LocalizedProperties?.first?.ShortDescription
    }

    private static func productPublisherName(_ product: GamePassCatalogClient.CatalogProduct?) -> String? {
        product?.PublisherName
    }

    private static func productAttributes(
        _ product: GamePassCatalogClient.CatalogProduct?
    ) -> [CloudLibraryAttribute] {
        (product?.Attributes ?? []).compactMap { attr in
            guard let localized = attr.LocalizedName, !localized.isEmpty else { return nil }
            return CloudLibraryAttribute(name: attr.Name ?? localized, localizedName: localized)
        }
    }

    private static func galleryImageURLs(_ product: GamePassCatalogClient.CatalogProduct?) -> [URL] {
        let directScreenshots: [URL] = (product?.Screenshots ?? []).compactMap { image in
            guard let raw = image.URL else { return nil }
            return urlFromCatalogPath(raw)
        }
        if !directScreenshots.isEmpty {
            var seen = Set<String>()
            return directScreenshots.filter { url in
                seen.insert(url.absoluteString).inserted
            }
        }

        guard let localizedImages = product?.LocalizedProperties?.flatMap({ $0.Images ?? [] }),
              !localizedImages.isEmpty else {
            return []
        }

        func purposePriority(_ purpose: String?) -> Int {
            let value = (purpose ?? "").lowercased()
            if value.contains("screenshot") { return 0 }
            if value.contains("hero") || value.contains("background") { return 1 }
            if value.contains("poster") || value.contains("box") { return 2 }
            if value.contains("tile") { return 3 }
            return 4
        }

        let sorted = localizedImages.sorted { lhs, rhs in
            purposePriority(lhs.ImagePurpose) < purposePriority(rhs.ImagePurpose)
        }

        var seen = Set<String>()
        var urls: [URL] = []
        urls.reserveCapacity(sorted.count)
        for image in sorted {
            guard let raw = image.Uri, let url = urlFromCatalogPath(raw) else { continue }
            let key = url.absoluteString
            if seen.insert(key).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private static func catalogTrailers(_ product: GamePassCatalogClient.CatalogProduct?) -> [CloudLibraryTrailer] {
        guard let rawTrailers = product?.Trailers, !rawTrailers.isEmpty else { return [] }
        let screenshotFallback = galleryImageURLs(product).first

        var seen = Set<String>()
        var trailers: [CloudLibraryTrailer] = []
        for trailer in rawTrailers {
            let playbackRaw = trailer.FormatURL?.Hls
                ?? trailer.FormatURL?.Dash
                ?? trailer.FormatURL?.Url
            guard let playbackRaw, let playbackURL = urlFromCatalogPath(playbackRaw) else { continue }
            let id = playbackURL.absoluteString
            guard seen.insert(id).inserted else { continue }
            let title = trailer.Caption?.trimmingCharacters(in: .whitespacesAndNewlines)
            let thumbnailURL = trailer.PreviewImageURL.flatMap(urlFromCatalogPath) ?? screenshotFallback
            trailers.append(
                CloudLibraryTrailer(
                    title: (title?.isEmpty == false) ? title! : "Trailer",
                    playbackURL: playbackURL,
                    thumbnailURL: thumbnailURL
                )
            )
        }
        return trailers
    }

    private static func deduplicatedLabels(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private static func urlFromCatalogPath(_ raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }
        return URL(string: raw)
    }

    private static func preferredNonEmpty(_ value: String?, fallback: String?) -> String? {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return fallback
    }

    private static func preferredLongText(_ value: String?, fallback: String?) -> String? {
        let candidate = preferredNonEmpty(value, fallback: nil)
        let base = preferredNonEmpty(fallback, fallback: nil)
        switch (candidate, base) {
        case let (lhs?, rhs?):
            return lhs.count >= rhs.count ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}
