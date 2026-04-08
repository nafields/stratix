// CloudLibraryClientTests.swift
// Exercises cloud library client behavior.
//

import Foundation
import Testing
@testable import XCloudAPI

@Suite("CloudLibraryClients", .serialized)
struct CloudLibraryClientTests {

    @Test func xcloudTitles_and_catalogHydration_requestsAndDecode() async throws {
        let session = makeStubSession()

        // xCloud titles
        URLProtocolStub.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v2/titles")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gs-token")
            let body = #"{"results":[{"titleId":"t1","details":{"productId":"p1","name":"Fallback","supportedInputTypes":["Controller"]}}]}"#
            return (.ok(url: request.url!), Data(body.utf8))
        }

        let xcloud = XCloudAPIClient(
            baseHost: "https://use.core.gssv-play-prodxhome.xboxlive.com",
            gsToken: "gs-token",
            session: session
        )
        let titles = try await xcloud.getCloudTitles()
        #expect(titles.results.count == 1)
        #expect(titles.results.first?.details?.productId == "p1")

        // xCloud MRU
        URLProtocolStub.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v2/titles/mru")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            #expect(comps?.queryItems?.first(where: { $0.name == "mr" })?.value == "7")
            let body = #"{"results":[]}"#
            return (.ok(url: request.url!), Data(body.utf8))
        }
        _ = try await xcloud.getCloudTitlesMRU(limit: 7)

        // Catalog hydration
        URLProtocolStub.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v3/products")
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            #expect(comps?.queryItems?.first(where: { $0.name == "market" })?.value == "US")
            #expect(comps?.queryItems?.first(where: { $0.name == "language" })?.value == "en-US")
            #expect(comps?.queryItems?.first(where: { $0.name == "hydration" })?.value == "RemoteHighSapphire0")
            #expect(request.value(forHTTPHeaderField: "ms-cv") == "0.0")
            #expect(request.value(forHTTPHeaderField: "calling-app-name") == "Xbox Cloud Gaming Web")
            #expect(request.value(forHTTPHeaderField: "calling-app-version") == "21.0.0")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gs-token")

            let payload = try JSONSerialization.jsonObject(with: requestBodyData(request), options: []) as? [String: Any]
            let products = payload?["Products"] as? [String]
            #expect(products == ["A", "B"])

            let body = #"""
            {
              "Products": [
                {
                  "ProductId": "A",
                  "LocalizedProperties": [
                    {
                      "ProductTitle": "Game A",
                      "ShortDescription": "Desc",
                      "Images": [{"Uri": "https://example.com/a.jpg", "ImagePurpose": "Poster"}]
                    }
                  ]
                }
              ]
            }
            """#
            return (.ok(url: request.url!), Data(body.utf8))
        }

        let catalog = GamePassCatalogClient(session: session)
        let hydrated = try await catalog.hydrateProducts(
            productIds: ["B", "A", "A"],
            market: "US",
            language: "en-US",
            hydration: "RemoteHighSapphire0",
            authorizationToken: "gs-token"
        )
        #expect(hydrated.count == 1)
        #expect(hydrated.first?.ProductId == "A")
        #expect(hydrated.first?.LocalizedProperties?.first?.ProductTitle == "Game A")
    }

    @Test func xcloudTitleDTO_decodesMissingOptionalFields() throws {
        let json = #"{"results":[{"titleId":"abc","details":{"productId":"pid"}}]}"#
        let decoded = try JSONDecoder().decode(XCloudTitlesResponse.self, from: Data(json.utf8))
        #expect(decoded.results.count == 1)
        #expect(decoded.results[0].details?.name == nil)
        #expect(decoded.results[0].details?.supportedInputTypes == nil)
    }

    @Test func catalogHydration_decodesObjectMapFlattenedFields() throws {
        let body = #"""
        {
          "Products": {
            "9TEST": {
              "StoreId": "9TEST",
              "XCloudTitleId": "abc-title",
              "ProductTitle": "Halo Test",
              "PublisherName": "Xbox Game Studios",
              "DeveloperName": "isometricorp Games Ltd.",
              "OriginalReleaseDate": "2022-03-16T00:00:00Z",
              "ProductDescriptionShort": "Short desc",
              "Image_Tile": { "URL": "//images.example/tile.jpg" },
              "Image_Poster": { "Url": "//images.example/poster.jpg" },
              "Image_Hero": { "URL": "//images.example/hero.jpg" },
              "Screenshots": [
                { "URL": "//images.example/shot1.jpg" },
                { "URL": "//images.example/shot2.jpg" }
              ],
              "Trailers": [
                {
                  "Caption": "Launch Trailer",
                  "PreviewImageURL": "//images.example/trailer-thumb.jpg",
                  "FormatURL": {
                    "Hls": "https://video.example/tunic-launch.m3u8",
                    "Dash": "https://video.example/tunic-launch.mpd"
                  }
                }
              ],
              "Attributes": [
                { "Name": "CoOp", "LocalizedName": "Co-op" }
              ],
              "LocalizedProperties": {
                "en-us": {
                  "ProductTitle": "Halo Test EN",
                  "Images": {
                    "poster": { "Url": "https://images.example/fallback.jpg", "ImagePurpose": "Poster" }
                  }
                }
              }
            }
          }
        }
        """#
        let decoded = try JSONDecoder().decode(GamePassCatalogClient.HydrateResponse.self, from: Data(body.utf8))
        #expect(decoded.Products.count == 1)
        let product = try #require(decoded.Products.first)
        #expect(product.StoreId == "9TEST")
        #expect(product.XCloudTitleId == "abc-title")
        #expect(product.ProductTitle == "Halo Test")
        #expect(product.DeveloperName == "isometricorp Games Ltd.")
        #expect(product.OriginalReleaseDate == "2022-03-16T00:00:00Z")
        #expect(product.Image_Tile?.URL == "//images.example/tile.jpg")
        #expect(product.Image_Poster?.URL == "//images.example/poster.jpg")
        #expect(product.Screenshots?.count == 2)
        #expect(product.Screenshots?.first?.URL == "//images.example/shot1.jpg")
        #expect(product.Trailers?.count == 1)
        #expect(product.Trailers?.first?.Caption == "Launch Trailer")
        #expect(product.Trailers?.first?.PreviewImageURL == "//images.example/trailer-thumb.jpg")
        #expect(product.Trailers?.first?.FormatURL?.Hls == "https://video.example/tunic-launch.m3u8")
        #expect(product.Attributes?.first?.LocalizedName == "Co-op")
        #expect((product.LocalizedProperties?.first?.ProductTitle ?? product.ProductTitle) != nil)
    }

    @Test func emeraldProductDetails_requestsXBLAndParsesRichMedia() async throws {
        let session = makeStubSession()

        URLProtocolStub.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.host == "emerald.xboxservices.com")
            #expect(request.url?.path == "/xboxcomfd/productdetails/9TEST")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.first(where: { $0.name == "enableFullDetail" })?.value == "true")
            #expect(query?.first(where: { $0.name == "locale" })?.value == "en-US")
            #expect(request.value(forHTTPHeaderField: "x-ms-api-version") == "2.0")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "XBL3.0 x=12345;web-token")

            let body = #"""
            {
              "ProductId": "9TEST",
              "PublisherName": "Finji",
              "ProductDescriptionShort": "Short fallback",
              "LocalizedProperties": [
                {
                  "Language": "en-US",
                  "ProductTitle": "TUNIC",
                  "Description": "Explore a land filled with legends.",
                  "Images": [
                    { "Uri": "https://images.example.com/shot-1.jpg", "ImagePurpose": "Screenshot" },
                    { "Uri": "https://images.example.com/hero.jpg", "ImagePurpose": "Hero" }
                  ],
                  "Trailers": [
                    {
                      "Title": "Launch Trailer",
                      "VideoUrl": "https://video.example.com/tunic-launch.m3u8",
                      "ThumbnailUrl": "https://images.example.com/trailer-thumb.jpg"
                    }
                  ]
                }
              ],
              "Attributes": [
                { "LocalizedName": "4K Ultra HD" },
                { "LocalizedName": "Single player" }
              ],
              "Properties": {
                "Genres": ["Action", "Adventure"],
                "DeveloperName": "Finji",
                "OriginalReleaseDate": "2022-03-16"
              }
            }
            """#
            return (.ok(url: request.url!), Data(body.utf8))
        }

        let client = XboxComProductDetailsClient(
            credentials: XboxWebCredentials(token: "web-token", uhs: "12345"),
            session: session
        )
        let detail = try await client.getProductDetails(productId: "9TEST", locale: "en-US")

        #expect(detail.productId == "9TEST")
        #expect(detail.title == "TUNIC")
        #expect(detail.publisherName == "Finji")
        #expect(detail.longDescription == "Explore a land filled with legends.")
        #expect(detail.developerName == "Finji")
        #expect(detail.capabilityLabels.contains("4K Ultra HD"))
        #expect(detail.genreLabels.contains("Action"))
        #expect(detail.galleryImageURLs.contains(where: { $0.absoluteString == "https://images.example.com/shot-1.jpg" }))
        #expect(detail.mediaAssets.contains(where: { $0.kind == .image && $0.url.absoluteString == "https://images.example.com/shot-1.jpg" }))
        #expect(detail.mediaAssets.contains(where: { $0.kind == .video && $0.url.absoluteString == "https://video.example.com/tunic-launch.m3u8" }))
        #expect(detail.trailers.count == 1)
        #expect(detail.trailers.first?.title == "Launch Trailer")
        #expect(detail.trailers.first?.playbackURL?.absoluteString == "https://video.example.com/tunic-launch.m3u8")
    }

    @Test func emeraldProductDetails_acceptsGenericImageAssetsAndProvidesVideoThumbnailFallback() async throws {
        let session = makeStubSession()

        URLProtocolStub.handler = { request in
            let body = #"""
            {
              "ProductId": "9GENERIC",
              "LocalizedProperties": [
                {
                  "Language": "en-US",
                  "ProductTitle": "Generic Media Game",
                  "Images": [
                    { "Uri": "https://images.example.com/media/asset-a.jpg", "ImagePurpose": "Image" },
                    { "Uri": "https://images.example.com/hero-art.jpg", "ImagePurpose": "Hero" }
                  ],
                  "Trailers": [
                    {
                      "Title": "Gameplay Trailer",
                      "VideoUrl": "https://video.example.com/generic-gameplay.m3u8"
                    }
                  ]
                }
              ]
            }
            """#
            return (.ok(url: request.url!), Data(body.utf8))
        }

        let client = XboxComProductDetailsClient(
            credentials: XboxWebCredentials(token: "web-token", uhs: "12345"),
            session: session
        )
        let detail = try await client.getProductDetails(productId: "9GENERIC", locale: "en-US")

        #expect(detail.galleryImageURLs.contains(where: { $0.absoluteString == "https://images.example.com/media/asset-a.jpg" }))
        #expect(!detail.galleryImageURLs.contains(where: { $0.absoluteString == "https://images.example.com/hero-art.jpg" }))
        let trailer = try #require(detail.trailers.first)
        #expect(trailer.playbackURL?.absoluteString == "https://video.example.com/generic-gameplay.m3u8")
        #expect(trailer.thumbnailURL?.absoluteString == "https://images.example.com/media/asset-a.jpg")
    }

    @Test func emeraldProductDetails_productSummarySchemaUsesScreenshotsAndCmsPreviewImage() async throws {
        let session = makeStubSession()

        URLProtocolStub.handler = { request in
            let body = #"""
            {
              "productSummaries": [
                {
                  "productId": "BZ6W9LRPC26W",
                  "title": "Control",
                  "images": {
                    "boxArt": {
                      "url": "https://store-images.s-microsoft.com/image/apps.boxart"
                    },
                    "poster": {
                      "url": "https://store-images.s-microsoft.com/image/apps.poster"
                    },
                    "superHeroArt": {
                      "url": "https://store-images.s-microsoft.com/image/apps.hero"
                    },
                    "screenshots": [
                      {
                        "url": "https://store-images.s-microsoft.com/image/apps.shot1"
                      },
                      {
                        "url": "https://store-images.s-microsoft.com/image/apps.shot2"
                      }
                    ]
                  },
                  "cmsVideos": [
                    {
                      "url": "https://cdn-dynmedia-1.microsoft.com/is/content/microsoftassets/control-trailer.m3u8?packagedStreaming=true",
                      "purpose": "HeroTrailer",
                      "title": "Control Accolades trailer",
                      "previewImage": {
                        "url": "https://store-images.s-microsoft.com/image/apps.hero"
                      }
                    }
                  ]
                },
                {
                  "productId": "OTHER",
                  "title": "Different Product",
                  "cmsVideos": [
                    {
                      "url": "https://video.example.com/wrong-trailer.m3u8",
                      "title": "Wrong Trailer",
                      "previewImage": { "url": "https://images.example.com/wrong-thumb.jpg" }
                    }
                  ]
                }
              ],
              "layout": {
                "BZ6W9LRPC26W": {}
              }
            }
            """#
            return (.ok(url: request.url!), Data(body.utf8))
        }

        let client = XboxComProductDetailsClient(
            credentials: XboxWebCredentials(token: "web-token", uhs: "12345"),
            session: session
        )
        let detail = try await client.getProductDetails(productId: "BZ6W9LRPC26W", locale: "en-US")

        #expect(detail.productId == "BZ6W9LRPC26W")
        #expect(detail.galleryImageURLs.count == 2)
        #expect(detail.galleryImageURLs[0].absoluteString == "https://store-images.s-microsoft.com/image/apps.shot1")
        #expect(detail.galleryImageURLs[1].absoluteString == "https://store-images.s-microsoft.com/image/apps.shot2")
        #expect(!detail.galleryImageURLs.contains(where: { $0.absoluteString.contains("boxart") }))
        #expect(!detail.galleryImageURLs.contains(where: { $0.absoluteString.contains("poster") }))
        #expect(!detail.galleryImageURLs.contains(where: { $0.absoluteString.contains("hero") }))

        #expect(detail.trailers.count == 1)
        let trailer = try #require(detail.trailers.first)
        #expect(trailer.title == "Control Accolades trailer")
        #expect(trailer.playbackURL?.absoluteString == "https://cdn-dynmedia-1.microsoft.com/is/content/microsoftassets/control-trailer.m3u8?packagedStreaming=true")
        #expect(trailer.thumbnailURL?.absoluteString == "https://store-images.s-microsoft.com/image/apps.hero")
        #expect(!detail.trailers.contains(where: { $0.playbackURL?.absoluteString == "https://video.example.com/wrong-trailer.m3u8" }))
    }

    private func makeStubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension HTTPURLResponse {
    static func ok(url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}

private func requestBodyData(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}
