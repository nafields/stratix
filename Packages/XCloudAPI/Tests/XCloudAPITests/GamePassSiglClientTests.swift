// GamePassSiglClientTests.swift
// Exercises game pass sigl client behavior.
//

import Foundation
import Testing
@testable import XCloudAPI

@Suite("GamePassSiglClient")
struct GamePassSiglClientTests {
    @Test func nextDataExtraction_andDiscovery_decodeSiglAliases() throws {
        let html = #"""
        <html>
        <head></head>
        <body>
          <script id="__NEXT_DATA__" type="application/json">
          {
            "props": {
              "pageProps": {
                "channels": [
                  { "siglId": "6a589fa0-d493-472b-8e20-3813699d7056", "label": "Popular" },
                  { "channelId": "06323672-b8c8-43cc-b0de-32d5a9834749", "name": "Recently Added" }
                ]
              }
            }
          }
          </script>
        </body>
        </html>
        """#

        let extracted = try #require(GamePassSiglClient.extractNextDataJSON(from: html))
        let entries = GamePassSiglClient.discoverAliasesFromNextData(extracted)
        #expect(entries.count == 2)
        #expect(entries[0].alias == "popular")
        #expect(entries[0].siglID == "6a589fa0-d493-472b-8e20-3813699d7056")
        #expect(entries[0].source == .nextData)
        #expect(entries[1].alias == "recently-added")
        #expect(entries[1].siglID == "06323672-b8c8-43cc-b0de-32d5a9834749")
    }

    @Test func clientJSFallback_prefersDiscoveredUUID_whenPresent() {
        let discoveredPopular = "11111111-2222-3333-4444-555555555555"
        let js = "const popular='\(discoveredPopular)'; const free='FreeToPlay';"
        let entries = GamePassSiglClient.discoverAliasesFromClientJS(js)
        let byAlias = Dictionary(entries.map { ($0.alias, $0) }, uniquingKeysWith: { first, _ in first })

        #expect(byAlias["popular"]?.siglID == discoveredPopular)
        #expect(byAlias["free-to-play"]?.siglID == "FreeToPlay")
        #expect(byAlias["action-adventure"]?.siglID == "f913b4be-6ca1-44ac-946a-1a481602595c")
    }

    @Test func parseSiglProducts_decodesArrayAndDictionaryShapes() throws {
        let arrayPayload = #"""
        [
          { "id": "9A" },
          { "id": "9B" },
          { "id": "9A" }
        ]
        """#
        let fromArray = try GamePassSiglClient.parseSiglProductIDs(from: Data(arrayPayload.utf8))
        #expect(fromArray == ["9A", "9B"])

        let dictPayload = #"""
        {
          "products": [
            { "id": "FreeToPlay" },
            { "id": "9C" }
          ]
        }
        """#
        let fromDict = try GamePassSiglClient.parseSiglProductIDs(from: Data(dictPayload.utf8))
        #expect(fromDict == ["FreeToPlay", "9C"])
    }

    @Test func discoverClientJSURLs_prefersPlayXBoxAssets() throws {
        let pageURL = try #require(URL(string: "https://www.xbox.com/en-US/play"))
        let html = #"""
        <script src="/assets/a.js"></script>
        <script src="https://assets.play.xbox.com/playxbox/client.bundle.js"></script>
        <script src="https://cdn.example.com/other.js"></script>
        """#
        let urls = GamePassSiglClient.discoverClientJSURLs(from: html, pageURL: pageURL)
        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://assets.play.xbox.com/playxbox/client.bundle.js")
    }
}
