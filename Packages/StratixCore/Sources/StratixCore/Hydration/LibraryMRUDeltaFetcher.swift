// LibraryMRUDeltaFetcher.swift
// Defines library mru delta fetcher for the Hydration surface.
//

import Foundation
import StratixModels
import XCloudAPI

@MainActor
enum LibraryMRUDeltaFetcher {
    static func fetchLiveMRUEntries(
        tokens: StreamTokens,
        mruLimit: Int,
        resolveHost: (_ gsToken: String, _ preferredHost: String?) async throws -> String,
        logInfo: (String) -> Void,
        logWarning: (String) -> Void,
        formatError: (Error) -> String
    ) async throws -> [LibraryMRUEntry] {
        let tokenCandidates = LibraryTokenCandidateResolver.makeCandidates(tokens: tokens)
        guard !tokenCandidates.isEmpty else { throw AuthError.noStreamToken }

        for candidate in tokenCandidates {
            do {
                let libraryHost = try await resolveHost(candidate.token, candidate.preferredHost)
                let xcloudClient = XCloudAPIClient(baseHost: libraryHost, gsToken: candidate.token)
                let response = try await xcloudClient.getCloudTitlesMRU(limit: mruLimit)
                let liveEntries = response.results.compactMap { dto -> LibraryMRUEntry? in
                    guard let rawTitleId = dto.titleId,
                          let rawProductId = dto.details?.productId,
                          let titleId = Optional(TitleID(rawTitleId)),
                          let productId = Optional(ProductID(rawProductId)),
                          !productId.rawValue.isEmpty else { return nil }
                    return LibraryMRUEntry(titleID: titleId, productID: productId)
                }
                logInfo("Post-stream delta refresh MRU count: \(liveEntries.count) source=\(candidate.label)")
                return liveEntries
            } catch {
                logWarning("Post-stream delta MRU fetch failed (\(candidate.label)): \(formatError(error))")
            }
        }

        throw AuthError.invalidResponse("Could not fetch a post-stream MRU snapshot from any library token candidate.")
    }
}
