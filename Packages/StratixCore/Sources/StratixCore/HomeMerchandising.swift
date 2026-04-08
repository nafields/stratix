// HomeMerchandising.swift
// Defines home merchandising.
//

import Foundation
import StratixModels

public struct HomeMerchandisingRow: Sendable, Equatable {
    public enum Source: String, Sendable {
        case fixedPriority
        case discoveredExtra
    }

    public let alias: String
    public let label: String
    public let source: Source
    public let items: [CloudLibraryItem]

    public init(alias: String, label: String, source: Source, items: [CloudLibraryItem]) {
        self.alias = alias
        self.label = label
        self.source = source
        self.items = items
    }
}

public struct HomeMerchandisingSnapshot: Sendable, Equatable {
    public let recentlyAddedItems: [CloudLibraryItem]
    public let rows: [HomeMerchandisingRow]
    public let generatedAt: Date

    public init(
        recentlyAddedItems: [CloudLibraryItem],
        rows: [HomeMerchandisingRow],
        generatedAt: Date = Date()
    ) {
        self.recentlyAddedItems = recentlyAddedItems
        self.rows = rows
        self.generatedAt = generatedAt
    }
}
