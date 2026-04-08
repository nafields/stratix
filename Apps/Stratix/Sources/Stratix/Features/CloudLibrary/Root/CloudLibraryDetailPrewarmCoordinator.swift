// CloudLibraryDetailPrewarmCoordinator.swift
// Defines the cloud library detail prewarm coordinator for the CloudLibrary / Root surface.
//

import Foundation
import StratixCore
import StratixModels

@MainActor
/// Loads and caches detail projections ahead of navigation so the pushed detail view can render from hot state.
struct CloudLibraryDetailPrewarmCoordinator {
    typealias DetailLoader = @MainActor (ProductID) async -> Void
    typealias AchievementsLoader = @MainActor (TitleID) async -> Void
    typealias DetailLookup = @MainActor (ProductID) -> CloudLibraryProductDetail?
    typealias AchievementLookup = @MainActor (TitleID) -> TitleAchievementSnapshot?
    typealias AchievementErrorLookup = @MainActor (TitleID) -> String?

    /// Reuses a matching hot-cache entry when possible, otherwise performs the full detail and achievements warmup.
    func prewarmDetailState(
        titleID: TitleID,
        item: CloudLibraryItem,
        originRoute: AppRoute,
        viewModel: CloudLibraryViewModel,
        loadDetail: DetailLoader,
        loadAchievements: AchievementsLoader,
        productDetail: DetailLookup,
        achievementSnapshot: AchievementLookup,
        achievementErrorText: AchievementErrorLookup
    ) async {
        let initialSnapshot = makeDetailSnapshot(
            item: item,
            originRoute: originRoute,
            productDetail: productDetail(item.typedProductID),
            achievementSnapshot: achievementSnapshot(titleID),
            achievementErrorText: achievementErrorText(titleID),
            isHydrating: false
        )
        let initialSignature = detailInputSignature(for: initialSnapshot)

        if let entry = viewModel.detailStateCache.peek(titleID),
           entry.inputSignature == initialSignature {
            viewModel.detailStateCache.touch(titleID)
            return
        }

        viewModel.detailHydrationInFlightTitleIDs.insert(titleID)
        defer {
            viewModel.detailHydrationInFlightTitleIDs.remove(titleID)
        }

        async let detailTask: Void = loadDetail(item.typedProductID)
        async let achievementsTask: Void = loadAchievements(titleID)
        _ = await (detailTask, achievementsTask)

        let finalSnapshot = makeDetailSnapshot(
            item: item,
            originRoute: originRoute,
            productDetail: productDetail(item.typedProductID),
            achievementSnapshot: achievementSnapshot(titleID),
            achievementErrorText: achievementErrorText(titleID),
            isHydrating: false
        )
        let finalSignature = detailInputSignature(for: finalSnapshot)
        let detailState = CloudLibraryDataSource.detailState(from: finalSnapshot)
        viewModel.detailStateCache.insert(
            state: detailState,
            for: titleID,
            inputSignature: finalSignature
        )
    }

    /// Captures the current detail inputs in the shape expected by the data-source projection layer.
    func makeDetailSnapshot(
        item: CloudLibraryItem,
        originRoute: AppRoute,
        productDetail: CloudLibraryProductDetail?,
        achievementSnapshot: TitleAchievementSnapshot?,
        achievementErrorText: String?,
        isHydrating: Bool
    ) -> CloudLibraryDataSource.DetailStateSnapshot {
        CloudLibraryDataSource.detailSnapshot(
            for: item,
            richDetail: productDetail,
            achievementSnapshot: achievementSnapshot,
            achievementErrorText: achievementErrorText,
            isHydrating: isHydrating,
            previousBaseRoute: originRoute
        )
    }

    /// Produces a stable cache key from the detail inputs that materially affect rendered detail state.
    func detailInputSignature(for snapshot: CloudLibraryDataSource.DetailStateSnapshot) -> String {
        var hasher = Hasher()
        let item = snapshot.item
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
        if let detail = snapshot.richDetail {
            hasher.combine(ProductID(rawValue: detail.productId))
            hasher.combine(detail.title ?? "")
            hasher.combine(detail.publisherName ?? "")
            hasher.combine(detail.shortDescription ?? "")
            hasher.combine(detail.longDescription ?? "")
            hasher.combine(detail.releaseDate ?? "")
            hasher.combine(detail.capabilityLabels.joined(separator: "|"))
            hasher.combine(detail.genreLabels.joined(separator: "|"))
            hasher.combine(detail.galleryImageURLs.map(\.absoluteString).joined(separator: "|"))
            hasher.combine(detail.mediaAssets.map(\.id).joined(separator: "|"))
            hasher.combine(detail.trailers.map(\.id).joined(separator: "|"))
            hasher.combine(detail.achievementSummary?.totalAchievements ?? -1)
            hasher.combine(detail.achievementSummary?.unlockedAchievements ?? -1)
            hasher.combine(detail.achievementSummary?.totalGamerscore ?? -1)
        } else {
            hasher.combine("no-detail")
        }
        if let achievements = snapshot.achievementSnapshot {
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
        hasher.combine(snapshot.achievementErrorText ?? "")
        return String(hasher.finalize())
    }
}
