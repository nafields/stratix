// CloudLibraryModels.swift
// Defines the cloud library models.
//

import Foundation

// MARK: - xCloud Library DTOs

/// Top-level response DTO returned by the xCloud titles library endpoint.
public struct XCloudTitlesResponse: Decodable, Sendable {
    public let results: [XCloudTitleDTO]

    public init(results: [XCloudTitleDTO]) {
        self.results = results
    }
}

/// Raw title DTO from the xCloud library endpoint before projection into shared domain models.
public struct XCloudTitleDTO: Decodable, Sendable {
    public let titleId: String?
    public let details: Details?

    public init(titleId: String?, details: Details?) {
        self.titleId = titleId
        self.details = details
    }

    /// Nested title details block containing the fields the app projects into browse models.
    public struct Details: Decodable, Sendable {
        public let productId: String?
        public let name: String?
        public let hasEntitlement: Bool?
        public let supportedInputTypes: [String]?

        public init(productId: String?, name: String?, hasEntitlement: Bool?, supportedInputTypes: [String]?) {
            self.productId = productId
            self.name = name
            self.hasEntitlement = hasEntitlement
            self.supportedInputTypes = supportedInputTypes
        }
    }
}
