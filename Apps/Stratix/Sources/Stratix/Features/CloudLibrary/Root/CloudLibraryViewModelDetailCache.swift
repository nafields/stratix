// CloudLibraryViewModelDetailCache.swift
// Defines cloud library view model detail cache for the CloudLibrary / Root surface.
//

import Foundation
import StratixCore
import StratixModels

@MainActor
extension CloudLibraryViewModel {
    func prewarmDetailState(
        titleID: TitleID,
        snapshot: CloudLibraryDataSource.DetailStateSnapshot
    ) {
        let inputSignature = detailInputSignature(for: snapshot)
        if let entry = detailStateCache.peek(titleID),
           entry.inputSignature == inputSignature {
            detailStateCache.touch(titleID)
            detailHydrationInFlightTitleIDs.remove(titleID)
            return
        }

        let detailState = CloudLibraryDataSource.detailState(from: snapshot)
        detailStateCache.insert(state: detailState, for: titleID, inputSignature: inputSignature)
        detailHydrationInFlightTitleIDs.remove(titleID)
    }

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
