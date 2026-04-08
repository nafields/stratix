// XboxComProductDetailsClient.swift
// Defines the xbox com product details client.
//

import Foundation
import StratixModels

public struct XboxComTrailer: Sendable, Equatable {
    public let title: String
    public let playbackURL: URL?
    public let thumbnailURL: URL?

    public init(title: String, playbackURL: URL?, thumbnailURL: URL? = nil) {
        self.title = title
        self.playbackURL = playbackURL
        self.thumbnailURL = thumbnailURL
    }
}

public struct XboxComProductDetails: Sendable, Equatable {
    public let productId: String
    public let title: String?
    public let publisherName: String?
    public let shortDescription: String?
    public let longDescription: String?
    public let developerName: String?
    public let releaseDate: String?
    public let capabilityLabels: [String]
    public let genreLabels: [String]
    public let mediaAssets: [CloudLibraryMediaAsset]
    public let galleryImageURLs: [URL]
    public let trailers: [XboxComTrailer]

    public init(
        productId: String,
        title: String? = nil,
        publisherName: String? = nil,
        shortDescription: String? = nil,
        longDescription: String? = nil,
        developerName: String? = nil,
        releaseDate: String? = nil,
        capabilityLabels: [String] = [],
        genreLabels: [String] = [],
        mediaAssets: [CloudLibraryMediaAsset] = [],
        galleryImageURLs: [URL] = [],
        trailers: [XboxComTrailer] = []
    ) {
        self.productId = productId
        self.title = title
        self.publisherName = publisherName
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.developerName = developerName
        self.releaseDate = releaseDate
        self.capabilityLabels = capabilityLabels
        self.genreLabels = genreLabels
        self.mediaAssets = mediaAssets
        self.galleryImageURLs = galleryImageURLs
        self.trailers = trailers
    }
}

public actor XboxComProductDetailsClient {
    let session: URLSession
    let credentials: XboxWebCredentials
    let baseURL = URL(string: "https://emerald.xboxservices.com")!

    public init(credentials: XboxWebCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: - Public API

    public func getProductDetails(
        productId: String,
        locale: String = "en-US",
        enableFullDetail: Bool = true
    ) async throws -> XboxComProductDetails {
        let requestContext = try makeProductDetailsRequest(
            productId: productId,
            locale: locale,
            enableFullDetail: enableFullDetail
        )

        let (data, response) = try await session.data(for: requestContext.request)
        try Self.validateProductDetailsResponse(data: data, response: response)

        do {
            return try Self.parseProductDetails(
                data: data,
                fallbackProductID: requestContext.productID,
                locale: locale
            )
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.decodingError("\(error.localizedDescription) | body: \(String(body.prefix(512)))")
        }
    }

    // MARK: - Request Construction

    typealias ProductDetailsRequestContext = (productID: String, request: URLRequest)

    func makeProductDetailsRequest(
        productId: String,
        locale: String,
        enableFullDetail: Bool
    ) throws -> ProductDetailsRequestContext {
        let trimmedProductID = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProductID.isEmpty else {
            throw APIError.decodingError("Missing productId")
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("xboxcomfd/productdetails/\(trimmedProductID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "enableFullDetail", value: enableFullDetail ? "true" : "false"),
            URLQueryItem(name: "locale", value: locale)
        ]

        guard let url = components.url else {
            throw APIError.notReady
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2.0", forHTTPHeaderField: "x-ms-api-version")
        request.setValue(Self.makeCorrelationVector(), forHTTPHeaderField: "MS-CV")
        request.setValue("https://play.xbox.com", forHTTPHeaderField: "Origin")
        request.setValue("XBL3.0 x=\(credentials.uhs);\(credentials.token)", forHTTPHeaderField: "Authorization")
        return (trimmedProductID, request)
    }

    static func validateProductDetailsResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }
    }
}
