// LibraryDetailWorkflow.swift
// Defines library detail workflow.
//

import Foundation
import StratixModels
import XCloudAPI

@MainActor
extension LibraryController {
    private struct LibraryDetailLoadContext: Sendable {
        let trimmedProductID: String
        let locale: String
        let credentials: XboxWebCredentials
        let session: URLSession
    }

    public func loadDetail(
        productID: ProductID,
        locale: String = "en-US",
        forceRefresh: Bool = false
    ) async {
        guard !isSuspendedForStreaming else {
            logger.info("Catalog detail request skipped: suspended for streaming")
            return
        }
        let trimmedProductID = productID.rawValue
        guard !trimmedProductID.isEmpty else { return }

        logger.info(
            "Catalog detail request: productId=\(trimmedProductID) forceRefresh=\(forceRefresh)"
        )

        let cachedDetail = state.productDetails[productID]
        if !forceRefresh, let cachedDetail, hasRichMedia(cachedDetail) {
            return
        }
        if !forceRefresh, cachedDetail != nil {
            logger.info("Rich catalog detail refreshing cached thin entry: \(trimmedProductID)")
        }

        let (task, inserted) = await taskRegistry.taskOrRegister(
            group: TaskGroupID.cloudLibraryProductDetail,
            key: trimmedProductID
        ) {
            Task { [weak self] in
                guard let self else { return }
                if let detailWorkflow = self.detailWorkflow {
                    await detailWorkflow(self, trimmedProductID, trimmedProductID, locale)
                    return
                }
                await self.performDetailWorkflow(
                    trimmedProductID: trimmedProductID,
                    normalizedProductID: trimmedProductID,
                    locale: locale
                )
            }
        }
        logger.info(
            inserted
                ? "Catalog detail starting request: \(trimmedProductID)"
                : "Catalog detail join existing request: \(trimmedProductID)"
        )
        await task.value
        if inserted {
            await taskRegistry.remove(
                group: TaskGroupID.cloudLibraryProductDetail,
                key: trimmedProductID
            )
        }
    }

    func performDetailWorkflow(
        trimmedProductID: String,
        normalizedProductID: String,
        locale: String
    ) async {
        guard !isSuspendedForStreaming else { return }
        guard let context = await makeLibraryDetailLoadContext(
            trimmedProductID: trimmedProductID,
            locale: locale
        ) else {
            logger.warning("Rich catalog detail skipped: missing Xbox web credentials")
            return
        }

        do {
            var detail = try await Self.loadCloudLibraryProductDetail(context: context)
            if let achievementSummary = achievementSummary(productID: ProductID(trimmedProductID)) {
                detail = Self.detail(detail, with: achievementSummary)
            }
            insertProductDetail(detail, primaryKey: normalizedProductID)
        } catch {
            if isTaskCancellation(error) {
                return
            }
            logger.warning("Rich catalog detail fetch failed (\(trimmedProductID)): \(logString(for: error))")
        }
    }

    private func makeLibraryDetailLoadContext(
        trimmedProductID: String,
        locale: String
    ) async -> LibraryDetailLoadContext? {
        guard let credentials = await dependencies?.xboxWebCredentials(logContext: "catalog detail fetch") else {
            return nil
        }
        return LibraryDetailLoadContext(
            trimmedProductID: trimmedProductID,
            locale: locale,
            credentials: credentials,
            session: URLSession.shared
        )
    }

    private nonisolated static func loadCloudLibraryProductDetail(
        context: LibraryDetailLoadContext
    ) async throws -> CloudLibraryProductDetail {
        let rich = try await XboxComProductDetailsClient(
            credentials: context.credentials,
            session: context.session
        ).getProductDetails(
            productId: context.trimmedProductID,
            locale: context.locale
        )
        return makeCloudLibraryProductDetail(from: rich)
    }

    private func achievementSummary(productID: ProductID) -> TitleAchievementSummary? {
        guard let item = item(productID: productID) else { return nil }
        return dependencies?.achievementSnapshot(titleID: TitleID(item.titleId))?.summary
    }

    private nonisolated static func detail(
        _ detail: CloudLibraryProductDetail,
        with achievementSummary: TitleAchievementSummary
    ) -> CloudLibraryProductDetail {
        CloudLibraryProductDetail(
            productId: detail.productId,
            title: detail.title,
            publisherName: detail.publisherName,
            shortDescription: detail.shortDescription,
            longDescription: detail.longDescription,
            developerName: detail.developerName,
            releaseDate: detail.releaseDate,
            capabilityLabels: detail.capabilityLabels,
            genreLabels: detail.genreLabels,
            mediaAssets: detail.mediaAssets,
            galleryImageURLs: detail.galleryImageURLs,
            trailers: detail.trailers,
            achievementSummary: achievementSummary
        )
    }

    func insertProductDetail(_ detail: CloudLibraryProductDetail, primaryKey: String) {
        let normalizedPrimaryKey = ProductID(primaryKey)
        guard !normalizedPrimaryKey.rawValue.isEmpty else { return }
        var nextDetails = state.productDetails
        nextDetails[normalizedPrimaryKey] = detail
        let normalizedDetailKey = ProductID(detail.productId)
        if !normalizedDetailKey.rawValue.isEmpty, normalizedDetailKey != normalizedPrimaryKey {
            nextDetails[normalizedDetailKey] = detail
        }
        apply(.productDetailsReplaced(nextDetails))
        trimProductDetailsCacheToLimit()
        saveProductDetailsCache()
    }

    func trimProductDetailsCacheToLimit() {
        var nextDetails = state.productDetails
        while nextDetails.count > Self.productDetailsCacheSizeLimit,
              let evictedKey = nextDetails.keys.first {
            nextDetails.removeValue(forKey: evictedKey)
        }
        if nextDetails != state.productDetails {
            apply(.productDetailsReplaced(nextDetails))
        }
    }

    private func hasRichMedia(_ cached: CloudLibraryProductDetail) -> Bool {
        if cached.mediaAssets.contains(where: { $0.source == .productDetails }) {
            return true
        }

        if cached.mediaAssets.contains(where: { asset in
            guard asset.source == .productDetails, asset.kind == .image else { return false }
            return Self.isLikelyGameplayScreenshotURL(asset.url)
        }) {
            return true
        }

        let hasProductDetailsTrailers = cached.mediaAssets.contains { asset in
            asset.source == .productDetails && asset.kind == .video
        } || !cached.trailers.isEmpty
        guard hasProductDetailsTrailers else { return false }

        return cached.mediaAssets.contains { asset in
            asset.source == .productDetails
                && asset.kind == .video
                && asset.thumbnailURL != nil
        } || cached.trailers.contains { $0.thumbnailURL != nil }
    }
}
