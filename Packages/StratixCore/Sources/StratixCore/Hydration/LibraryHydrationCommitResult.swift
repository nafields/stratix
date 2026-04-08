// LibraryHydrationCommitResult.swift
// Defines library hydration commit result for the Hydration surface.
//

import Foundation

struct LibraryHydrationCommitResult: Sendable {
    let persistenceIntent: LibraryHydrationPersistenceIntent
    let cachedDiscovery: HomeMerchandisingDiscoveryCachePayload?
    let actions: [LibraryAction]
    let shouldPrefetchArtwork: Bool
    let shouldWarmProfileAndSocial: Bool
    let publicationPlan: LibraryHydrationPublicationPlan
    let postStreamResult: PostStreamRefreshResult?
}
