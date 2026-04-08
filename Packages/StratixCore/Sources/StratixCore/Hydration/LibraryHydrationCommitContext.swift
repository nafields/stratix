// LibraryHydrationCommitContext.swift
// Defines library hydration commit context for the Hydration surface.
//

import Foundation

struct LibraryHydrationCommitContext: Sendable, Equatable {
    let trigger: LibraryHydrationTrigger
    let market: String
    let language: String
    let shouldPersist: Bool
    let shouldPrefetchArtwork: Bool
    let shouldAdvanceHomeReadiness: Bool
    let shouldWarmProfileAndSocial: Bool
}
