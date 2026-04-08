// XboxAchievementsClient.swift
// Defines the xbox achievements client.
//

import Foundation
import StratixModels

/// Fetches title history, per-title achievements, and summary snapshots from Xbox achievements APIs.
public actor XboxAchievementsClient {
    private let session: URLSession
    private let credentials: XboxWebCredentials
    private let explicitXuid: String?

    public init(
        credentials: XboxWebCredentials,
        xuid: String? = nil,
        session: URLSession = .shared
    ) {
        self.credentials = credentials
        self.explicitXuid = Self.normalizedXuid(xuid)
        self.session = session
    }

    /// Loads the user's achievement history across titles, ordered by most recent activity.
    public func getTitleHistory(maxItems: Int = 200) async throws -> [TitleAchievementSummary] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "achievements.xboxlive.com"
        components.path = "/users/\(resolvedUserPathComponent())/history/titles"
        components.queryItems = [URLQueryItem(name: "maxItems", value: String(max(1, maxItems)))]
        guard let url = components.url else {
            throw APIError.notReady
        }
        let request = XboxWebRequestSupport.makeRequest(
            url: url,
            method: "GET",
            contractVersion: "2",
            credentials: credentials
        )
        let data = try await XboxWebRequestSupport.performData(session: session, request: request)
        return try Self.parseTitleHistory(data: data)
    }

    /// Loads the achievements list for one title using the normalized title ID query path.
    public func getTitleAchievements(titleId: String, maxItems: Int = 50) async throws -> [AchievementProgressItem] {
        let trimmedTitleID = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitleID.isEmpty else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "achievements.xboxlive.com"
        components.path = "/users/\(resolvedUserPathComponent())/achievements"
        components.queryItems = [
            URLQueryItem(name: "titleId", value: trimmedTitleID),
            URLQueryItem(name: "maxItems", value: String(max(1, maxItems)))
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
        let data = try await XboxWebRequestSupport.performData(session: session, request: request)
        return try Self.parseAchievements(data: data)
    }

    /// Combines title history and per-title achievements into one snapshot for detail hydration.
    public func getTitleAchievementSnapshot(
        titleId: String,
        maxRecentItems: Int = 8
    ) async throws -> TitleAchievementSnapshot? {
        let trimmedTitleID = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitleID.isEmpty else { return nil }

        var history = (try? await getTitleHistory(maxItems: 200)) ?? []
        var historySummary = matchingHistorySummary(for: trimmedTitleID, in: history)
        if historySummary == nil, !trimmedTitleID.allSatisfy(\.isNumber) {
            // Large libraries can push a title outside a small history window.
            let extendedHistory = (try? await getTitleHistory(maxItems: 2000)) ?? []
            if extendedHistory.count > history.count {
                history = extendedHistory
                historySummary = matchingHistorySummary(for: trimmedTitleID, in: history)
            }
        }
        let queryTitleID = resolvedAchievementQueryTitleID(input: trimmedTitleID, summary: historySummary)
        if !shouldFetchPerTitleAchievements(for: queryTitleID, hasHistorySummary: historySummary != nil) {
            guard let historySummary else { return nil }
            return TitleAchievementSnapshot(
                titleId: trimmedTitleID,
                fetchedAt: Date(),
                summary: historySummary,
                achievements: []
            )
        }

        let achievements: [AchievementProgressItem]
        do {
            achievements = try await getTitleAchievements(titleId: queryTitleID, maxItems: max(1, maxRecentItems * 4))
        } catch {
            if case let APIError.httpError(code, _) = error, code == 400 {
                if let historySummary {
                    return TitleAchievementSnapshot(
                        titleId: trimmedTitleID,
                        fetchedAt: Date(),
                        summary: historySummary,
                        achievements: []
                    )
                }
                return nil
            }
            if let historySummary {
                return TitleAchievementSnapshot(
                    titleId: trimmedTitleID,
                    fetchedAt: Date(),
                    summary: historySummary,
                    achievements: []
                )
            }
            throw error
        }

        guard historySummary != nil || !achievements.isEmpty else { return nil }
        let summary = Self.mergedSummary(
            historySummary: historySummary,
            queryTitleId: queryTitleID,
            fallbackTitleId: trimmedTitleID,
            achievements: achievements
        )
        let recent = Array(achievements.prefix(max(1, maxRecentItems)))
        return TitleAchievementSnapshot(
            titleId: trimmedTitleID,
            fetchedAt: Date(),
            summary: summary,
            achievements: recent
        )
    }

    private func matchingHistorySummary(
        for requestedTitle: String,
        in history: [TitleAchievementSummary]
    ) -> TitleAchievementSummary? {
        let requested = normalizedComparisonKey(requestedTitle)
        guard !requested.isEmpty else { return nil }
        return history.first { summary in
            let idKey = normalizedComparisonKey(summary.titleId)
            if idKey == requested { return true }
            let nameKey = normalizedComparisonKey(summary.titleName)
            return !nameKey.isEmpty && nameKey == requested
        }
    }

    private func resolvedAchievementQueryTitleID(
        input: String,
        summary: TitleAchievementSummary?
    ) -> String {
        if let summaryTitleID = summary?.titleId.trimmingCharacters(in: .whitespacesAndNewlines),
           !summaryTitleID.isEmpty {
            return summaryTitleID
        }
        return input
    }

    private func shouldFetchPerTitleAchievements(for queryTitleID: String, hasHistorySummary: Bool) -> Bool {
        let trimmed = queryTitleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.allSatisfy(\.isNumber) {
            return true
        }
        // Keep a best-effort query path when history is unavailable.
        return !hasHistorySummary
    }

    /// Normalizes identifiers and names into a comparison key shared by history/title matching.
    private func normalizedComparisonKey(_ raw: String?) -> String {
        guard let raw else { return "" }
        let folded = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func parseTitleHistory(data: Data) throws -> [TitleAchievementSummary] {
        let json = try JSONSerialization.jsonObject(with: data)
        let dictionaries = titleHistoryDictionaries(from: json)

        var seen = Set<String>()
        var results: [TitleAchievementSummary] = []
        for dict in dictionaries {
            let titleDictionary = firstDictionary(keys: ["title", "Title", "associatedTitle", "AssociatedTitle"], in: dict)
            let progressDictionary = firstDictionary(
                keys: ["progress", "Progress", "progression", "Progression", "stats", "Stats"],
                in: dict
            )
            guard let titleId = firstString(
                keys: ["titleId", "TitleId", "xboxTitleId", "XboxTitleId", "id", "Id", "serviceConfigId", "scid"],
                in: dict
            ) ?? titleDictionary.flatMap({
                firstString(
                    keys: ["titleId", "TitleId", "xboxTitleId", "XboxTitleId", "id", "Id", "serviceConfigId", "scid"],
                    in: $0
                )
            }) else { continue }

            let normalizedID = titleId.lowercased()
            guard seen.insert(normalizedID).inserted else { continue }

            let totalAchievements = firstInt(
                keys: [
                    "totalAchievements",
                    "TotalAchievements",
                    "achievementCount",
                    "AchievementCount",
                    "possibleAchievements",
                    "PossibleAchievements"
                ],
                in: dict
            ) ?? progressDictionary.flatMap {
                firstInt(
                    keys: [
                        "totalAchievements",
                        "TotalAchievements",
                        "achievementCount",
                        "AchievementCount",
                        "possibleAchievements",
                        "PossibleAchievements"
                    ],
                    in: $0
                )
            } ?? 0
            let unlockedAchievements = firstInt(
                keys: [
                    "unlockedAchievements",
                    "UnlockedAchievements",
                    "currentAchievements",
                    "CurrentAchievements",
                    "achievementsUnlocked",
                    "AchievementsUnlocked"
                ],
                in: dict
            ) ?? progressDictionary.flatMap {
                firstInt(
                    keys: [
                        "unlockedAchievements",
                        "UnlockedAchievements",
                        "currentAchievements",
                        "CurrentAchievements",
                        "achievementsUnlocked",
                        "AchievementsUnlocked"
                    ],
                    in: $0
                )
            } ?? 0
            let totalGamerscore = firstInt(
                keys: ["totalGamerscore", "TotalGamerscore", "possibleGamerscore", "PossibleGamerscore"],
                in: dict
            ) ?? progressDictionary.flatMap {
                firstInt(keys: ["totalGamerscore", "TotalGamerscore", "possibleGamerscore", "PossibleGamerscore"], in: $0)
            }
            let unlockedGamerscore = firstInt(
                keys: ["unlockedGamerscore", "UnlockedGamerscore", "currentGamerscore", "CurrentGamerscore"],
                in: dict
            ) ?? progressDictionary.flatMap {
                firstInt(keys: ["unlockedGamerscore", "UnlockedGamerscore", "currentGamerscore", "CurrentGamerscore"], in: $0)
            }
            let titleName = firstString(keys: ["titleName", "TitleName", "name", "Name", "title", "Title"], in: dict)
                ?? titleDictionary.flatMap({ firstString(keys: ["titleName", "TitleName", "name", "Name", "title", "Title"], in: $0) })
            let lastUpdated = parseDate(firstValue(keys: ["lastUpdated", "LastUpdated", "lastPlayed", "LastPlayed"], in: dict)) ?? Date()

            let normalizedTotal = max(totalAchievements, unlockedAchievements)
            let normalizedUnlocked = min(normalizedTotal, max(0, unlockedAchievements))

            results.append(
                TitleAchievementSummary(
                    titleId: titleId,
                    titleName: titleName,
                    totalAchievements: normalizedTotal,
                    unlockedAchievements: normalizedUnlocked,
                    totalGamerscore: totalGamerscore,
                    unlockedGamerscore: unlockedGamerscore,
                    lastUpdated: lastUpdated
                )
            )
        }

        return results
            .sorted { lhs, rhs in
                lhs.lastUpdated > rhs.lastUpdated
            }
    }

    private static func parseAchievements(data: Data) throws -> [AchievementProgressItem] {
        let json = try JSONSerialization.jsonObject(with: data)
        let dictionaries = achievementDictionaries(from: json)

        var seen = Set<String>()
        var items: [AchievementProgressItem] = []

        for dict in dictionaries {
            let id = firstString(
                keys: ["id", "Id", "achievementId", "AchievementId", "name", "Name", "title", "Title"],
                in: dict
            ) ?? UUID().uuidString
            let normalizedID = id.lowercased()
            guard seen.insert(normalizedID).inserted else { continue }

            let name = firstString(keys: ["name", "Name", "title", "Title"], in: dict) ?? "Achievement"
            let detail = firstString(
                keys: ["description", "Description", "lockedDescription", "LockedDescription"],
                in: dict
            )
            let unlockedAt = parseDate(
                firstValue(keys: ["timeUnlocked", "TimeUnlocked", "unlockedOn", "UnlockedOn", "unlockTime"], in: dict)
            )
            let progressState = firstString(keys: ["progressState", "ProgressState", "state", "State"], in: dict)?.lowercased()
            let percentComplete = firstInt(
                keys: ["percentComplete", "PercentComplete", "progressPercentage", "ProgressPercentage"],
                in: dict
            )
            let unlocked = unlockedAt != nil
                || (progressState?.contains("achieved") == true)
                || (progressState?.contains("unlocked") == true)
                || (percentComplete ?? 0) >= 100
            let gamerscore = firstInt(keys: ["gamerscore", "Gamerscore", "score", "Score"], in: dict)

            items.append(
                AchievementProgressItem(
                    id: id,
                    name: name,
                    detail: detail,
                    unlocked: unlocked,
                    percentComplete: percentComplete,
                    gamerscore: gamerscore,
                    unlockedAt: unlockedAt
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.unlocked != rhs.unlocked {
                return lhs.unlocked && !rhs.unlocked
            }
            if let lhsDate = lhs.unlockedAt, let rhsDate = rhs.unlockedAt, lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            let lhsPercent = lhs.percentComplete ?? 0
            let rhsPercent = rhs.percentComplete ?? 0
            if lhsPercent != rhsPercent {
                return lhsPercent > rhsPercent
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func summaryFromAchievements(
        titleId: String,
        achievements: [AchievementProgressItem]
    ) -> TitleAchievementSummary {
        let total = achievements.count
        let unlocked = achievements.filter(\.unlocked).count
        let totalGamerscore = achievements.compactMap(\.gamerscore).reduce(0, +)
        let unlockedGamerscore = achievements.filter(\.unlocked).compactMap(\.gamerscore).reduce(0, +)
        return TitleAchievementSummary(
            titleId: titleId,
            titleName: nil,
            totalAchievements: total,
            unlockedAchievements: unlocked,
            totalGamerscore: totalGamerscore > 0 ? totalGamerscore : nil,
            unlockedGamerscore: unlockedGamerscore > 0 ? unlockedGamerscore : nil,
            lastUpdated: Date()
        )
    }

    private static func mergedSummary(
        historySummary: TitleAchievementSummary?,
        queryTitleId: String,
        fallbackTitleId: String,
        achievements: [AchievementProgressItem]
    ) -> TitleAchievementSummary {
        guard let historySummary else {
            let resolvedTitleId = queryTitleId.trimmingCharacters(in: .whitespacesAndNewlines)
            return summaryFromAchievements(
                titleId: resolvedTitleId.isEmpty ? fallbackTitleId : resolvedTitleId,
                achievements: achievements
            )
        }
        guard !achievements.isEmpty else { return historySummary }

        let computed = summaryFromAchievements(titleId: historySummary.titleId, achievements: achievements)
        let total = max(historySummary.totalAchievements, computed.totalAchievements)
        let unlocked = min(total, max(historySummary.unlockedAchievements, computed.unlockedAchievements))

        let totalGamerscore: Int? = {
            switch (historySummary.totalGamerscore, computed.totalGamerscore) {
            case let (lhs?, rhs?): return max(lhs, rhs)
            case let (lhs?, nil): return lhs
            case let (nil, rhs?): return rhs
            default: return nil
            }
        }()
        let unlockedGamerscore: Int? = {
            switch (historySummary.unlockedGamerscore, computed.unlockedGamerscore) {
            case let (lhs?, rhs?): return max(lhs, rhs)
            case let (lhs?, nil): return lhs
            case let (nil, rhs?): return rhs
            default: return nil
            }
        }()
        let normalizedUnlockedGamerscore: Int? = {
            guard let unlockedGamerscore else { return nil }
            if let totalGamerscore {
                return min(totalGamerscore, unlockedGamerscore)
            }
            return unlockedGamerscore
        }()

        return TitleAchievementSummary(
            titleId: historySummary.titleId,
            titleName: historySummary.titleName,
            totalAchievements: total,
            unlockedAchievements: unlocked,
            totalGamerscore: totalGamerscore,
            unlockedGamerscore: normalizedUnlockedGamerscore,
            lastUpdated: historySummary.lastUpdated
        )
    }

    private static func titleHistoryDictionaries(from json: Any) -> [[String: Any]] {
        if let dict = json as? [String: Any] {
            for key in ["titles", "items", "results", "value", "history"] {
                if let entries = dict[key] as? [Any] {
                    let mapped = entries.compactMap { $0 as? [String: Any] }
                    if !mapped.isEmpty { return mapped }
                }
            }
            if let entries = dict["titles"] as? [[String: Any]], !entries.isEmpty {
                return entries
            }
        }
        if let array = json as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return allDictionaries(in: json)
    }

    private static func achievementDictionaries(from json: Any) -> [[String: Any]] {
        if let dict = json as? [String: Any] {
            for key in ["achievements", "items", "results", "value"] {
                if let entries = dict[key] as? [Any] {
                    let mapped = entries.compactMap { $0 as? [String: Any] }
                    if !mapped.isEmpty { return mapped }
                }
            }
        }
        if let array = json as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return allDictionaries(in: json)
    }

    private func resolvedUserPathComponent() -> String {
        if let explicitXuid {
            return "xuid(\(explicitXuid))"
        }
        if let tokenXuid = Self.xuidFromJWT(credentials.token) {
            return "xuid(\(tokenXuid))"
        }
        return "me"
    }

    private static func normalizedXuid(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("xuid("), trimmed.hasSuffix(")") {
            trimmed = String(trimmed.dropFirst(5).dropLast())
        }
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty, digits.count == trimmed.count else { return nil }
        return digits
    }

    private static func xuidFromJWT(_ token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payloadSegment = String(segments[1])
        guard let payloadData = base64URLDecode(payloadSegment),
              let json = try? JSONSerialization.jsonObject(with: payloadData) else {
            return nil
        }
        return extractXuid(from: json).flatMap(normalizedXuid)
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = base64.count % 4
        if pad != 0 {
            base64.append(String(repeating: "=", count: 4 - pad))
        }
        return Data(base64Encoded: base64)
    }

    private static func extractXuid(from json: Any) -> String? {
        if let dict = json as? [String: Any] {
            for key in ["xuid", "xid", "Xuid", "Xid"] {
                if let value = dict[key] as? String, !value.isEmpty {
                    return value
                }
            }
            for value in dict.values {
                if let nested = extractXuid(from: value) {
                    return nested
                }
            }
            return nil
        }
        if let array = json as? [Any] {
            for value in array {
                if let nested = extractXuid(from: value) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func firstString(keys: [String], in dict: [String: Any]) -> String? {
        for key in keys {
            if let value = firstValue(keys: [key], in: dict), let string = asTrimmedString(value) {
                return string
            }
        }
        return nil
    }

    private static func firstInt(keys: [String], in dict: [String: Any]) -> Int? {
        for key in keys {
            guard let raw = firstValue(keys: [key], in: dict) else { continue }
            if let intValue = raw as? Int {
                return intValue
            }
            if let stringValue = asTrimmedString(raw), let parsed = Int(stringValue) {
                return parsed
            }
            if let number = raw as? NSNumber {
                return number.intValue
            }
        }
        return nil
    }

    private static func firstValue(keys: [String], in dict: [String: Any]) -> Any? {
        for key in keys {
            if let exact = dict[key] {
                return exact
            }
            if let match = dict.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value {
                return match
            }
        }
        return nil
    }

    private static func firstDictionary(keys: [String], in dict: [String: Any]) -> [String: Any]? {
        for key in keys {
            if let exact = dict[key] as? [String: Any] {
                return exact
            }
            if let match = dict.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value as? [String: Any] {
                return match
            }
        }
        return nil
    }

    private static func asTrimmedString(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedString.isEmpty ? nil : trimmedString
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let raw = asTrimmedString(value) else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: raw) {
            return date
        }

        if let seconds = TimeInterval(raw) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private static func allDictionaries(in root: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func walk(_ value: Any, depth: Int) {
            guard depth <= 30 else { return }
            if let dict = value as? [String: Any] {
                result.append(dict)
                for nested in dict.values {
                    walk(nested, depth: depth + 1)
                }
                return
            }
            if let array = value as? [Any] {
                for nested in array {
                    walk(nested, depth: depth + 1)
                }
            }
        }
        walk(root, depth: 0)
        return result
    }
}
