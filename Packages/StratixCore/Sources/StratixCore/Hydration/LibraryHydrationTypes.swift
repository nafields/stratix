// LibraryHydrationTypes.swift
// Defines library hydration types for the Hydration surface.
//

import Foundation
import StratixModels

enum ProductDetailsCacheLoadResult: Sendable {
    case snapshot(ProductDetailsDiskCacheSnapshot)
    case legacyUnversioned
    case unavailable
}

struct LibraryStartupCachePayload: Sendable {
    let productDetails: ProductDetailsCacheLoadResult
    let sectionsSnapshot: DecodedLibrarySectionsCacheSnapshot?
}

enum ProductDetailsStartupRestoreOutcome: Sendable {
    case unavailable
    case apply([ProductID: CloudLibraryProductDetail])
    case rejectLegacyUnversioned
    case rejectVersionMismatch(found: Int, expected: Int)
}

enum SectionsStartupRestoreOutcome: Sendable {
    case unavailable
    case apply(DecodedLibrarySectionsCacheSnapshot)
    case rejectVersionMismatch(found: Int, expected: Int)
    case rejectUnifiedSnapshot(reason: String, snapshot: DecodedLibrarySectionsCacheSnapshot)
}

struct LibraryStartupRestoreResult: Sendable {
    let productDetails: ProductDetailsStartupRestoreOutcome?
    let sections: SectionsStartupRestoreOutcome?
}

struct ShellBootHydrationPlan: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case refreshNetwork
        case prefetchCached
    }

    let mode: Mode
    let statusText: String
    let deferInitialRoutePublication: Bool
    let minimumVisibleDuration: Duration
    let decisionDescription: String
}

struct PostStreamHydrationPlan: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case refreshMRUDelta
        case refreshNetwork
    }

    let mode: Mode
    let decisionDescription: String
}

enum PostStreamRefreshResult: Equatable, Sendable {
    case appliedDelta
    case noChange
    case requiresFullRefresh(String)
}

enum MRUDeltaSectionsResult: Equatable, Sendable {
    case updated([CloudLibrarySection])
    case noChange
    case requiresFullRefresh(String)
}
