// LibraryHydrationLiveFetchResult.swift
// Defines library hydration live fetch result for the Hydration surface.
//

import Foundation
import StratixModels
import XCloudAPI

struct LibraryHydrationLiveFetchResult: Sendable {
    let catalogState: LibraryHydrationCatalogState
    let committedSections: [CloudLibrarySection]
    let seededProductDetails: CatalogProductDetailsSeedState
    let recoveryState: LibraryHydrationRecoveryState?
    let merchandisingSnapshot: HomeMerchandisingSnapshot?
    let merchandisingDiscovery: HomeMerchandisingDiscoveryCachePayload?
    let hydratedCatalogProducts: [GamePassCatalogClient.CatalogProduct]
    let hydratedProductCount: Int
}
