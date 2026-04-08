// HomeMerchandisingSnapshotBuilder.swift
// Defines home merchandising snapshot builder.
//

import Foundation
import StratixModels
import XCloudAPI

struct HomeMerchandisingBuildResult: Sendable {
    let snapshot: HomeMerchandisingSnapshot
    let discovery: HomeMerchandisingDiscoveryCachePayload
}

@MainActor
enum HomeMerchandisingSnapshotBuilder {
    struct Context: Sendable {
        let latestSections: [CloudLibrarySection]
        let discovery: HomeMerchandisingDiscoveryCachePayload
        let existingSnapshot: HomeMerchandisingSnapshot?
        let market: String
        let language: String
        let config: LibraryHydrationConfig
    }

    static func build(
        context: Context,
        fetchProductIDs: @escaping @Sendable (_ siglID: String, _ market: String, _ language: String) async throws -> [String],
        logDebug: (String) -> Void
    ) async -> HomeMerchandisingBuildResult {
        let discoveryEntries = context.discovery.entries
        let allItems = LibraryController.allLibraryItems(from: context.latestSections)
        let itemsByProductID = Dictionary(
            allItems.map { (ProductID($0.productId), $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let itemsByTitleID = Dictionary(
            allItems.map { (TitleID($0.titleId), $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let existingRowsByAlias = Dictionary(
            (context.existingSnapshot?.rows ?? []).map { ($0.alias, $0) },
            uniquingKeysWith: { current, _ in current }
        )

        let fixedAliases = context.config.fixedHomeCategoryAliases
        let trailingAliases = context.config.trailingHomeCategoryAliases
        let excludedAliases = context.config.excludedHomeCategoryAliases
        let discoveredByAlias = Dictionary(
            discoveryEntries.map { ($0.alias, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let leadingFixedAliases = fixedAliases.filter { !trailingAliases.contains($0) }
        var orderedAliases: [String] = leadingFixedAliases
        let fixedAliasSet = Set(fixedAliases)
        let extraAliases = discoveryEntries
            .map(\.alias)
            .filter { alias in
                !fixedAliasSet.contains(alias) && !excludedAliases.contains(alias)
            }
            .reduce(into: [String]()) { partial, alias in
                if !partial.contains(alias) {
                    partial.append(alias)
                }
            }
            .prefix(context.config.maxExtraHomeCategories)
        orderedAliases.append(contentsOf: extraAliases)
        orderedAliases.append(contentsOf: trailingAliases.filter { !orderedAliases.contains($0) })

        var siglByAlias: [String: String] = [:]
        var labelByAlias: [String: String] = [:]
        for alias in orderedAliases {
            if excludedAliases.contains(alias) { continue }
            if let entry = discoveredByAlias[alias] {
                siglByAlias[alias] = entry.siglID
                labelByAlias[alias] = entry.label
                continue
            }
            if let fallbackSigl = GamePassSiglClient.fallbackAliasToSiglID[alias] {
                siglByAlias[alias] = fallbackSigl
                labelByAlias[alias] = LibraryController.displayLabel(for: alias)
            }
        }

        var productIDsByAlias: [String: [String]] = [:]
        await withTaskGroup(of: (String, [String]).self) { group in
            for alias in orderedAliases {
                guard let siglID = siglByAlias[alias], !siglID.isEmpty else { continue }
                group.addTask {
                    do {
                        let ids = try await fetchProductIDs(siglID, context.market, context.language)
                        return (alias, ids)
                    } catch {
                        return (alias, [])
                    }
                }
            }

            for await (alias, productIDs) in group {
                productIDsByAlias[alias] = productIDs
            }
        }

        var rows: [HomeMerchandisingRow] = []
        rows.reserveCapacity(orderedAliases.count)

        for alias in orderedAliases {
            guard !excludedAliases.contains(alias) else { continue }
            let productIDs = productIDsByAlias[alias] ?? []
            var resolvedItems = LibraryController.resolveCategoryItems(
                productIDs: productIDs,
                itemsByProductID: itemsByProductID,
                itemsByTitleID: itemsByTitleID
            )
            let fetchedResolvedCount = resolvedItems.count
            if resolvedItems.isEmpty,
               let existingRow = existingRowsByAlias[alias] {
                resolvedItems = LibraryController.deduplicatePreservingOrder(
                    existingRow.items.compactMap { item in
                        itemsByTitleID[TitleID(item.titleId)] ?? itemsByProductID[ProductID(item.productId)]
                    }
                )
                if !resolvedItems.isEmpty {
                    logDebug(
                        "home_row_preserved alias=\(alias) requestedProducts=\(productIDs.count) fetchedResolved=\(fetchedResolvedCount) preserved=\(resolvedItems.count) sample=[\(sampleItems(resolvedItems))]"
                    )
                }
            }
            guard !resolvedItems.isEmpty else {
                logDebug(
                    "home_row_empty alias=\(alias) requestedProducts=\(productIDs.count) fetchedResolved=\(fetchedResolvedCount)"
                )
                continue
            }

            let label = labelByAlias[alias] ?? LibraryController.displayLabel(for: alias)
            let rowSource: HomeMerchandisingRow.Source = fixedAliasSet.contains(alias) ? .fixedPriority : .discoveredExtra
            rows.append(
                HomeMerchandisingRow(
                    alias: alias,
                    label: label,
                    source: rowSource,
                    items: resolvedItems
                )
            )
        }

        let recentlyAddedItems = rows.first(where: { $0.alias == "recently-added" })?.items
            ?? LibraryController.deduplicatePreservingOrder(
                (context.existingSnapshot?.recentlyAddedItems ?? []).compactMap { item in
                    itemsByTitleID[TitleID(item.titleId)] ?? itemsByProductID[ProductID(item.productId)]
                }
            )
        let snapshot = HomeMerchandisingSnapshot(
            recentlyAddedItems: Array(recentlyAddedItems.prefix(5)),
            rows: rows
        )
        logDebug(
            "home_snapshot_built homeRows=\(snapshot.rows.count) recentlyAdded=\(snapshot.recentlyAddedItems.count)"
        )
        return HomeMerchandisingBuildResult(
            snapshot: snapshot,
            discovery: context.discovery
        )
    }

    private static func sampleItems(_ items: [CloudLibraryItem], limit: Int = 5) -> String {
        items.prefix(limit)
            .map { item in
                let sanitizedName = item.name.replacingOccurrences(of: "\"", with: "'")
                return "\(item.titleId)|\(item.productId)|\(sanitizedName)"
            }
            .joined(separator: ", ")
    }
}
