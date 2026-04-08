// LibraryCatalogShaper.swift
// Defines library catalog shaper for the Library surface.
//

import Foundation
import StratixModels
import XCloudAPI

enum LibraryShaper {
    typealias CatalogProduct = GamePassCatalogClient.CatalogProduct

    static func makeCloudLibrarySectionsAsync(
        titles: [TitleEntry],
        mruEntries: [LibraryMRUEntry],
        productMap: [String: CatalogProduct],
        titleByProductId: [ProductID: TitleEntry],
        titleByTitleId: [TitleID: TitleEntry],
        productByXCloudTitleId: [String: CatalogProduct],
        mruProductIds: Set<ProductID>
    ) async -> [CloudLibrarySection] {
        makeCloudLibrarySections(
            titles: titles,
            mruEntries: mruEntries,
            productMap: productMap,
            titleByProductId: titleByProductId,
            titleByTitleId: titleByTitleId,
            productByXCloudTitleId: productByXCloudTitleId,
            mruProductIds: mruProductIds
        )
    }

    static func makeCloudLibrarySections(
        titles: [TitleEntry],
        mruEntries: [LibraryMRUEntry],
        productMap: [String: CatalogProduct],
        titleByProductId: [ProductID: TitleEntry],
        titleByTitleId: [TitleID: TitleEntry],
        productByXCloudTitleId: [String: CatalogProduct],
        mruProductIds: Set<ProductID>
    ) -> [CloudLibrarySection] {
        let mruItems: [CloudLibraryItem] = mruEntries.compactMap { entry in
            let resolved = resolvedProduct(
                forTitleID: entry.titleID,
                productID: entry.productID,
                productMap: productMap,
                productByXCloudTitleId: productByXCloudTitleId
            )
            return makeItem(
                titleID: entry.titleID,
                productID: entry.productID,
                product: resolved,
                fallback: titleByTitleId[entry.titleID] ?? titleByProductId[entry.productID],
                isInMRU: true
            )
        }

        let libraryItems: [CloudLibraryItem] = titles.compactMap { title in
            let resolved = resolvedProduct(
                forTitleID: title.titleID,
                productID: title.productID,
                productMap: productMap,
                productByXCloudTitleId: productByXCloudTitleId
            )
            return makeItem(
                titleID: title.titleID,
                productID: title.productID,
                product: resolved,
                fallback: title,
                isInMRU: mruProductIds.contains(title.productID)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var output: [CloudLibrarySection] = []
        if !mruItems.isEmpty {
            output.append(CloudLibrarySection(id: "mru", name: "Continue Playing", items: mruItems))
        }
        output.append(CloudLibrarySection(id: "library", name: "Cloud Library", items: libraryItems))
        return output
    }

    private static func resolvedProduct(
        forTitleID titleID: TitleID,
        productID: ProductID,
        productMap: [String: CatalogProduct],
        productByXCloudTitleId: [String: CatalogProduct]
    ) -> CatalogProduct? {
        productByXCloudTitleId[titleID.rawValue] ?? productMap[productID.rawValue]
    }

    private static func makeItem(
        titleID: TitleID,
        productID: ProductID,
        product: CatalogProduct?,
        fallback: TitleEntry?,
        isInMRU: Bool
    ) -> CloudLibraryItem? {
        let displayName = productTitle(product) ?? fallback?.fallbackName ?? productID.rawValue
        guard product != nil || fallback?.fallbackName != nil else { return nil }
        return CloudLibraryItem(
            titleId: titleID.rawValue,
            productId: productID.rawValue,
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

    private static func productTitle(_ p: CatalogProduct?) -> String? {
        p?.ProductTitle ?? p?.LocalizedProperties?.first?.ProductTitle
    }

    private static func productShortDescription(_ p: CatalogProduct?) -> String? {
        p?.ProductDescriptionShort ?? p?.LocalizedProperties?.first?.ShortDescription
    }

    private static func tileImageURL(_ p: CatalogProduct?) -> URL? {
        p?.Image_Tile?.URL.flatMap(urlFromCatalogPath)
    }

    private static func posterImageURL(_ p: CatalogProduct?) -> URL? {
        p?.Image_Poster?.URL.flatMap(urlFromCatalogPath)
    }

    private static func heroImageURL(_ p: CatalogProduct?) -> URL? {
        p?.Image_Hero?.URL.flatMap(urlFromCatalogPath)
    }

    private static func productImageURL(_ p: CatalogProduct?) -> URL? {
        guard let images = p?.LocalizedProperties?.first?.Images else { return nil }
        let preferred = images.first { ($0.ImagePurpose ?? "").localizedCaseInsensitiveContains("tile") }
            ?? images.first { ($0.ImagePurpose ?? "").localizedCaseInsensitiveContains("box") }
            ?? images.first { ($0.ImagePurpose ?? "").localizedCaseInsensitiveContains("poster") }
            ?? images.first { ($0.ImagePurpose ?? "").localizedCaseInsensitiveContains("hero") }
            ?? images.first
        return preferred?.Uri.flatMap(urlFromCatalogPath)
    }

    private static func galleryImageURLs(_ p: CatalogProduct?) -> [URL] {
        let directShots: [URL] = (p?.Screenshots ?? []).compactMap { $0.URL.flatMap(urlFromCatalogPath) }
        if !directShots.isEmpty {
            var seen = Set<String>()
            return directShots.filter { seen.insert($0.absoluteString).inserted }
        }
        guard let images = p?.LocalizedProperties?.flatMap({ $0.Images ?? [] }),
              !images.isEmpty else { return [] }
        func priority(_ purpose: String?) -> Int {
            let value = (purpose ?? "").lowercased()
            if value.contains("screenshot") { return 0 }
            if value.contains("hero") || value.contains("background") { return 1 }
            if value.contains("poster") || value.contains("box") { return 2 }
            if value.contains("tile") { return 3 }
            return 4
        }
        let sorted = images.sorted { priority($0.ImagePurpose) < priority($1.ImagePurpose) }
        var seen = Set<String>()
        var urls: [URL] = []
        urls.reserveCapacity(sorted.count)
        for image in sorted {
            guard let url = image.Uri.flatMap(urlFromCatalogPath) else { continue }
            if seen.insert(url.absoluteString).inserted { urls.append(url) }
        }
        return urls
    }

    private static func productPublisherName(_ p: CatalogProduct?) -> String? {
        p?.PublisherName
    }

    private static func productAttributes(_ p: CatalogProduct?) -> [CloudLibraryAttribute] {
        (p?.Attributes ?? []).compactMap { attr in
            guard let localized = attr.LocalizedName, !localized.isEmpty else { return nil }
            return CloudLibraryAttribute(name: attr.Name ?? localized, localizedName: localized)
        }
    }

    private static func urlFromCatalogPath(_ raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        if raw.hasPrefix("//") { return URL(string: "https:\(raw)") }
        return URL(string: raw)
    }
}
