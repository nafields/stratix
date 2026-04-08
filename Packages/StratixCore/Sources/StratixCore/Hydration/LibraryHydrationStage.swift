// LibraryHydrationStage.swift
// Defines library hydration stage for the Hydration surface.
//

import Foundation

enum LibraryHydrationStage: Int, Codable, Sendable, Equatable {
    case authShell
    case routeRestore
    case mruAndHero
    case visibleRows
    case detailsAndSecondaryRows
    case socialAndProfile
    case backgroundArtwork
}
