// CloudLibraryViewCacheMaintenance.swift
// Defines cloud library view cache maintenance for the CloudLibrary / Root surface.
//

import SwiftUI
import DiagnosticsKit
import StratixCore
import StratixModels

extension CloudLibraryView {
    func triggerDebugQuickLaunch() {
        if let item = stateSnapshot.item(productID: Self.debugQuickLaunchProductID) {
            pendingDebugQuickLaunchProductID = nil
            launchCloudStream(titleId: item.typedTitleID, source: "debug_quick_launch")
            return
        }
        pendingDebugQuickLaunchProductID = Self.debugQuickLaunchProductID
        if !stateSnapshot.isLoading {
            Task { await refreshCloudLibrary(forceRefresh: true) }
        }
    }

    func attemptPendingDebugQuickLaunch() {
        guard let productID = pendingDebugQuickLaunchProductID else { return }
        guard activeStreamContext == nil else { return }
        guard let item = stateSnapshot.item(productID: productID) else { return }
        pendingDebugQuickLaunchProductID = nil
        launchCloudStream(titleId: item.typedTitleID, source: "debug_quick_launch_pending")
    }

    func handleSectionRefresh(oldSections: [CloudLibrarySection], newSections: [CloudLibrarySection]) {
        let majorRefresh = isMajorLibraryRefresh(oldSections: oldSections, newSections: newSections)
        logProjectionDebug(
            "sections_changed major=\(majorRefresh) old=[\(sectionSummary(oldSections))] new=[\(sectionSummary(newSections))] route=\(String(describing: routeState.browseRoute))"
        )
        if majorRefresh {
            vm.detailStateCache.removeAll()
            vm.detailHydrationInFlightTitleIDs.removeAll()
        } else {
            pruneDetailCaches(using: newSections)
        }
        if let scopedCategory = queryState.scopedCategory {
            let availableTitleIDs = Set(
                CloudLibraryDataSource.allLibraryItems(from: newSections).map(\.typedTitleID)
            )
            if scopedCategory.allowedTitleIDs.isDisjoint(with: availableTitleIDs) {
                queryState.scopedCategory = nil
            }
        }
        invalidateDetailCacheForChangedInputs()
        sceneModel.noteHydrationMarker(stateSnapshot.lastHydratedAt)
    }

    func logProjectionDebug(_ message: @autoclosure () -> String) {
        guard GLogger.isEnabled else { return }
        Self.uiLogger.info("CloudLibraryView projection: \(message())")
    }

    func logHomeStateTransition(
        oldState: CloudLibraryHomeViewState,
        newState: CloudLibraryHomeViewState
    ) {
        logProjectionDebug(
            "home_state oldCarousel=\(oldState.carouselItems.count) newCarousel=\(newState.carouselItems.count) oldRails=\(oldState.sections.count) newRails=\(newState.sections.count) newCarouselSample=[\(carouselSample(newState.carouselItems))] newRailSummary=[\(railSummary(newState.sections))]"
        )
    }

    func sectionSummary(_ sections: [CloudLibrarySection], limit: Int = 6) -> String {
        sections.prefix(limit)
            .map { "\($0.id):\($0.items.count)" }
            .joined(separator: ", ")
    }

