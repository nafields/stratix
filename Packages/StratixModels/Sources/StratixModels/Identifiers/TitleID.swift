// TitleID.swift
// Defines title id for the Identifiers surface.
//

import Foundation

public struct TitleID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}
