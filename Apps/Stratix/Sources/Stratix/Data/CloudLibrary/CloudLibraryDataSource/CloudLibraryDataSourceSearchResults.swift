// CloudLibraryDataSourceSearchResults.swift
// Defines cloud library data source search results for the CloudLibrary / CloudLibraryDataSource surface.
//

import Foundation
import StratixCore
import StratixModels

extension CloudLibraryDataSource {
    /// Returns the item set for the currently selected library tab, reusing a prepared index when available.
    static func selectedItemsForCurrentTab(
        sections: [CloudLibrarySection],
        selectedTabID: String
    ) -> [CloudLibraryItem] {
        selectedItemsForCurrentTab(
            index: prepareIndex(sections: sections, merchandising: nil),
            selectedTabID: selectedTabID
        )
    }

    /// Narrows the prepared index down to the active library tab selection.
    static func selectedItemsForCurrentTab(
        index: PreparedLibraryIndex,
        selectedTabID: String
    ) -> [CloudLibraryItem] {
        guard selectedTabID == "my-games", !index.mruItems.isEmpty else { return index.allItems }
        return index.mruItems
    }

    /// Returns the search result set directly from sections when no prepared index is being reused.
    static func searchResultItems(
        sections: [CloudLibrarySection],
        queryState: LibraryQueryState
    ) -> [CloudLibraryItem] {
        searchResultItems(
            index: prepareIndex(sections: sections, merchandising: nil),
            queryState: queryState
        )
    }

    /// Returns the search result set from the prepared index and current query/filter state.
    static func searchResultItems(
        index: PreparedLibraryIndex,
        queryState: LibraryQueryState
    ) -> [CloudLibraryItem] {
        let query = queryState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return applyFiltersAndSort(
            to: index.allItems,
            queryState: queryState,
            searchQuery: query,
            searchDocumentsByTitleID: index.searchDocumentsByTitleID
        )
    }

    /// Applies the current search text, category filters, and sort mode to a candidate item set.
    static func applyFiltersAndSort(
        to items: [CloudLibraryItem],
        queryState: LibraryQueryState,
        searchQuery: String,
        searchDocumentsByTitleID: [TitleID: String] = [:]
    ) -> [CloudLibraryItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems = trimmedQuery.isEmpty
            ? items
            : items.filter { item in
                matchesSearch(
                    item: item,
                    query: trimmedQuery,
                    searchDocumentsByTitleID: searchDocumentsByTitleID
                )
            }

        switch queryState.sortOption {
        case .alphabetical:
            return filteredItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .publisher:
            return filteredItems.sorted {
                let lhsPublisher = $0.publisherName ?? ""
                let rhsPublisher = $1.publisherName ?? ""
                if lhsPublisher.caseInsensitiveCompare(rhsPublisher) == .orderedSame {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhsPublisher.localizedCaseInsensitiveCompare(rhsPublisher) == .orderedAscending
            }
        case .recentlyPlayed:
            return filteredItems.sorted {
                if $0.isInMRU != $1.isInMRU {
                    return $0.isInMRU && !$1.isInMRU
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Matches a query against the precomputed search document for a title, or synthesizes one on demand.
    static func matchesSearch(
        item: CloudLibraryItem,
        query: String,
        searchDocumentsByTitleID: [TitleID: String] = [:]
    ) -> Bool {
        let searchableText = searchDocumentsByTitleID[item.typedTitleID] ?? [
            item.name,
            item.publisherName,
            item.shortDescription,
            item.attributes.map(\.localizedName).joined(separator: " "),
            item.supportedInputTypes.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return searchableText.localizedStandardContains(query)
    }
}
