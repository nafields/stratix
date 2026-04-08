// GamePassCatalogClient.swift
// Defines the game pass catalog client.
//

import Foundation

/// Catalog client for hydrating product IDs into richer Game Pass metadata and media fields.
public final class GamePassCatalogClient: Sendable {
    /// Request body expected by the catalog hydration endpoint.
    public struct HydrateRequest: Encodable, Sendable {
        public let Products: [String]

        public init(Products: [String]) {
            self.Products = Products
        }
    }

    /// Decoded hydration payload, normalized across the endpoint's array and dictionary response shapes.
    public struct HydrateResponse: Decodable, Sendable {
        public let Products: [CatalogProduct]

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let array = try? container.decode([CatalogProduct].self, forKey: .Products) {
                Products = array
                return
            }
            let dict = try container.decode([String: CatalogProductValue].self, forKey: .Products)
            Products = dict.compactMap { key, value in
                let productId = value.ProductId ?? value.StoreId ?? key
                return CatalogProduct(
                    productId: productId,
                    storeId: value.StoreId,
                    xCloudTitleId: value.XCloudTitleId,
                    xboxTitleId: value.XboxTitleId,
                    productTitle: value.ProductTitle,
                    publisherName: value.PublisherName,
                    developerName: value.DeveloperName,
                    originalReleaseDate: value.OriginalReleaseDate,
                    productDescriptionShort: value.ProductDescriptionShort,
                    imageTile: value.Image_Tile,
                    imagePoster: value.Image_Poster,
                    imageHero: value.Image_Hero,
                    screenshots: value.Screenshots,
                    trailers: value.Trailers,
                    attributes: value.Attributes,
                    localizedProperties: value.LocalizedProperties
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case Products
        }

        private struct CatalogProductValue: Decodable, Sendable {
            let ProductId: String?
            let StoreId: String?
            let XCloudTitleId: String?
            let XboxTitleId: String?
            let ProductTitle: String?
            let PublisherName: String?
            let DeveloperName: String?
            let OriginalReleaseDate: String?
            let ProductDescriptionShort: String?
            let Image_Tile: CatalogProduct.CatalogImage?
            let Image_Poster: CatalogProduct.CatalogImage?
            let Image_Hero: CatalogProduct.CatalogImage?
            let Screenshots: [CatalogProduct.CatalogImage]?
            let Trailers: [CatalogProduct.CatalogTrailer]?
            let Attributes: [CatalogProduct.CatalogAttribute]?
            let LocalizedProperties: [CatalogProduct.Localized]?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                ProductId = try container.decodeIfPresent(String.self, forKey: .ProductId)
                StoreId = try container.decodeIfPresent(String.self, forKey: .StoreId)
                XCloudTitleId = try container.decodeIfPresent(String.self, forKey: .XCloudTitleId)
                XboxTitleId = try container.decodeIfPresent(String.self, forKey: .XboxTitleId)
                ProductTitle = try container.decodeIfPresent(String.self, forKey: .ProductTitle)
                PublisherName = try container.decodeIfPresent(String.self, forKey: .PublisherName)
                DeveloperName = try container.decodeIfPresent(String.self, forKey: .DeveloperName)
                OriginalReleaseDate = try container.decodeIfPresent(String.self, forKey: .OriginalReleaseDate)
                ProductDescriptionShort = try container.decodeIfPresent(String.self, forKey: .ProductDescriptionShort)
                Image_Tile = try container.decodeIfPresent(CatalogProduct.CatalogImage.self, forKey: .Image_Tile)
                Image_Poster = try container.decodeIfPresent(CatalogProduct.CatalogImage.self, forKey: .Image_Poster)
                Image_Hero = try container.decodeIfPresent(CatalogProduct.CatalogImage.self, forKey: .Image_Hero)
                Screenshots = try container.decodeIfPresent([CatalogProduct.CatalogImage].self, forKey: .Screenshots)
                Trailers = try container.decodeIfPresent([CatalogProduct.CatalogTrailer].self, forKey: .Trailers)
                Attributes = try container.decodeIfPresent([CatalogProduct.CatalogAttribute].self, forKey: .Attributes)
                LocalizedProperties = CatalogProduct.decodeLocalizedProperties(from: container)
            }

            private enum CodingKeys: String, CodingKey {
                case ProductId
                case StoreId
                case XCloudTitleId
                case XboxTitleId
                case ProductTitle
                case PublisherName
                case DeveloperName
                case OriginalReleaseDate
                case ProductDescriptionShort
                case Image_Tile
                case Image_Poster
                case Image_Hero
                case Screenshots
                case Trailers
                case Attributes
                case LocalizedProperties
            }
        }
    }

