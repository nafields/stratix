// XboxWebPresenceClient.swift
// Defines the xbox web presence client.
//

import Foundation

/// Title-level presence entry reported on one Xbox device session.
public struct XboxPresenceTitle: Sendable, Equatable {
    public let id: String?
    public let name: String?
    public let placement: String?
    public let state: String?

    public init(id: String?, name: String?, placement: String?, state: String?) {
        self.id = id
        self.name = name
        self.placement = placement
        self.state = state
    }
}

/// Presence grouping for one device type, including any active or suspended titles on it.
public struct XboxPresenceDevice: Sendable, Equatable {
    public let type: String?
    public let titles: [XboxPresenceTitle]

    public init(type: String?, titles: [XboxPresenceTitle]) {
        self.type = type
        self.titles = titles
    }
}

/// Last-seen fallback when the user is offline and only historical presence is available.
public struct XboxPresenceLastSeen: Sendable, Equatable {
    public let titleId: String?
    public let titleName: String?
    public let deviceType: String?
    public let timestamp: Date?

    public init(titleId: String?, titleName: String?, deviceType: String?, timestamp: Date?) {
        self.titleId = titleId
        self.titleName = titleName
        self.deviceType = deviceType
        self.timestamp = timestamp
    }
}

/// Current-user presence projection consumed by profile and social surfaces.
public struct XboxCurrentUserPresence: Sendable, Equatable {
    public let xuid: String?
    public let state: String
    public let devices: [XboxPresenceDevice]
    public let lastSeen: XboxPresenceLastSeen?
    public let fetchedAt: Date

    public init(
        xuid: String?,
        state: String,
        devices: [XboxPresenceDevice],
        lastSeen: XboxPresenceLastSeen?,
        fetchedAt: Date = Date()
    ) {
        self.xuid = xuid
        self.state = state
        self.devices = devices
        self.lastSeen = lastSeen
        self.fetchedAt = fetchedAt
    }

    /// Treats any presence state containing "online" as an online session.
    public var isOnline: Bool {
        state.localizedCaseInsensitiveContains("online")
    }

    /// Returns the first active title name reported across the user's live devices.
    public var activeTitleName: String? {
        devices.lazy
            .compactMap { device in
                device.titles.first {
                    ($0.state ?? "").localizedCaseInsensitiveContains("active")
                }?.name
            }
            .first
    }
}

private struct XboxSetPresenceRequest: Encodable {
    let state: String
    let titles: [XboxSetPresenceTitleRequest]?
}

private struct XboxSetPresenceTitleRequest: Encodable {
    let id: String
    let state: String
    let placement: String?
}

/// Reads and updates the signed-in user's Xbox presence state through the web presence API.
public actor XboxWebPresenceClient {
    private let session: URLSession
    private let credentials: XboxWebCredentials

    public init(credentials: XboxWebCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    /// Fetches the current user's presence payload and normalizes it into app-facing structs.
    public func getCurrentUserPresence(level: String = "all") async throws -> XboxCurrentUserPresence {
        let url = try currentUserPresenceURL(level: level)
        let request = XboxWebRequestSupport.makeRequest(
            url: url,
            method: "GET",
            contractVersion: "3",
            credentials: credentials
        )
        let data = try await XboxWebRequestSupport.performData(session: session, request: request)

        do {
            return try parseCurrentUserPresence(data: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.decodingError("\(error.localizedDescription) | body: \(String(body.prefix(512)))")
        }
    }

    /// Pushes a lightweight online/offline presence update, optionally with active titles attached.
    public func setCurrentUserPresence(
        isOnline: Bool,
        titles: [(id: String, state: String, placement: String?)] = []
    ) async throws {
        guard let url = URL(string: "https://userpresence.xboxlive.com/users/me") else {
            throw APIError.notReady
        }

        let presenceTitles = titles.isEmpty ? nil : titles.map {
            XboxSetPresenceTitleRequest(id: $0.id, state: $0.state, placement: $0.placement)
        }
        let body = XboxSetPresenceRequest(
            state: isOnline ? "Online" : "Offline",
            titles: presenceTitles
        )

        let encodedBody = try JSONEncoder().encode(body)
        let request = XboxWebRequestSupport.makeRequest(
            url: url,
            method: "POST",
            contractVersion: "3",
            credentials: credentials,
            contentType: "application/json",
            body: encodedBody
        )
        _ = try await XboxWebRequestSupport.performData(session: session, request: request)
    }

    private func parseCurrentUserPresence(data: Data) throws -> XboxCurrentUserPresence {
        let json = try JSONSerialization.jsonObject(with: data)
        let rootObject = try Self.presenceRootObject(from: json)

        return XboxCurrentUserPresence(
            xuid: Self.string(rootObject["xuid"]),
            state: Self.string(rootObject["state"]) ?? "Unknown",
            devices: Self.array(rootObject["devices"]).compactMap(Self.dictionary).map(Self.parseDevice),
            lastSeen: Self.dictionary(rootObject["lastSeen"]).map(Self.parseLastSeen),
            fetchedAt: Date()
        )
    }

    private func currentUserPresenceURL(level: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "userpresence.xboxlive.com"
        components.path = "/users/me"
        components.queryItems = [
            .init(name: "level", value: level)
        ]
        guard let url = components.url else { throw APIError.notReady }
        return url
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func presenceRootObject(from json: Any) throws -> [String: Any] {
        if let rootObject = json as? [String: Any] {
            if rootObject["state"] != nil || rootObject["xuid"] != nil || rootObject["devices"] != nil {
                return rootObject
            }
            return dictionary(rootObject["presence"])
                ?? firstDictionary(in: array(rootObject["users"]))
                ?? firstDictionary(in: array(rootObject["people"]))
                ?? rootObject
        }

        if let firstPresence = firstDictionary(in: array(json)) {
            return firstPresence
        }

        throw APIError.decodingError("Presence root is not an object")
    }

    private static func parseDevice(_ dictionary: [String: Any]) -> XboxPresenceDevice {
        XboxPresenceDevice(
            type: string(dictionary["type"]),
            titles: array(dictionary["titles"]).compactMap(Self.dictionary).map(Self.parseTitle)
        )
    }

    private static func parseTitle(_ dictionary: [String: Any]) -> XboxPresenceTitle {
        XboxPresenceTitle(
            id: string(dictionary["id"]),
            name: string(dictionary["name"]),
            placement: string(dictionary["placement"]),
            state: string(dictionary["state"])
        )
    }

    private static func parseLastSeen(_ dictionary: [String: Any]) -> XboxPresenceLastSeen {
        XboxPresenceLastSeen(
            titleId: string(dictionary["titleId"]),
            titleName: string(dictionary["titleName"]),
            deviceType: string(dictionary["deviceType"]),
            timestamp: parseDate(dictionary["timestamp"])
        )
    }

    private static func firstDictionary(in values: [Any]) -> [String: Any]? {
        values.lazy.compactMap(dictionary).first
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let raw = string(value), !raw.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: raw) { return date }

        if let seconds = TimeInterval(raw) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}
