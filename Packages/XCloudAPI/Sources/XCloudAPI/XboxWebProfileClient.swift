// XboxWebProfileClient.swift
// Defines the xbox web profile client.
//

import Foundation

/// Xbox web-token pair required by profile, presence, social, and achievements endpoints.
public struct XboxWebCredentials: Sendable {
    public let token: String
    public let uhs: String

    public init(token: String, uhs: String) {
        self.token = token
        self.uhs = uhs
    }
}

/// App-facing projection of the signed-in user's Xbox profile card.
public struct XboxCurrentUserProfile: Sendable, Equatable {
    public let xuid: String?
    public let gamertag: String?
    public let gameDisplayName: String?
    public let gameDisplayPicRaw: URL?
    public let gamerscore: String?

    public init(
        xuid: String? = nil,
        gamertag: String?,
        gameDisplayName: String?,
        gameDisplayPicRaw: URL?,
        gamerscore: String?
    ) {
        self.xuid = xuid
        self.gamertag = gamertag
        self.gameDisplayName = gameDisplayName
        self.gameDisplayPicRaw = gameDisplayPicRaw
        self.gamerscore = gamerscore
    }

    /// Prefers the console-facing display name before falling back to the raw gamertag.
    public var preferredScreenName: String? {
        nonEmpty(gameDisplayName) ?? nonEmpty(gamertag)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private struct XboxProfileSettingsResponse: Decodable {
    let profileUsers: [XboxProfileUser]
}

private struct XboxProfileBatchRequest: Encodable {
    let settings: [String]
    let userIds: [String]
}

private struct XboxProfileUser: Decodable {
    let id: String?
    let settings: [XboxProfileSetting]
}

private struct XboxProfileSetting: Decodable {
    let id: String
    let value: String
}

/// Fetches Xbox profile settings for the current user or an explicit batch of user IDs.
public actor XboxWebProfileClient {
    private let session: URLSession
    private let credentials: XboxWebCredentials

    public init(credentials: XboxWebCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    /// Loads the signed-in user's own profile card from the profile service.
    public func getCurrentUserProfile() async throws -> XboxCurrentUserProfile {
        let profiles = try await getProfiles(forUsersPath: "/users/me/profile/settings", userIds: nil)
        return profiles.first ?? XboxCurrentUserProfile(
            xuid: nil,
            gamertag: nil,
            gameDisplayName: nil,
            gameDisplayPicRaw: nil,
            gamerscore: nil
        )
    }

    /// Batch-loads profile cards for a set of XUIDs through the profile batch endpoint.
    public func getProfiles(userIds: [String]) async throws -> [XboxCurrentUserProfile] {
        let unique = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [] }

        guard let url = URL(string: "https://profile.xboxlive.com/users/batch/profile/settings") else {
            throw APIError.notReady
        }
        let body = try JSONEncoder().encode(
            XboxProfileBatchRequest(
                settings: ["GameDisplayName", "GameDisplayPicRaw", "Gamerscore", "Gamertag"],
                userIds: unique
            )
        )
        let request = XboxWebRequestSupport.makeRequest(
            url: url,
            method: "POST",
            contractVersion: "3",
            credentials: credentials,
            contentType: "application/json",
            body: body
        )

        return try await decodeResponse(for: request).profileUsers.map(Self.mapProfileUser)
    }

    private func getProfiles(
        forUsersPath path: String,
        userIds _: [String]?
    ) async throws -> [XboxCurrentUserProfile] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "profile.xboxlive.com"
        components.path = path
        components.queryItems = [
            .init(name: "settings", value: "GameDisplayName,GameDisplayPicRaw,Gamerscore,Gamertag")
        ]
        guard let url = components.url else {
            throw APIError.notReady
        }

        let request = XboxWebRequestSupport.makeRequest(
            url: url,
            method: "GET",
            contractVersion: "2",
            credentials: credentials
        )
        return try await decodeResponse(for: request).profileUsers.map(Self.mapProfileUser)
    }

    private static func mapProfileUser(_ user: XboxProfileUser) -> XboxCurrentUserProfile {
        var gamertag: String?
        var gameDisplayName: String?
        var gameDisplayPicRaw: URL?
        var gamerscore: String?

        for setting in user.settings {
            switch setting.id {
            case "Gamertag":
                gamertag = setting.value
            case "GameDisplayName":
                gameDisplayName = setting.value
            case "GameDisplayPicRaw":
                gameDisplayPicRaw = URL(string: setting.value)
            case "Gamerscore":
                gamerscore = setting.value
            default:
                continue
            }
        }

        return XboxCurrentUserProfile(
            xuid: user.id,
            gamertag: gamertag,
            gameDisplayName: gameDisplayName,
            gameDisplayPicRaw: gameDisplayPicRaw,
            gamerscore: gamerscore
        )
    }

    private func decodeResponse(for request: URLRequest) async throws -> XboxProfileSettingsResponse {
        let responseData = try await XboxWebRequestSupport.performData(session: session, request: request)
        do {
            return try JSONDecoder().decode(XboxProfileSettingsResponse.self, from: responseData)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
