// XboxSocialPeopleClient.swift
// Defines the xbox social people client.
//

import Foundation

/// Social person projection returned by the Xbox people endpoint.
public struct XboxSocialPerson: Sendable, Equatable, Identifiable {
    /// Uses XUID as the stable identity across friends/followers lists.
    public var id: String { xuid }

    public let xuid: String
    public let gamertag: String?
    public let displayName: String?
    public let realName: String?
    public let displayPicRaw: URL?
    public let gamerScore: String?
    public let presenceState: String?
    public let presenceText: String?
    public let isFavorite: Bool
    public let isFollowingCaller: Bool
    public let isFollowedByCaller: Bool

    public init(
        xuid: String,
        gamertag: String?,
        displayName: String?,
        realName: String?,
        displayPicRaw: URL?,
        gamerScore: String?,
        presenceState: String?,
        presenceText: String?,
        isFavorite: Bool,
        isFollowingCaller: Bool,
        isFollowedByCaller: Bool
    ) {
        self.xuid = xuid
        self.gamertag = gamertag
        self.displayName = displayName
        self.realName = realName
        self.displayPicRaw = displayPicRaw
        self.gamerScore = gamerScore
        self.presenceState = presenceState
        self.presenceText = presenceText
        self.isFavorite = isFavorite
        self.isFollowingCaller = isFollowingCaller
        self.isFollowedByCaller = isFollowedByCaller
    }

    /// Prefers the richer display name before falling back to gamertag or raw XUID.
    public var preferredName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let gamertag, !gamertag.isEmpty { return gamertag }
        return xuid
    }

    /// Treats any presence state containing "online" as an online user.
    public var isOnline: Bool {
        (presenceState ?? "").localizedCaseInsensitiveContains("online")
    }
}

/// Page response wrapper for people lists, preserving the service's reported total count.
public struct XboxSocialPeoplePage: Sendable, Equatable {
    public let totalCount: Int
    public let people: [XboxSocialPerson]

    public init(totalCount: Int, people: [XboxSocialPerson]) {
        self.totalCount = totalCount
        self.people = people
    }
}

private struct XboxSocialPeopleResponseWire: Decodable {
    let totalCount: Int?
    let people: [XboxSocialPersonWire]?
}

private struct XboxSocialPersonWire: Decodable {
    let xuid: String?
    let gamertag: String?
    let displayName: String?
    let realName: String?
    let displayPicRaw: String?
    let gamerScore: String?
    let presenceState: String?
    let presenceText: String?
    let isFavorite: Bool?
    let isFollowingCaller: Bool?
    let isFollowedByCaller: Bool?
}

/// Fetches social graph people pages from the Xbox web social service.
public actor XboxSocialPeopleClient {
    private let session: URLSession
    private let credentials: XboxWebCredentials

    public init(credentials: XboxWebCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    /// Loads one page of people for the requested owner and view mode.
    public func getPeople(
        ownerId: String = "me",
        view: String = "all",
        startIndex: Int = 0,
        maxItems: Int = 24
    ) async throws -> XboxSocialPeoplePage {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "social.xboxlive.com"
        components.path = "/users/\(ownerId)/people"
        components.queryItems = [
            .init(name: "view", value: view),
            .init(name: "startIndex", value: String(startIndex)),
            .init(name: "maxItems", value: String(maxItems))
        ]
        guard let url = components.url else { throw APIError.notReady }

        let request = XboxWebRequestSupport.makeRequest(
            url: url,
            method: "GET",
            contractVersion: "5",
            credentials: credentials
        )
        let decoded = try await decodeResponse(for: request)

        let people = (decoded.people ?? []).compactMap { wire -> XboxSocialPerson? in
            mapPerson(wire)
        }

        return XboxSocialPeoplePage(
            totalCount: decoded.totalCount ?? people.count,
            people: people
        )
    }

    private func decodeResponse(for request: URLRequest) async throws -> XboxSocialPeopleResponseWire {
        let responseData = try await XboxWebRequestSupport.performData(session: session, request: request)
        do {
            return try JSONDecoder().decode(XboxSocialPeopleResponseWire.self, from: responseData)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func mapPerson(_ wire: XboxSocialPersonWire) -> XboxSocialPerson? {
        guard let xuid = wire.xuid, !xuid.isEmpty else { return nil }
        return XboxSocialPerson(
            xuid: xuid,
            gamertag: wire.gamertag,
            displayName: wire.displayName,
            realName: wire.realName,
            displayPicRaw: wire.displayPicRaw.flatMap(URL.init(string:)),
            gamerScore: wire.gamerScore,
            presenceState: wire.presenceState,
            presenceText: wire.presenceText,
            isFavorite: wire.isFavorite ?? false,
            isFollowingCaller: wire.isFollowingCaller ?? false,
            isFollowedByCaller: wire.isFollowedByCaller ?? false
        )
    }
}
