// LibraryControllerCatalogSupport.swift
// Provides shared support for the Library surface.
//

import Foundation
import StratixModels
import XCloudAPI

@MainActor
extension LibraryController {
    nonisolated static func allLibraryItems(from sections: [CloudLibrarySection]) -> [CloudLibraryItem] {
        if let library = sections.first(where: { $0.id == "library" }) {
            return library.items
        }
        return sections.flatMap(\.items)
    }

    nonisolated static func libraryTitleCount(in sections: [CloudLibrarySection]) -> Int {
        Set(allLibraryItems(from: sections).map(\.titleId)).count
    }

    nonisolated static func preferredHydrationSections(
        currentBest: [CloudLibrarySection],
        candidate: [CloudLibrarySection]
    ) -> [CloudLibrarySection] {
        let currentBestCount = libraryTitleCount(in: currentBest)
        let candidateCount = libraryTitleCount(in: candidate)
        guard candidateCount >= currentBestCount else { return currentBest }
        return candidate
    }

    nonisolated static func normalizeProductDetails(
        _ decoded: [String: CloudLibraryProductDetail]
    ) -> [ProductID: CloudLibraryProductDetail] {
        var normalized: [ProductID: CloudLibraryProductDetail] = [:]
        normalized.reserveCapacity(decoded.count)
        for (key, detail) in decoded {
            let normalizedKey = ProductID(key)
            guard !normalizedKey.rawValue.isEmpty else { continue }
            if let existing = normalized[normalizedKey],
               Self.detailMediaRichness(existing) >= Self.detailMediaRichness(detail) {
                continue
            }
            normalized[normalizedKey] = detail
        }
        return normalized
    }

    nonisolated static func detailMediaRichness(_ detail: CloudLibraryProductDetail) -> Int {
        let mediaAssets = detail.mediaAssets
        let productDetailsMedia = mediaAssets.filter { $0.source == .productDetails }
        let productDetailScreenshots = productDetailsMedia.filter { asset in
            guard asset.kind == .image else { return false }
            return isLikelyGameplayScreenshotURL(asset.url)
        }
        let productDetailVideoWithThumb = productDetailsMedia.filter { asset in
            asset.kind == .video && asset.thumbnailURL != nil
        }

        var score = 0
        if !productDetailScreenshots.isEmpty { score += 100 }
        if !productDetailVideoWithThumb.isEmpty { score += 70 }
        if !productDetailsMedia.isEmpty { score += 35 }
        if !detail.galleryImageURLs.isEmpty { score += 15 }
        if !detail.trailers.isEmpty { score += 10 }
        if !detail.mediaAssets.isEmpty { score += 5 }
        return score
    }

    func makeCloudLibraryItem(
        titleId: String,
        productId: String,
        product: GamePassCatalogClient.CatalogProduct?,
        fallback: TitleEntry?,
        isInMRU: Bool
    ) -> CloudLibraryItem? {
        let displayName = productTitle(product) ?? fallback?.fallbackName ?? productId
        if product == nil && fallback?.fallbackName == nil {
            return nil
        }

        return CloudLibraryItem(
            titleId: titleId,
            productId: productId,
            name: displayName,
            shortDescription: productShortDescription(product),
            artURL: tileImageURL(product) ?? productImageURL(product),
            posterImageURL: posterImageURL(product),
            heroImageURL: heroImageURL(product),
            galleryImageURLs: galleryImageURLs(product),
            publisherName: productPublisherName(product),
            attributes: productAttributes(product),
            supportedInputTypes: fallback?.inputs ?? [],
            isInMRU: isInMRU
        )
    }

    func productTitle(_ product: GamePassCatalogClient.CatalogProduct?) -> String? {
        product?.ProductTitle ?? product?.LocalizedProperties?.first?.ProductTitle
    }

    func productShortDescription(_ product: GamePassCatalogClient.CatalogProduct?) -> String? {
        product?.ProductDescriptionShort ?? product?.LocalizedProperties?.first?.ShortDescription
    }

    func productImageURL(_ product: GamePassCatalogClient.CatalogProduct?) -> URL? {
        guard let images = product?.LocalizedProperties?.first?.Images else { return nil }
        let preferred = images.first { ($0.ImagePurpose ?? "").localizedCaseInsensitiveContains("tile") }
            ?? images.first { ($0.ImagePurpose ?? "").localizedCaseInsensitiveContains("box") }
            ?? images.first { ($0.ImagePurpose ?? "").localizedCaseInsensitiveContains("poster") }
            ?? images.first { ($0.ImagePurpose ?? "").localizedCaseInsensitiveContains("hero") }
            ?? images.first
        guard let uri = preferred?.Uri else { return nil }
        return URL(string: uri)
    }

    func tileImageURL(_ product: GamePassCatalogClient.CatalogProduct?) -> URL? {
        guard let raw = product?.Image_Tile?.URL else { return nil }
        return urlFromCatalogPath(raw)
    }

    func posterImageURL(_ product: GamePassCatalogClient.CatalogProduct?) -> URL? {
        guard let raw = product?.Image_Poster?.URL else { return nil }
        return urlFromCatalogPath(raw)
    }

