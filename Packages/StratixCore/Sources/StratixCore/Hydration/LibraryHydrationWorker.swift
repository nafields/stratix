// LibraryHydrationWorker.swift
// Defines library hydration worker for the Hydration surface.
//

import Foundation
import StratixModels
import XCloudAPI

/// Defines the cache-loading surface the hydration workflows use before any live fetch begins.
protocol LibraryHydrationWorking: Sendable {
    func loadStartupCachePayload(
        loadProductDetails: Bool,
        loadSections: Bool
    ) async -> LibraryStartupCachePayload
    func loadProductDetailsCacheSnapshot() async -> ProductDetailsCacheLoadResult
    func loadDecodedSectionsCacheSnapshot() async -> DecodedLibrarySectionsCacheSnapshot?
    func loadHomeMerchandisingCacheSnapshot() async -> HomeMerchandisingDiskCacheSnapshot?
}

/// Loads startup cache inputs from disk-backed stores so the orchestrator can restore state
/// without knowing how individual caches are persisted.
actor LibraryHydrationWorker: LibraryHydrationWorking {
    private let detailsCacheURL: URL
    private let repository: any LibraryRepository

    init(
        detailsCacheURL: URL,
        repository: any LibraryRepository
    ) {
        self.detailsCacheURL = detailsCacheURL
        self.repository = repository
    }

    init(
        detailsCacheURL: URL,
        sectionsCacheURL: URL,
        repositoryStoreURL: URL? = nil,
        homeMerchandisingCacheURL _: URL
    ) {
        let repository: any LibraryRepository
        do {
            let storeURL = repositoryStoreURL
                ?? sectionsCacheURL.deletingPathExtension().appendingPathExtension("swiftdata")
            repository = try SwiftDataLibraryRepository(storeURL: storeURL)
        } catch {
            fatalError("Failed to initialize library repository: \(error)")
        }
        self.init(detailsCacheURL: detailsCacheURL, repository: repository)
    }

    /// Reads the requested cache fragments in parallel and returns one startup-restore payload.
    func loadStartupCachePayload(
        loadProductDetails: Bool,
        loadSections: Bool
    ) async -> LibraryStartupCachePayload {
        async let productDetails: ProductDetailsCacheLoadResult = if loadProductDetails {
            await loadProductDetailsCacheSnapshot()
        } else {
            .unavailable
        }

        async let sectionsSnapshot: DecodedLibrarySectionsCacheSnapshot? = if loadSections {
            await loadDecodedSectionsCacheSnapshot()
        } else {
            nil
        }

        return await LibraryStartupCachePayload(
            productDetails: productDetails,
            sectionsSnapshot: sectionsSnapshot
        )
    }

    /// Decodes the product-details cache off the main actor and reports whether the on-disk
    /// format is current, legacy, or unavailable.
    func loadProductDetailsCacheSnapshot() async -> ProductDetailsCacheLoadResult {
        let detailsCacheURL = self.detailsCacheURL
        return await Task.detached(priority: .background) {
            guard let data = try? Data(contentsOf: detailsCacheURL, options: .mappedIfSafe) else {
                return ProductDetailsCacheLoadResult.unavailable
            }

            let decoder = JSONDecoder()
            if let snapshot = try? decoder.decode(ProductDetailsDiskCacheSnapshot.self, from: data) {
                return .snapshot(snapshot)
            }
            if (try? decoder.decode([String: CloudLibraryProductDetail].self, from: data)) != nil {
                return .legacyUnversioned
            }
            return ProductDetailsCacheLoadResult.unavailable
        }.value
    }

    func loadDecodedSectionsCacheSnapshot() async -> DecodedLibrarySectionsCacheSnapshot? {
        await repository.loadUnifiedSectionsSnapshot()
    }

    func loadHomeMerchandisingCacheSnapshot() async -> HomeMerchandisingDiskCacheSnapshot? {
        nil
    }
}