    /// Raw catalog product DTO returned by the Game Pass hydration service.
    public struct CatalogProduct: Decodable, Sendable {
        public let ProductId: String
        public let StoreId: String?
        public let XCloudTitleId: String?
        public let XboxTitleId: String?
        public let ProductTitle: String?
        public let PublisherName: String?
        public let DeveloperName: String?
        public let OriginalReleaseDate: String?
        public let ProductDescriptionShort: String?
        public let Image_Tile: CatalogImage?
        public let Image_Poster: CatalogImage?
        public let Image_Hero: CatalogImage?
        public let Screenshots: [CatalogImage]?
        public let Trailers: [CatalogTrailer]?
        public let Attributes: [CatalogAttribute]?
        public let LocalizedProperties: [Localized]?

        init(
            productId: String,
            storeId: String? = nil,
            xCloudTitleId: String? = nil,
            xboxTitleId: String? = nil,
            productTitle: String? = nil,
            publisherName: String? = nil,
            developerName: String? = nil,
            originalReleaseDate: String? = nil,
            productDescriptionShort: String? = nil,
            imageTile: CatalogImage? = nil,
            imagePoster: CatalogImage? = nil,
            imageHero: CatalogImage? = nil,
            screenshots: [CatalogImage]? = nil,
            trailers: [CatalogTrailer]? = nil,
            attributes: [CatalogAttribute]? = nil,
            localizedProperties: [Localized]? = nil
        ) {
            self.ProductId = productId
            self.StoreId = storeId
            self.XCloudTitleId = xCloudTitleId
            self.XboxTitleId = xboxTitleId
            self.ProductTitle = productTitle
            self.PublisherName = publisherName
            self.DeveloperName = developerName
            self.OriginalReleaseDate = originalReleaseDate
            self.ProductDescriptionShort = productDescriptionShort
            self.Image_Tile = imageTile
            self.Image_Poster = imagePoster
            self.Image_Hero = imageHero
            self.Screenshots = screenshots
            self.Trailers = trailers
            self.Attributes = attributes
            self.LocalizedProperties = localizedProperties
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let productId = try container.decodeIfPresent(String.self, forKey: .ProductId)
                ?? (try container.decodeIfPresent(String.self, forKey: .StoreId))
            guard let productId else {
                throw DecodingError.keyNotFound(
                    CodingKeys.ProductId,
                    .init(codingPath: decoder.codingPath, debugDescription: "Missing ProductId/StoreId")
                )
            }
            ProductId = productId
            StoreId = try container.decodeIfPresent(String.self, forKey: .StoreId)
            XCloudTitleId = try container.decodeIfPresent(String.self, forKey: .XCloudTitleId)
            XboxTitleId = try container.decodeIfPresent(String.self, forKey: .XboxTitleId)
            ProductTitle = try container.decodeIfPresent(String.self, forKey: .ProductTitle)
            PublisherName = try container.decodeIfPresent(String.self, forKey: .PublisherName)
            DeveloperName = try container.decodeIfPresent(String.self, forKey: .DeveloperName)
            OriginalReleaseDate = try container.decodeIfPresent(String.self, forKey: .OriginalReleaseDate)
            ProductDescriptionShort = try container.decodeIfPresent(String.self, forKey: .ProductDescriptionShort)
            Image_Tile = try container.decodeIfPresent(CatalogImage.self, forKey: .Image_Tile)
            Image_Poster = try container.decodeIfPresent(CatalogImage.self, forKey: .Image_Poster)
            Image_Hero = try container.decodeIfPresent(CatalogImage.self, forKey: .Image_Hero)
            Screenshots = try container.decodeIfPresent([CatalogImage].self, forKey: .Screenshots)
            Trailers = try container.decodeIfPresent([CatalogTrailer].self, forKey: .Trailers)
            Attributes = try container.decodeIfPresent([CatalogAttribute].self, forKey: .Attributes)
            LocalizedProperties = Self.decodeLocalizedProperties(from: container)
        }

