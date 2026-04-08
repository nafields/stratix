// LibraryHydrationMetadata.swift
// Defines library hydration metadata for the Hydration surface.
//

import Foundation

struct LibraryHydrationMetadata: Codable, Sendable, Equatable {
    let snapshotID: UUID
    let generatedAt: Date
    let cacheVersion: Int
    let market: String
    let language: String
    let refreshSource: String
    let hydrationGeneration: UInt64
    let homeReady: Bool
    let completenessBySectionID: [String: Bool]
    let deferredStages: [LibraryHydrationStage]
    let trigger: String

    init(
        snapshotID: UUID,
        generatedAt: Date,
        cacheVersion: Int,
        market: String,
        language: String,
        refreshSource: String,
        hydrationGeneration: UInt64,
        homeReady: Bool,
        completenessBySectionID: [String: Bool],
        deferredStages: [LibraryHydrationStage] = [],
        trigger: String = "legacy_decode"
    ) {
        self.snapshotID = snapshotID
        self.generatedAt = generatedAt
        self.cacheVersion = cacheVersion
        self.market = market
        self.language = language
        self.refreshSource = refreshSource
        self.hydrationGeneration = hydrationGeneration
        self.homeReady = homeReady
        self.completenessBySectionID = completenessBySectionID
        self.deferredStages = deferredStages
        self.trigger = trigger
    }
}

extension LibraryHydrationMetadata {
    static func compatibility(
        savedAt: Date,
        cacheVersion: Int,
        refreshSource: String = "legacy_decode",
        homeReady: Bool = false
    ) -> LibraryHydrationMetadata {
        LibraryHydrationMetadata(
            snapshotID: UUID(),
            generatedAt: savedAt,
            cacheVersion: cacheVersion,
            market: "unknown",
            language: "unknown",
            refreshSource: refreshSource,
            hydrationGeneration: 0,
            homeReady: homeReady,
            completenessBySectionID: [:],
            deferredStages: [],
            trigger: "legacy_decode"
        )
    }
}
