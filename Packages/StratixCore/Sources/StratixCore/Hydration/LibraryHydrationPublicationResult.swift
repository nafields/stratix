// LibraryHydrationPublicationResult.swift
// Defines library hydration publication result for the Hydration surface.
//

import Foundation

struct LibraryHydrationPublicationResult: Sendable, Equatable {
    let completedStages: [LibraryHydrationStage]
}