        private enum CodingKeys: String, CodingKey {
            case ProductId
            case StoreId
            case XCloudTitleId
            case XboxTitleId
            case ProductTitle
            case PublisherName
            case DeveloperName
            case OriginalReleaseDate
            case ProductDescriptionShort
            case Image_Tile
            case Image_Poster
            case Image_Hero
            case Screenshots
            case Trailers
            case Attributes
            case LocalizedProperties
        }

        /// Catalog image DTO that tolerates the endpoint's inconsistent URL key casing.
        public struct CatalogImage: Decodable, Sendable {
            public let URL: String?
            public let Width: Int?
            public let Height: Int?

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                URL = try container.decodeIfPresent(String.self, forKey: .URL)
                    ?? (try container.decodeIfPresent(String.self, forKey: .Url))
                    ?? (try container.decodeIfPresent(String.self, forKey: .Uri))
                Width = try container.decodeIfPresent(Int.self, forKey: .Width)
                Height = try container.decodeIfPresent(Int.self, forKey: .Height)
            }

            private enum CodingKeys: String, CodingKey {
                case URL
                case Url
                case Uri
                case Width
                case Height
            }
        }

        /// Small product label DTO used for capabilities, genres, and similar catalog tags.
        public struct CatalogAttribute: Decodable, Sendable {
            public let Name: String?
            public let LocalizedName: String?

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                Name = try container.decodeIfPresent(String.self, forKey: .Name)
                    ?? (try container.decodeIfPresent(String.self, forKey: .name))
                LocalizedName = try container.decodeIfPresent(String.self, forKey: .LocalizedName)
                    ?? (try container.decodeIfPresent(String.self, forKey: .localizedName))
            }

