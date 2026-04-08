// LibraryRuntimeState.swift
// Defines the library runtime state.
//

import Foundation

struct LibraryRuntimeState: Sendable, Equatable {
    var hasPerformedNetworkHydrationThisSession = false
    var hasLoadedProductDetailsCache = false
    var hasLoadedSectionsCache = false
    var isArtworkPrefetchDisabledForSession = false
    var isSuspendedForStreaming = false
    var lastArtworkPrefetchStartedAt: Date?
    var artworkPrefetchLastCompletedAtByURL: [String: Date] = [:]
    var cachedHomeMerchandisingDiscovery: LibraryController.CachedHomeMerchandisingDiscovery?
}
