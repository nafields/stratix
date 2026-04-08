// StreamHeroArtworkService.swift
// Defines stream hero artwork service for the Streaming surface.
//

import Foundation
import StratixModels
import XCloudAPI

struct StreamHeroArtworkEnvironment: Sendable {
    let cachedItem: @Sendable (TitleID) async -> CloudLibraryItem?
    let xboxWebCredentials: @Sendable (String) async -> XboxWebCredentials?
    let urlSession: URLSession
    let fetchProductDetails: @Sendable (String, XboxWebCredentials, URLSession) async throws -> XboxComProductDetails
}

struct StreamHeroArtworkService {
    func fetchHeroArt(
        titleId: TitleID,
        environment: StreamHeroArtworkEnvironment
    ) async -> URL? {
        let cachedItem = await environment.cachedItem(titleId)
        if let cached = cachedItem {
            if let cachedArtwork = cached.heroImageURL ?? cached.posterImageURL ?? cached.artURL {
                return cachedArtwork
            }
        }

        guard let credentials = await environment.xboxWebCredentials("hero art fetch") else {
            return nil
        }

        do {
            let productId = cachedItem?.productId ?? titleId.rawValue
            let details = try await environment.fetchProductDetails(
                productId,
                credentials,
                environment.urlSession
            )
            return details.galleryImageURLs.first
        } catch {
            return nil
        }
    }

    func resolveLaunchHeroURL(
        titleId: TitleID,
        currentHeroURL: URL?,
        environment: StreamHeroArtworkEnvironment
    ) async -> URL? {
        guard currentHeroURL == nil else { return currentHeroURL }
        return await fetchHeroArt(titleId: titleId, environment: environment)
    }
}
