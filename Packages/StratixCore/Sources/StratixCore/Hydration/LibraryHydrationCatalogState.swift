// LibraryHydrationCatalogState.swift
// Defines the library hydration catalog state.
//

import Foundation
import StratixModels
import XCloudAPI

struct TitleEntry: Sendable {
    let titleID: TitleID
    let productID: ProductID
    let inputs: [String]
    let fallbackName: String?

    var titleId: String { titleID.rawValue }
    var productId: String { productID.rawValue }
}

struct LibraryMRUEntry: Sendable, Hashable {
    let titleID: TitleID
    let productID: ProductID

    var titleId: String { titleID.rawValue }
    var productId: String { productID.rawValue }
}

struct LibraryHydrationCatalogState: Sendable {
    enum MRUSource: String, Sendable {
        case live
        case fallback
    }

    struct SupplementaryMerge: Sendable {
        let label: String
        let rawCount: Int
        let addedTitles: [TitleEntry]
    }

    let titles: [TitleEntry]
    let expectedLibraryTitleCount: Int
    let mruEntries: [LibraryMRUEntry]
    let mruSource: MRUSource
    let fetchedMRUCount: Int
    let allProductIds: [ProductID]
    let titleByProductId: [ProductID: TitleEntry]
    let titleByTitleId: [TitleID: TitleEntry]
    let duplicateTitleIds: Set<TitleID>
    let mruProductIds: Set<ProductID>
    let supplementaryMerges: [SupplementaryMerge]

    static func liveFetch(
        primaryTitlesResponse: XCloudTitlesResponse,
        supplementaryResponses: [(label: String, response: XCloudTitlesResponse)],
        mruResponse: XCloudTitlesResponse,
        existingSections: [CloudLibrarySection]
    ) -> LibraryHydrationCatalogState {
        var seenTitleIds = Set<TitleID>()
        let primaryTitles = normalizedEntitledTitles(
            from: primaryTitlesResponse,
            excludingTitleIds: &seenTitleIds
        )

        var titles = primaryTitles
        titles.reserveCapacity(
            primaryTitles.count + supplementaryResponses.reduce(into: 0) { $0 += $1.response.results.count }
        )

        var supplementaryMerges: [SupplementaryMerge] = []
        supplementaryMerges.reserveCapacity(supplementaryResponses.count)
        for supplementary in supplementaryResponses {
            let addedTitles = normalizedEntitledTitles(
                from: supplementary.response,
                excludingTitleIds: &seenTitleIds
            )
            titles.append(contentsOf: addedTitles)
            supplementaryMerges.append(
                SupplementaryMerge(
                    label: supplementary.label,
                    rawCount: supplementary.response.results.count,
                    addedTitles: addedTitles
                )
            )
        }

        let entitledTitleIds = Set(titles.map { $0.titleID })
        let fetchedMRUEntries = mruResponse.results.compactMap { dto -> LibraryMRUEntry? in
            guard let rawTitleId = dto.titleId,
                  let titleId = Optional(TitleID(rawTitleId)),
                  entitledTitleIds.contains(titleId),
                  let rawProductId = dto.details?.productId,
                  let productId = Optional(ProductID(rawProductId)),
                  !productId.rawValue.isEmpty else { return nil }
            return LibraryMRUEntry(titleID: titleId, productID: productId)
        }
        let mruEntries: [LibraryMRUEntry]
        let mruSource: MRUSource
        if fetchedMRUEntries.isEmpty {
            mruEntries = fallbackMRUEntries(from: existingSections, entitledTitleIds: entitledTitleIds)
            mruSource = .fallback
        } else {
            mruEntries = fetchedMRUEntries
            mruSource = .live
        }

        var titleByProductId: [ProductID: TitleEntry] = [:]
        for title in titles where titleByProductId[title.productID] == nil {
            titleByProductId[title.productID] = title
        }

        var titleByTitleId: [TitleID: TitleEntry] = [:]
        var duplicateTitleIds = Set<TitleID>()
        for title in titles {
            if titleByTitleId[title.titleID] != nil {
                duplicateTitleIds.insert(title.titleID)
                continue
            }
            titleByTitleId[title.titleID] = title
        }

        let mruProductIds = Set(mruEntries.map(\.productID))
        return LibraryHydrationCatalogState(
            titles: titles,
            expectedLibraryTitleCount: entitledTitleIds.count,
            mruEntries: mruEntries,
            mruSource: mruSource,
            fetchedMRUCount: fetchedMRUEntries.count,
            allProductIds: prioritizedCatalogProductIds(titles: titles, mruEntries: mruEntries),
            titleByProductId: titleByProductId,
            titleByTitleId: titleByTitleId,
            duplicateTitleIds: duplicateTitleIds,
            mruProductIds: mruProductIds,
            supplementaryMerges: supplementaryMerges
        )
    }

    private static func normalizedEntitledTitles(
        from response: XCloudTitlesResponse,
        excludingTitleIds seenTitleIds: inout Set<TitleID>
    ) -> [TitleEntry] {
        response.results.compactMap { dto -> TitleEntry? in
            guard let rawTitleId = dto.titleId,
                  let titleId = Optional(TitleID(rawTitleId)),
                  let rawProductId = dto.details?.productId,
                  let productId = Optional(ProductID(rawProductId)),
                  !productId.rawValue.isEmpty,
                  dto.details?.hasEntitlement == true,
                  seenTitleIds.insert(titleId).inserted else { return nil }
            return TitleEntry(
                titleID: titleId,
                productID: productId,
                inputs: dto.details?.supportedInputTypes ?? [],
                fallbackName: dto.details?.name
            )
        }
    }

    private static func fallbackMRUEntries(
        from sections: [CloudLibrarySection],
        entitledTitleIds: Set<TitleID>
    ) -> [LibraryMRUEntry] {
        let sourceItems: [CloudLibraryItem]
        if let mruSection = sections.first(where: { $0.id == "mru" }) {
            sourceItems = mruSection.items
        } else {
            sourceItems = sections.flatMap(\.items).filter(\.isInMRU)
        }

        var seenTitleIds = Set<TitleID>()
        return sourceItems.compactMap { item in
            let titleId = TitleID(item.titleId)
            let productId = ProductID(item.productId)
            guard entitledTitleIds.contains(titleId) else { return nil }
            guard !productId.rawValue.isEmpty else { return nil }
            guard seenTitleIds.insert(titleId).inserted else { return nil }
            return LibraryMRUEntry(titleID: titleId, productID: productId)
        }
    }

    private static func prioritizedCatalogProductIds(
        titles: [TitleEntry],
        mruEntries: [LibraryMRUEntry]
    ) -> [ProductID] {
        var ordered: [ProductID] = []
        ordered.reserveCapacity(titles.count + mruEntries.count)

        func appendUnique(_ id: ProductID) {
            if !ordered.contains(id) {
                ordered.append(id)
            }
        }

        for entry in mruEntries { appendUnique(entry.productID) }
        for title in titles.prefix(100) { appendUnique(title.productID) }
        for title in titles { appendUnique(title.productID) }
        return ordered
    }
}