    func heroImageURL(_ product: GamePassCatalogClient.CatalogProduct?) -> URL? {
        guard let raw = product?.Image_Hero?.URL else { return nil }
        return urlFromCatalogPath(raw)
    }

    func galleryImageURLs(_ product: GamePassCatalogClient.CatalogProduct?) -> [URL] {
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

    func catalogTrailers(_ product: GamePassCatalogClient.CatalogProduct?) -> [CloudLibraryTrailer] {
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

    func productPublisherName(_ product: GamePassCatalogClient.CatalogProduct?) -> String? {
        product?.PublisherName
    }

    func productAttributes(_ product: GamePassCatalogClient.CatalogProduct?) -> [CloudLibraryAttribute] {
        (product?.Attributes ?? []).compactMap { attr in
            guard let localized = attr.LocalizedName, !localized.isEmpty else { return nil }
            return CloudLibraryAttribute(name: attr.Name ?? localized, localizedName: localized)
        }
    }

    nonisolated static func makeCloudLibraryProductDetail(from detail: XboxComProductDetails) -> CloudLibraryProductDetail {
        let trailers = detail.trailers.map { trailer in
            CloudLibraryTrailer(
                title: trailer.title,
                playbackURL: trailer.playbackURL,
                thumbnailURL: trailer.thumbnailURL
            )
        }

        return CloudLibraryProductDetail(
            productId: detail.productId,
            title: detail.title,
            publisherName: detail.publisherName,
            shortDescription: detail.shortDescription,
            longDescription: detail.longDescription,
            developerName: detail.developerName,
            releaseDate: detail.releaseDate,
            capabilityLabels: deduplicatedLabels(detail.capabilityLabels),
            genreLabels: deduplicatedLabels(detail.genreLabels),
            mediaAssets: detail.mediaAssets,
            galleryImageURLs: detail.galleryImageURLs,
            trailers: trailers,
            achievementSummary: nil
        )
    }

    func makeCloudLibraryProductDetail(from detail: XboxComProductDetails) -> CloudLibraryProductDetail {
        Self.makeCloudLibraryProductDetail(from: detail)
    }

    nonisolated static func deduplicatedLabels(_ values: [String]) -> [String] {
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

    func deduplicatedLabels(_ values: [String]) -> [String] {
        Self.deduplicatedLabels(values)
    }

    func urlFromCatalogPath(_ raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }
        return URL(string: raw)
    }

    func resolvedCatalogProduct(
        forTitleId titleId: String,
        productId: String,
        productMap: [String: GamePassCatalogClient.CatalogProduct],
        productByXCloudTitleId: [String: GamePassCatalogClient.CatalogProduct]
    ) -> GamePassCatalogClient.CatalogProduct? {
        if let match = productByXCloudTitleId[titleId] {
            return match
        }
        return productMap[productId]
    }

    func logString(for error: Error) -> String {
        if case let APIError.httpError(code, body) = error {
            return "HTTP \(code): \(truncateForLog(body))"
        }
        if case let APIError.decodingError(message) = error {
            return "Decode: \(message)"
        }
        return error.localizedDescription
    }

    func isUnauthorized(_ error: Error) -> Bool {
        if case let APIError.httpError(code, _) = error {
            return code == 401
        }
        return false
    }

    func isTaskCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == URLError.cancelled.rawValue {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSURLErrorDomain,
           underlying.code == URLError.cancelled.rawValue {
            return true
        }

        return false
    }

    func isHTTPResponseError(_ error: Error) -> Bool {
        if case APIError.httpError = error {
            return true
        }
        return false
    }

    func truncateForLog(_ text: String, maxBytes: Int = 2048) -> String {
        if text.utf8.count <= maxBytes { return text }
        let prefix = String(text.prefix(maxBytes))
        return "\(prefix)…"
    }

    func makeLibraryTokenCandidates(tokens: StreamTokens) -> [(label: String, token: String, preferredHost: String?)] {
        LibraryTokenCandidateResolver.makeCandidates(tokens: tokens)
    }

    func makeLibraryHostCandidates(tokens: StreamTokens, preferredHost: String?) -> [String] {
        LibraryHostResolver.makeCandidates(tokens: tokens, preferredHost: preferredHost)
    }

    nonisolated static func isLikelyGameplayScreenshotURL(_ url: URL) -> Bool {
        let probe = url.absoluteString.lowercased()
        let includes = ["screenshot", "screen", "shot", "gallery", "still", "gameplay", "ingame"]
        let excludes = [
            "xboxgamepass", "gamepass", "esrb", "pegi", "rating",
            "logo", "wordmark", "icon", "brand", "badge",
            "cover", "poster", "tile", "hero", "keyart", "boxart",
            "capsule", "banner", "splash", "placeholder", "watermark"
        ]
        if excludes.contains(where: { probe.contains($0) }) {
            return false
        }
        if includes.contains(where: { probe.contains($0) }) {
            return true
        }
        return probe.contains("/media/")
            || probe.contains("/images/")
            || probe.contains("/assets/")
    }
}
