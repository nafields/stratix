// LibraryRuntimeAction.swift
// Defines library runtime action.
//

import Foundation

enum LibraryRuntimeAction: Sendable, Equatable {
    case networkHydrationPerformedSet(Bool)
    case loadedProductDetailsCacheSet(Bool)
    case loadedSectionsCacheSet(Bool)
    case artworkPrefetchDisabledForSessionSet(Bool)
    case artworkPrefetchStartedAtSet(Date?)
    case artworkPrefetchLastCompletedAtByURLSet([String: Date])
    case suspendedForStreamingSet(Bool)
    case cachedHomeMerchandisingDiscoverySet(HomeMerchandisingDiscoveryCachePayload?)
}

enum LibraryRuntimeReducer {
    static func reduce(
        state: LibraryRuntimeState,
        action: LibraryRuntimeAction
    ) -> LibraryRuntimeState {
        var next = state

        switch action {
        case .networkHydrationPerformedSet(let value):
            next.hasPerformedNetworkHydrationThisSession = value
        case .loadedProductDetailsCacheSet(let value):
            next.hasLoadedProductDetailsCache = value
        case .loadedSectionsCacheSet(let value):
            next.hasLoadedSectionsCache = value
        case .artworkPrefetchDisabledForSessionSet(let value):
            next.isArtworkPrefetchDisabledForSession = value
        case .artworkPrefetchStartedAtSet(let value):
            next.lastArtworkPrefetchStartedAt = value
        case .artworkPrefetchLastCompletedAtByURLSet(let value):
            next.artworkPrefetchLastCompletedAtByURL = value
        case .suspendedForStreamingSet(let value):
            next.isSuspendedForStreaming = value
        case .cachedHomeMerchandisingDiscoverySet(let value):
            next.cachedHomeMerchandisingDiscovery = value
        }

        return next
    }
}
