// CloudLibraryDataSource.swift
// Defines cloud library data source for the Data / CloudLibrary surface.
//

import Foundation
import DiagnosticsKit
import StratixCore
import StratixModels

// MARK: - Cloud Library Data Source

/// Pure projection and indexing helpers that shape CloudLibrary domain models into shell-facing view state.
enum CloudLibraryDataSource {
    static let logger = GLogger(category: .ui)

    /// Captures the complete detail-state input set before it is projected into a title-detail view state.
    struct DetailStateSnapshot {
        let item: CloudLibraryItem
        let richDetail: CloudLibraryProductDetail?
        let achievementSnapshot: TitleAchievementSnapshot?
        let achievementErrorText: String?
        let isHydrating: Bool
        let previousBaseRoute: AppRoute
    }

    /// Describes one library-scoped category chip, including the title IDs that belong to it.
    struct LibraryCategoryDefinition {
        let context: LibraryScopedCategoryContext
        let systemImage: String?
    }

    /// Precomputes the reusable library-wide index used by home, library, search, and detail shaping.
    struct PreparedLibraryIndex {
        let sections: [CloudLibrarySection]
        let merchandising: HomeMerchandisingSnapshot?
        let allItems: [CloudLibraryItem]
        let mruItems: [CloudLibraryItem]
        let featuredItem: CloudLibraryItem?
        let itemsByTitleID: [TitleID: CloudLibraryItem]
        let itemsByProductID: [ProductID: CloudLibraryItem]
        let categoryDefinitions: [LibraryCategoryDefinition]
        let searchDocumentsByTitleID: [TitleID: String]
        let libraryCount: Int
    }

    // MARK: - View State Builders

    /// Projects one library item into the shared tile state used across home, library, and search.
    static func tileState(
        for item: CloudLibraryItem,
        aspect: MediaTileAspect,
        idPrefix: String? = nil,
        showsContinueBadge: Bool = true
    ) -> MediaTileViewState {
        MediaTileViewState(
            id: "\(idPrefix.map { "\($0):" } ?? "")\(item.titleId)",
            titleID: item.typedTitleID,
            title: item.name,
            subtitle: item.publisherName,
            caption: item.isInMRU && showsContinueBadge ? "Resume in cloud" : nil,
            artworkURL: item.artURL ?? item.posterImageURL ?? item.heroImageURL,
            badgeText: item.isInMRU && showsContinueBadge ? "Continue" : nil,
            aspect: aspect
        )
    }

    /// Builds the library-screen view state directly from sections when no prepared index is being reused.
    static func libraryState(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot?,
        queryState: LibraryQueryState,
        showsContinueBadge: Bool = true
    ) -> CloudLibraryLibraryViewState {
        libraryState(
            index: prepareIndex(sections: sections, merchandising: merchandising),
            queryState: queryState,
            showsContinueBadge: showsContinueBadge
        )
    }

    /// Builds the library-screen view state from a prepared index plus the current query/filter state.
    static func libraryState(
        index: PreparedLibraryIndex,
        queryState: LibraryQueryState,
        showsContinueBadge: Bool = true
    ) -> CloudLibraryLibraryViewState {
        let categoryDefinitions = index.categoryDefinitions
        let resolvedScopedCategory = queryState.scopedCategory.map { scopedCategory in
            categoryDefinitions
                .first(where: { $0.context.alias == scopedCategory.alias })?
                .context ?? scopedCategory
        }
        let selectedTabItems = selectedItemsForCurrentTab(
            index: index,
            selectedTabID: queryState.selectedTabID
        )
        let visibleItems = resolvedScopedCategory.map { scopedCategory in
            selectedTabItems.filter { scopedCategory.allowedTitleIDs.contains($0.typedTitleID) }
        } ?? selectedTabItems
        let filteredItems = applyFiltersAndSort(
            to: visibleItems,
            queryState: queryState,
            searchQuery: "",
            searchDocumentsByTitleID: index.searchDocumentsByTitleID
        )
        let featuredItem = featuredItem(from: index)

        return CloudLibraryLibraryViewState(
            heroBackdropURL: featuredItem?.heroImageURL ?? featuredItem?.artURL,
            tabs: [
                .init(id: "my-games", title: "My games"),
                .init(id: "full-library", title: "Full library")
            ],
            selectedTabID: queryState.selectedTabID,
            filters: categoryDefinitions.map { categoryDefinition in
                ChipViewState(
                    id: categoryDefinition.context.alias,
                    label: categoryDefinition.context.label,
                    systemImage: categoryDefinition.systemImage,
                    style: resolvedScopedCategory?.alias == categoryDefinition.context.alias ? .accent : .neutral,
                    isSelected: resolvedScopedCategory?.alias == categoryDefinition.context.alias
                )
            },
            sortLabel: "Sort \(queryState.sortOption.label)",
            displayMode: queryState.displayMode,
            gridItems: filteredItems.map {
                tileState(for: $0, aspect: .portrait, showsContinueBadge: showsContinueBadge)
            },
            resultSummaryText: "\(filteredItems.count) results",
            activeFilterLabels: resolvedScopedCategory.map { [$0.label] } ?? [],
            categoryCalloutTitle: resolvedScopedCategory.map { "Showing: \($0.label)" }
        )
    }
}

extension CloudLibraryItem {
    /// Normalizes the raw title string into the strongly typed title identifier used across the shell.
    var typedTitleID: TitleID {
        TitleID(rawValue: titleId)
    }

    /// Normalizes the raw product string into the strongly typed product identifier used across hydration and detail lookups.
    var typedProductID: ProductID {
        ProductID(rawValue: productId)
    }
}
