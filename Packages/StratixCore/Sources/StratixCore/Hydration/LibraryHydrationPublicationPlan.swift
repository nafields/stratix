// LibraryHydrationPublicationPlan.swift
// Defines library hydration publication plan for the Hydration surface.
//

import Foundation

struct LibraryHydrationPublicationPlan: Sendable, Equatable {
    let stages: [LibraryHydrationStage]
}
