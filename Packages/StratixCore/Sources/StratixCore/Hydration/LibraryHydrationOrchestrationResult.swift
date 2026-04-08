// LibraryHydrationOrchestrationResult.swift
// Defines library hydration orchestration result for the Hydration surface.
//

import Foundation

struct LibraryHydrationOrchestrationResult: Sendable {
    let actions: [LibraryAction]
    let persistenceIntent: LibraryHydrationPersistenceIntent
    let cachedDiscovery: HomeMerchandisingDiscoveryCachePayload?
    let source: LibraryHydrationTrigger
    let publicationPlan: LibraryHydrationPublicationPlan
    let postStreamResult: PostStreamRefreshResult?
}