    func carouselSample(_ items: [CloudLibraryHomeCarouselItemViewState], limit: Int = 5) -> String {
        items.prefix(limit)
            .map { "\($0.titleID.rawValue)|\($0.title.replacingOccurrences(of: "\"", with: "'"))" }
            .joined(separator: ", ")
    }

    func railSummary(_ sections: [CloudLibraryRailSectionViewState], limit: Int = 8) -> String {
        sections.prefix(limit)
            .map { "\($0.alias ?? $0.id):\($0.items.count)" }
            .joined(separator: ", ")
    }

    func pruneDetailCaches(using sections: [CloudLibrarySection]) {
        let validTitleIDs = Set(CloudLibraryDataSource.allLibraryItems(from: sections).map(\.typedTitleID))
        vm.detailStateCache.prune(validTitleIDs: validTitleIDs)
        vm.detailHydrationInFlightTitleIDs = vm.detailHydrationInFlightTitleIDs.intersection(validTitleIDs)
        focusState.setSettledHeroTileID(
            focusState.settledHeroTileID(for: CloudLibraryBrowseRoute.home).flatMap { validTitleIDs.contains($0) ? $0 : nil },
            for: CloudLibraryBrowseRoute.home
        )
        focusState.setSettledHeroTileID(
            focusState.settledHeroTileID(for: CloudLibraryBrowseRoute.library).flatMap { validTitleIDs.contains($0) ? $0 : nil },
            for: CloudLibraryBrowseRoute.library
        )
        focusState.focusedTileIDsByRoute = focusState.focusedTileIDsByRoute.filter { validTitleIDs.contains($0.value) }
    }

    func detailInputSignature(for item: CloudLibraryItem) -> String {
        var hasher = Hasher()
        hasher.combine(item.typedTitleID)
        hasher.combine(item.typedProductID)
        hasher.combine(item.name)
        hasher.combine(item.shortDescription ?? "")
        hasher.combine(item.publisherName ?? "")
        hasher.combine(item.isInMRU)
        hasher.combine(item.attributes.map(\.localizedName).joined(separator: "|"))
        hasher.combine(item.supportedInputTypes.joined(separator: "|"))
        hasher.combine(item.artURL?.absoluteString ?? "")
        hasher.combine(item.posterImageURL?.absoluteString ?? "")
        hasher.combine(item.heroImageURL?.absoluteString ?? "")
        hasher.combine(item.galleryImageURLs.map(\.absoluteString).joined(separator: "|"))
        if let detail = stateSnapshot.productDetail(productID: item.typedProductID) {
            hasher.combine(ProductID(rawValue: detail.productId))
            hasher.combine(detail.title ?? "")
            hasher.combine(detail.publisherName ?? "")
            hasher.combine(detail.shortDescription ?? "")
            hasher.combine(detail.longDescription ?? "")
            hasher.combine(detail.releaseDate ?? "")
            hasher.combine(detail.capabilityLabels.joined(separator: "|"))
            hasher.combine(detail.genreLabels.joined(separator: "|"))
            hasher.combine(detail.galleryImageURLs.map { $0.absoluteString }.joined(separator: "|"))
            hasher.combine(detail.mediaAssets.map { $0.id }.joined(separator: "|"))
            hasher.combine(detail.trailers.map { $0.id }.joined(separator: "|"))
            hasher.combine(detail.achievementSummary?.totalAchievements ?? -1)
            hasher.combine(detail.achievementSummary?.unlockedAchievements ?? -1)
            hasher.combine(detail.achievementSummary?.totalGamerscore ?? -1)
        } else {
            hasher.combine("no-detail")
        }
        if let achievements = achievementsController.titleAchievementSnapshot(titleID: item.typedTitleID) {
            hasher.combine(TitleID(rawValue: achievements.titleId))
            hasher.combine(Int(achievements.fetchedAt.timeIntervalSince1970))
            hasher.combine(achievements.summary.totalAchievements)
            hasher.combine(achievements.summary.unlockedAchievements)
            hasher.combine(achievements.summary.totalGamerscore)
            hasher.combine(achievements.achievements.count)
            for achievement in achievements.achievements.prefix(12) {
                hasher.combine(achievement.id)
                hasher.combine(achievement.unlocked)
                hasher.combine(achievement.percentComplete ?? -1)
                hasher.combine(achievement.gamerscore ?? -1)
            }
        } else {
            hasher.combine("no-achievements")
        }
        let errorText = achievementsController.lastTitleAchievementsError(titleID: item.typedTitleID)
        hasher.combine(errorText ?? "")
        return String(hasher.finalize())
    }

    func invalidateDetailCacheForChangedInputs() {
        let cachedTitleIDs = vm.detailStateCache.keys
        guard !cachedTitleIDs.isEmpty else { return }

        var currentSignatures: [TitleID: String] = [:]
        for titleID in cachedTitleIDs {
            guard let item = vm.cachedItemsByTitleID[titleID] else { continue }
            currentSignatures[titleID] = detailInputSignature(for: item)
        }
        let invalidatedTitleIDs = vm.detailStateCache.invalidateChangedEntries(currentSignatures: currentSignatures)
        guard !invalidatedTitleIDs.isEmpty else { return }

        for titleID in invalidatedTitleIDs {
            vm.detailHydrationInFlightTitleIDs.remove(titleID)
        }
    }

    func isMajorLibraryRefresh(oldSections: [CloudLibrarySection], newSections: [CloudLibrarySection]) -> Bool {
        sceneModel.isMajorLibraryRefresh(
            oldSections: oldSections,
            newSections: newSections,
            currentHydratedAt: stateSnapshot.lastHydratedAt
        )
    }
}
