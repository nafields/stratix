// LibraryControllerMRUDelta.swift
// Defines library controller mru delta for the Library surface.
//

import Foundation
import StratixModels

@MainActor
extension LibraryController {
    func applyPostStreamMRUDelta(
        _ liveMRUEntries: [LibraryMRUEntry],
        market: String,
        language: String
    ) async -> PostStreamRefreshResult {
        guard !isSuspendedForStreaming else {
            logger.info("Post-stream MRU delta apply skipped: suspended for streaming")
            return .requiresFullRefresh("suspended_for_streaming")
        }

        let updatedSections = Self.sectionsApplyingMRUDelta(
            to: sections,
            liveMRUEntries: liveMRUEntries
        )
        switch updatedSections {
        case .requiresFullRefresh(let reason):
            logger.info("Post-stream MRU delta apply escalated to full refresh: \(reason)")
            return .requiresFullRefresh(reason)
        case .noChange:
            logger.info("Post-stream MRU delta apply skipped: no section changes")
            return .noChange
        case .updated(let updatedSections):
            let merchandisingResult = await HomeMerchandisingRefreshWorkflow.refresh(
                context: .init(
                    latestSections: updatedSections,
                    existingSnapshot: homeMerchandising,
                    cachedDiscovery: cachedHomeMerchandisingDiscovery,
                    market: market,
                    language: language,
                    forceDiscoveryRefresh: false,
                    config: Self.hydrationConfig
                ),
                dependencies: .init(
                    isDiscoveryStale: { [hydrationPlanner] savedAt in
                        hydrationPlanner.isUnifiedHydrationStale(generatedAt: savedAt)
                    },
                    discoverAliases: homeMerchandisingSIGLProvider.discoverAliases,
                    fetchProductIDs: homeMerchandisingSIGLProvider.fetchProductIDs,
                    formatError: { [weak self] error in
                        self?.logString(for: error) ?? String(describing: error)
                    },
                    logInfo: { [logger] message in
                        logger.info("\(message)")
                    },
                    logWarning: { [logger] message in
                        logger.warning("\(message)")
                    },
                    logDebug: { [weak self] message in
                        self?.logHydrationDebug(message)
                    }
                )
            )
            cachedHomeMerchandisingDiscovery = merchandisingResult.discovery
            let savedAt = Date()
            let recoveryState = LibraryHydrationRecoveryState.postStreamDelta(
                sections: updatedSections,
                homeMerchandising: merchandisingResult.snapshot,
                discovery: merchandisingResult.discovery,
                savedAt: savedAt
            )
            apply([.hydrationPublishedStateApplied(recoveryState.publishedState)])
            saveCloudLibrarySectionsCache(
                sections: recoveryState.publishedState.sections,
                homeMerchandising: recoveryState.publishedState.homeMerchandising,
                discovery: recoveryState.publishedState.discovery,
                savedAt: recoveryState.publishedState.savedAt,
                isUnifiedHomeReady: recoveryState.publishedState.isUnifiedHomeReady
            )
            logHydrationDebug(
                "post_stream_delta_applied age=\(formattedAge(since: savedAt)) liveMRU=\(liveMRUEntries.count) \(describeSections(updatedSections)) \(describeHomeMerchandising(merchandisingResult.snapshot)) \(describeDiscovery(merchandisingResult.discovery))"
            )
            return .appliedDelta
        }
    }

    nonisolated static func sectionsApplyingMRUDelta(
        to currentSections: [CloudLibrarySection],
        liveMRUEntries: [LibraryMRUEntry]
    ) -> MRUDeltaSectionsResult {
        guard !currentSections.isEmpty else { return .requiresFullRefresh("sections_missing") }

        let libraryItems = allLibraryItems(from: currentSections)
        guard !libraryItems.isEmpty else { return .requiresFullRefresh("library_items_missing") }

        let itemsByTitleID = Dictionary(
            libraryItems.map { (TitleID($0.titleId), $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let itemsByProductID = Dictionary(
            libraryItems.map { (ProductID($0.productId), $0) },
            uniquingKeysWith: { current, _ in current }
        )

        var seenMRUKeys = Set<LibraryMRUEntry>()
        let uniqueLiveMRUEntries = liveMRUEntries.compactMap { entry -> LibraryMRUEntry? in
            guard !entry.productID.rawValue.isEmpty else { return nil }
            guard seenMRUKeys.insert(entry).inserted else { return nil }
            return entry
        }

        let resolvedMRUItems = uniqueLiveMRUEntries.compactMap { entry -> CloudLibraryItem? in
            let item = itemsByTitleID[entry.titleID] ?? itemsByProductID[entry.productID]
            guard let item else { return nil }
            return itemSettingMRUState(item, isInMRU: true)
        }

        if !uniqueLiveMRUEntries.isEmpty,
           resolvedMRUItems.count != uniqueLiveMRUEntries.count {
            return .requiresFullRefresh("mru_entries_unmapped")
        }

        let mruTitleIDs = Set(resolvedMRUItems.map { TitleID($0.titleId) })
        let mruProductIDs = Set(resolvedMRUItems.map { ProductID($0.productId) })

        let updatedSections = currentSections.compactMap { section -> CloudLibrarySection? in
            guard section.id != "mru" else { return nil }
            let updatedItems = section.items.map { item in
                let titleID = TitleID(item.titleId)
                let productID = ProductID(item.productId)
                let isInMRU = mruTitleIDs.contains(titleID) || mruProductIDs.contains(productID)
                return itemSettingMRUState(item, isInMRU: isInMRU)
            }
            return CloudLibrarySection(
                id: section.id,
                name: section.name,
                items: updatedItems
            )
        }

        let finalSections = if resolvedMRUItems.isEmpty {
            updatedSections
        } else {
            [
                CloudLibrarySection(id: "mru", name: "Continue Playing", items: resolvedMRUItems)
            ] + updatedSections
        }

        if finalSections == currentSections {
            return .noChange
        }

        return .updated(finalSections)
    }

    nonisolated static func itemSettingMRUState(
        _ item: CloudLibraryItem,
        isInMRU: Bool
    ) -> CloudLibraryItem {
        CloudLibraryItem(
            titleId: item.titleId,
            productId: item.productId,
            name: item.name,
            shortDescription: item.shortDescription,
            artURL: item.artURL,
            posterImageURL: item.posterImageURL,
            heroImageURL: item.heroImageURL,
            galleryImageURLs: item.galleryImageURLs,
            publisherName: item.publisherName,
            attributes: item.attributes,
            supportedInputTypes: item.supportedInputTypes,
            isInMRU: isInMRU
        )
    }
}