            private enum CodingKeys: String, CodingKey {
                case Name
                case LocalizedName
                case name
                case localizedName
            }
        }

        /// Trailer DTO including preview artwork and stream-format URLs when present.
        public struct CatalogTrailer: Decodable, Sendable {
            public let Caption: String?
            public let PreviewImageURL: String?
            public let FormatURL: Format?

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                Caption = try container.decodeIfPresent(String.self, forKey: .Caption)
                    ?? (try container.decodeIfPresent(String.self, forKey: .Title))
                PreviewImageURL = try container.decodeIfPresent(String.self, forKey: .PreviewImageURL)
                    ?? (try container.decodeIfPresent(String.self, forKey: .ThumbnailURL))
                FormatURL = try container.decodeIfPresent(Format.self, forKey: .FormatURL)
            }

            private enum CodingKeys: String, CodingKey {
                case Caption
                case Title
                case PreviewImageURL
                case ThumbnailURL
                case FormatURL
            }

            /// Stream-format URLs nested under a trailer entry.
            public struct Format: Decodable, Sendable {
                public let Hls: String?
                public let Dash: String?
                public let Url: String?

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    Hls = try container.decodeIfPresent(String.self, forKey: .Hls)
                        ?? (try container.decodeIfPresent(String.self, forKey: .HLS))
                    Dash = try container.decodeIfPresent(String.self, forKey: .Dash)
                        ?? (try container.decodeIfPresent(String.self, forKey: .DASH))
                    Url = try container.decodeIfPresent(String.self, forKey: .Url)
                        ?? (try container.decodeIfPresent(String.self, forKey: .URL))
                }

                private enum CodingKeys: String, CodingKey {
                    case Hls
                    case HLS
                    case Dash
                    case DASH
                    case Url
                    case URL
                }
            }
        }

        /// Localized override block used when the catalog ships title text or imagery per locale.
        public struct Localized: Decodable, Sendable {
            public let ProductTitle: String?
            public let ShortDescription: String?
            public let Images: [Image]?

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                ProductTitle = try container.decodeIfPresent(String.self, forKey: .ProductTitle)
                    ?? (try container.decodeIfPresent(String.self, forKey: .Title))
                ShortDescription = try container.decodeIfPresent(String.self, forKey: .ShortDescription)
                    ?? (try container.decodeIfPresent(String.self, forKey: .Description))
                if let imagesArray = try? container.decode([Image].self, forKey: .Images) {
                    Images = imagesArray
                } else if let imagesDict = try? container.decode([String: Image].self, forKey: .Images) {
                    Images = Array(imagesDict.values)
                } else {
                    Images = nil
                }
            }

            private enum CodingKeys: String, CodingKey {
                case ProductTitle
                case Title
                case ShortDescription
                case Description
                case Images
            }
        }

        /// Image entry nested inside a localized-properties block.
        public struct Image: Decodable, Sendable {
            public let Uri: String?
            public let ImagePurpose: String?

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                Uri = try container.decodeIfPresent(String.self, forKey: .Uri)
                    ?? (try container.decodeIfPresent(String.self, forKey: .URL))
                    ?? (try container.decodeIfPresent(String.self, forKey: .Url))
                ImagePurpose = try container.decodeIfPresent(String.self, forKey: .ImagePurpose)
                    ?? (try container.decodeIfPresent(String.self, forKey: .Purpose))
            }

            private enum CodingKeys: String, CodingKey {
                case Uri
                case URL
                case Url
                case ImagePurpose
                case Purpose
            }
        }

        fileprivate static func decodeLocalizedProperties<K: CodingKey>(
            from container: KeyedDecodingContainer<K>
        ) -> [Localized]? {
            guard let key = K(stringValue: "LocalizedProperties") else { return nil }
            if let localizedArray = try? container.decode([Localized].self, forKey: key) {
                return localizedArray
            }
            if let localizedSingle = try? container.decode(Localized.self, forKey: key) {
                return [localizedSingle]
            }
            if let localizedDict = try? container.decode([String: Localized].self, forKey: key) {
                return Array(localizedDict.values)
            }
            return nil
        }
    }

    private let baseURL = URL(string: "https://catalog.gamepass.com")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Hydrates product IDs in batches and returns the merged catalog DTO list for those products.
    public func hydrateProducts(
        productIds: [String],
        market: String = "US",
        language: String = "en-US",
        hydration: String = "RemoteHighSapphire0",
        authorizationToken: String? = nil
    ) async throws -> [CatalogProduct] {
        let uniqueIds = Array(Set(productIds)).sorted()
        guard !uniqueIds.isEmpty else { return [] }

        var merged: [CatalogProduct] = []
        for batch in uniqueIds.chunked(into: 100) {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("v3/products"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "market", value: market),
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "hydration", value: hydration)
            ]

            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("0.0", forHTTPHeaderField: "ms-cv")
            request.setValue("Xbox Cloud Gaming Web", forHTTPHeaderField: "calling-app-name")
            request.setValue("21.0.0", forHTTPHeaderField: "calling-app-version")
            if let authorizationToken, !authorizationToken.isEmpty {
                request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(HydrateRequest(Products: batch))

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, body)
            }

            do {
                merged.append(contentsOf: try JSONDecoder().decode(HydrateResponse.self, from: data).Products)
            } catch {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                throw APIError.decodingError("\(error.localizedDescription) | body: \(String(body.prefix(512)))")
            }
        }
        return merged
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<next]))
            index = next
        }
        return result
    }
}
