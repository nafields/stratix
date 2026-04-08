// ProductID.swift
// Defines product id for the Identifiers surface.
//

import Foundation

public struct ProductID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}
