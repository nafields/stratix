// LibraryCategorySupport.swift
// Provides shared support for the Library surface.
//

import Foundation
import StratixModels

extension LibraryController {
    nonisolated static func resolveCategoryItems(
        productIDs: [String],
        itemsByProductID: [ProductID: CloudLibraryItem],
        itemsByTitleID: [TitleID: CloudLibraryItem]
    ) -> [CloudLibraryItem] {
        var output: [CloudLibraryItem] = []
        var seenTitleIDs = Set<TitleID>()
        for productID in productIDs {
            let normalized = ProductID(productID)
            let titleID = TitleID(productID)
            let item = itemsByProductID[normalized] ?? itemsByTitleID[titleID]
            guard let item else { continue }
            guard seenTitleIDs.insert(TitleID(item.titleId)).inserted else { continue }
            output.append(item)
        }
        return output
    }

    nonisolated static func normalizedCategoryProductKey(_ productID: String) -> String {
        productID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func displayLabel(for alias: String) -> String {
        alias
            .split(separator: "-")
            .map { token in
                let lowercased = token.lowercased()
                switch lowercased {
                case "rpgs":
                    return "RPGs"
                case "ea":
                    return "EA"
                default:
                    return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
                }
            }
            .joined(separator: " ")
    }

    nonisolated static func deduplicatePreservingOrder(_ items: [CloudLibraryItem]) -> [CloudLibraryItem] {
        var seenTitleIds = Set<String>()
        var deduplicated: [CloudLibraryItem] = []
        deduplicated.reserveCapacity(items.count)
        for item in items {
            guard seenTitleIds.insert(item.titleId).inserted else { continue }
            deduplicated.append(item)
        }
        return deduplicated
    }
}
