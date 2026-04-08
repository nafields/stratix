// XboxAchievementsClientTests.swift
// Exercises xbox achievements client behavior.
//

import Foundation
import Testing
@testable import XCloudAPI

@Suite(.serialized)
struct XboxAchievementsClientTests {
    @Test func titleSnapshot_parsesHistoryAndAchievementPayloads() async throws {
        let session = makeStubSession()

        AchievementsURLProtocolStub.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "XBL3.0 x=12345;web-token")
            #expect(request.url?.host == "achievements.xboxlive.com")
            if request.url?.path == "/users/xuid(2814637611111111)/history/titles" {
                let body = #"""
                {
                  "titles": [
                    {
                      "titleId": "1234",
                      "titleName": "Halo Test",
                      "totalAchievements": 10,
                      "unlockedAchievements": 4,
                      "totalGamerscore": 1000,
                      "unlockedGamerscore": 400
                    }
                  ]
                }
                """#
                return (.ok(url: request.url!), Data(body.utf8))
            }

            let body = #"""
            {
              "achievements": [
                {
                  "id": "ach-1",
                  "name": "First Unlock",
                  "description": "First achievement",
                  "progressState": "Achieved",
                  "timeUnlocked": "2026-03-01T01:02:03Z",
                  "gamerscore": 50
                },
                {
                  "id": "ach-2",
                  "name": "Second Unlock",
                  "description": "Second achievement",
                  "percentComplete": 40,
                  "gamerscore": 30
                }
              ]
            }
            """#
            return (.ok(url: request.url!), Data(body.utf8))
        }

        let client = XboxAchievementsClient(
            credentials: XboxWebCredentials(token: "web-token", uhs: "12345"),
            xuid: "2814637611111111",
            session: session
        )
        let snapshot = try #require(await client.getTitleAchievementSnapshot(titleId: "1234", maxRecentItems: 2))

        #expect(snapshot.summary.titleId == "1234")
        #expect(snapshot.summary.unlockedAchievements == 4)
        #expect(snapshot.summary.totalAchievements == 10)
        #expect(snapshot.summary.unlockedGamerscore == 400)
        #expect(snapshot.achievements.count == 2)
        #expect(snapshot.achievements.first?.id == "ach-1")
        #expect(snapshot.achievements.first?.unlocked == true)
    }

    @Test func titleSnapshot_buildsSummaryFromAchievementsWhenHistoryMissing() async throws {
        let session = makeStubSession()

        AchievementsURLProtocolStub.handler = { request in
            if request.url?.path == "/users/xuid(2814637611111111)/history/titles" {
                return (.ok(url: request.url!), Data(#"{"titles":[]}"#.utf8))
            }
            let body = #"""
            {
              "results": [
                { "id": "a1", "name": "Alpha", "percentComplete": 100, "gamerscore": 20 },
                { "id": "a2", "name": "Beta", "percentComplete": 25, "gamerscore": 10 }
              ]
            }
            """#
            return (.ok(url: request.url!), Data(body.utf8))
        }

        let client = XboxAchievementsClient(
            credentials: XboxWebCredentials(token: "web-token", uhs: "12345"),
            xuid: "2814637611111111",
            session: session
        )
        let snapshot = try #require(await client.getTitleAchievementSnapshot(titleId: "fallback-title", maxRecentItems: 2))

        #expect(snapshot.summary.titleId == "fallback-title")
        #expect(snapshot.summary.totalAchievements == 2)
        #expect(snapshot.summary.unlockedAchievements == 1)
        #expect(snapshot.summary.totalGamerscore == 30)
        #expect(snapshot.summary.unlockedGamerscore == 20)
    }

    @Test func titleHistory_usesXuidFromTokenWhenExplicitXuidMissing() async throws {
        let session = makeStubSession()
        let token = "eyJhbGciOiJub25lIn0.eyJ4aWQiOiIyODE0NjM3NjExMTExMTExIn0."

        AchievementsURLProtocolStub.handler = { request in
            #expect(request.url?.path == "/users/xuid(2814637611111111)/history/titles")
            return (.ok(url: request.url!), Data(#"{"titles":[]}"#.utf8))
        }

        let client = XboxAchievementsClient(
            credentials: XboxWebCredentials(token: token, uhs: "12345"),
            session: session
        )
        let titles = try await client.getTitleHistory()
        #expect(titles.isEmpty)
    }

    @Test func titleSnapshot_resolvesNumericQueryTitleIdFromHistoryWhenInputIsSlug() async throws {
        let session = makeStubSession()
        var sawAchievementsCall = false

        AchievementsURLProtocolStub.handler = { request in
            if request.url?.path == "/users/xuid(2814637611111111)/history/titles" {
                let body = #"""
                {
                  "titles": [
                    {
                      "titleId": "1234567890",
                      "titleName": "TUNIC",
                      "totalAchievements": 10,
                      "unlockedAchievements": 4
                    }
                  ]
                }
                """#
                return (.ok(url: request.url!), Data(body.utf8))
            }

            sawAchievementsCall = true
            #expect(request.url?.path == "/users/xuid(2814637611111111)/achievements")
            let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first(where: { $0.name == "titleId" })?.value == "1234567890")
            return (.ok(url: request.url!), Data(#"{"achievements":[]}"#.utf8))
        }

        let client = XboxAchievementsClient(
            credentials: XboxWebCredentials(token: "web-token", uhs: "12345"),
            xuid: "2814637611111111",
            session: session
        )
        let snapshot = try #require(await client.getTitleAchievementSnapshot(titleId: "TUNIC", maxRecentItems: 2))
        #expect(snapshot.summary.titleId == "1234567890")
        #expect(sawAchievementsCall)
    }

    @Test func titleSnapshot_nonNumericInputFallsBackToHistorySummaryOnBadRequest() async throws {
        let session = makeStubSession()

        AchievementsURLProtocolStub.handler = { request in
            if request.url?.path == "/users/xuid(2814637611111111)/history/titles" {
                let body = #"""
                {
                  "titles": [
                    {
                      "titleId": "99887766",
                      "titleName": "TUNIC",
                      "totalAchievements": 25,
                      "unlockedAchievements": 6
                    }
                  ]
                }
                """#
                return (.ok(url: request.url!), Data(body.utf8))
            }
            return (
                HTTPURLResponse(url: try #require(request.url), statusCode: 400, httpVersion: nil, headerFields: nil)!,
                Data(#"{"code":44,"description":"invalid query"}"#.utf8)
            )
        }

        let client = XboxAchievementsClient(
            credentials: XboxWebCredentials(token: "web-token", uhs: "12345"),
            xuid: "2814637611111111",
            session: session
        )
        let snapshot = try #require(await client.getTitleAchievementSnapshot(titleId: "TUNIC", maxRecentItems: 2))
        #expect(snapshot.summary.titleId == "99887766")
        #expect(snapshot.summary.totalAchievements == 25)
        #expect(snapshot.achievements.isEmpty)
    }

    @Test func titleSnapshot_prefersPerTitleCountsWhenHistoryCountsAreEmpty() async throws {
        let session = makeStubSession()

        AchievementsURLProtocolStub.handler = { request in
            if request.url?.path == "/users/xuid(2814637611111111)/history/titles" {
                let body = #"""
                {
                  "titles": [
                    {
                      "titleId": "1234567890",
                      "titleName": "TUNIC",
                      "progress": {
                        "totalAchievements": 0,
                        "unlockedAchievements": 0
                      }
                    }
                  ]
                }
                """#
                return (.ok(url: request.url!), Data(body.utf8))
            }

            let body = #"""
            {
              "achievements": [
                { "id": "a1", "name": "One", "progressState": "Achieved", "gamerscore": 10 },
                { "id": "a2", "name": "Two", "progressState": "NotStarted", "gamerscore": 15 },
                { "id": "a3", "name": "Three", "percentComplete": 100, "gamerscore": 25 }
              ]
            }
            """#
            return (.ok(url: request.url!), Data(body.utf8))
        }

        let client = XboxAchievementsClient(
            credentials: XboxWebCredentials(token: "web-token", uhs: "12345"),
            xuid: "2814637611111111",
            session: session
        )
        let snapshot = try #require(await client.getTitleAchievementSnapshot(titleId: "TUNIC", maxRecentItems: 3))
        #expect(snapshot.summary.totalAchievements == 3)
        #expect(snapshot.summary.unlockedAchievements == 2)
        #expect(snapshot.summary.totalGamerscore == 50)
        #expect(snapshot.summary.unlockedGamerscore == 35)
    }

    private func makeStubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AchievementsURLProtocolStub.self]
        return URLSession(configuration: config)
    }
}

private final class AchievementsURLProtocolStub: URLProtocol, @unchecked Sendable {
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
