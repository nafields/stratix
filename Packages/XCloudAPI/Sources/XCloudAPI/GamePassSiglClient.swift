// GamePassSiglClient.swift
// Defines the game pass sigl client.
//

import Foundation

/// One discovered SIGL alias mapping gathered from the play page, client script, or fallback table.
public struct GamePassSiglDiscoveryEntry: Sendable, Equatable {
    public let alias: String
    public let label: String
    public let siglID: String
    public let source: Source

    /// Identifies which discovery path produced the alias mapping.
    public enum Source: String, Sendable {
        case nextData
        case clientJS
        case fallback
    }

    public init(alias: String, label: String, siglID: String, source: Source) {
        self.alias = alias
        self.label = label
        self.siglID = siglID
        self.source = source
    }
}

/// Result of SIGL alias discovery, preserving both the ordered entries and a lookup view.
public struct GamePassSiglDiscoveryResult: Sendable, Equatable {
    public let entries: [GamePassSiglDiscoveryEntry]

    public init(entries: [GamePassSiglDiscoveryEntry]) {
        self.entries = entries
    }

    /// Convenience lookup keyed by normalized alias for later catalog fetches.
    public var aliasToSiglID: [String: String] {
        Dictionary(entries.map { ($0.alias, $0.siglID) }, uniquingKeysWith: { existing, _ in existing })
    }
}

/// Fetches and discovers Game Pass SIGL channel IDs used to enumerate themed catalog shelves.
public final class GamePassSiglClient: Sendable {
    public static let defaultPlayURL = URL(string: "https://www.xbox.com/en-US/play")!

    public static let fallbackAliasToSiglID: [String: String] = [
        "all-games": "1bf84c2b-0643-4591-893f-d9edb703f692",
        "buy-and-stream": "e78d9a61-5ef4-43af-b400-edba1250b18e",
        "recently-added": "06323672-b8c8-43cc-b0de-32d5a9834749",
        "leaving-soon": "31ff2361-2772-4622-849b-f4f1abb4ad1b",
        "popular": "6a589fa0-d493-472b-8e20-3813699d7056",
        "action-adventure": "f913b4be-6ca1-44ac-946a-1a481602595c",
        "family-friendly": "c51f789c-cc6c-4f31-b9ed-0cc97b04d455",
        "fighters": "d34a6cdb-e678-4193-89a1-0dc86360cfa7",
        "indies": "36f22fa5-3d2e-4b1d-818f-4308ab0ffa2e",
        "rpgs": "455e5b52-9454-41ad-a00a-9f2d5e9d6549",
        "shooters": "725d2704-860d-4bdf-a827-ac93dc729a96",
        "simulations": "cd6e5cbb-9f14-4d0d-bb38-a4b22b10f403",
        "strategies": "67aaebe2-6215-4258-aeab-2c837bc7e34c",
        "ea-play": "e8e34eab-2bdb-4680-8fb8-28ce7a507bce",
        "mouse-and-keyboard": "3aa7a358-f15b-476b-af7e-134a250c08a0",
        "touch": "9c86f07a-f3e8-45ad-82a0-a1f759597059",
        "free-to-play": "FreeToPlay"
    ]

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Discovers the current alias-to-SIGL mapping by merging Next.js data, client scripts, and fallbacks.
    public func discoverAliases(playURL: URL = defaultPlayURL) async throws -> GamePassSiglDiscoveryResult {
        let html = try await fetchText(url: playURL)
        var mergedEntries: [GamePassSiglDiscoveryEntry] = []
        var seenAliases = Set<String>()

        if let nextDataJSON = Self.extractNextDataJSON(from: html) {
            let nextEntries = Self.discoverAliasesFromNextData(nextDataJSON)
            appendUnique(nextEntries, seenAliases: &seenAliases, to: &mergedEntries)
        }

        let clientJSURLs = Self.discoverClientJSURLs(from: html, pageURL: playURL)
        for jsURL in clientJSURLs {
            guard let jsText = try? await fetchText(url: jsURL) else { continue }
            let jsEntries = Self.discoverAliasesFromClientJS(jsText)
            appendUnique(jsEntries, seenAliases: &seenAliases, to: &mergedEntries)
        }

        for (alias, siglID) in Self.fallbackAliasToSiglID where seenAliases.insert(alias).inserted {
            mergedEntries.append(Self.makeDiscoveryEntry(alias: alias, siglID: siglID, source: .fallback))
        }

        return GamePassSiglDiscoveryResult(entries: mergedEntries)
    }

    /// Loads the product IDs listed under one SIGL shelf for the requested market and language.
    public func fetchProductIDs(
        siglID: String,
        market: String = "US",
        language: String = "en-US"
    ) async throws -> [String] {
        var components = URLComponents(string: "https://catalog.gamepass.com/sigls/v2")!
        components.queryItems = [
            URLQueryItem(name: "id", value: siglID),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "market", value: market)
        ]
        let data = try await fetchData(url: components.url!)
        return try Self.parseSiglProductIDs(from: data)
    }

    func fetchData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json, text/html, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw APIError.httpError(statusCode, String(body.prefix(512)))
        }
        return data
    }

    func fetchText(url: URL) async throws -> String {
        let data = try await fetchData(url: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func makeDiscoveryEntry(
        alias: String,
        siglID: String,
        source: GamePassSiglDiscoveryEntry.Source
    ) -> GamePassSiglDiscoveryEntry {
        GamePassSiglDiscoveryEntry(
            alias: alias,
            label: displayLabel(for: alias),
            siglID: siglID,
            source: source
        )
    }

    private func appendUnique(
        _ entries: [GamePassSiglDiscoveryEntry],
        seenAliases: inout Set<String>,
        to mergedEntries: inout [GamePassSiglDiscoveryEntry]
    ) {
        for entry in entries where seenAliases.insert(entry.alias).inserted {
            mergedEntries.append(entry)
        }
    }
}

extension GamePassSiglClient {
    static func normalizeAlias(_ label: String) -> String {
        var normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        normalized = normalized.replacingOccurrences(of: "&", with: "and")
        normalized = normalized.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "-", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized
    }

    static func displayLabel(for alias: String) -> String {
        alias
            .split(separator: "-")
            .map { token in
                let lowercased = token.lowercased()
                switch lowercased {
                case "rpgs":
                    return "RPGs"
                case "ea":
                    return "EA"
                default:
                    return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
                }
            }
            .joined(separator: " ")
    }

    static func extractNextDataJSON(from html: String) -> String? {
        let pattern = #"<script[^>]+id=["']__NEXT_DATA__["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func discoverAliasesFromNextData(_ jsonString: String) -> [GamePassSiglDiscoveryEntry] {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var entries: [GamePassSiglDiscoveryEntry] = []
        var seenAliases = Set<String>()
        walkJSON(object) { dict in
            let siglID = (dict["siglId"] as? String) ?? (dict["channelId"] as? String)
            let label = (dict["label"] as? String) ?? (dict["name"] as? String) ?? (dict["title"] as? String)
            guard let siglID, !siglID.isEmpty, let label, !label.isEmpty else { return }
            let alias = normalizeAlias(label)
            guard !alias.isEmpty, seenAliases.insert(alias).inserted else { return }
            entries.append(
                GamePassSiglDiscoveryEntry(
                    alias: alias,
                    label: label,
                    siglID: siglID,
                    source: .nextData
                )
            )
        }
        return entries
    }

    static func discoverClientJSURLs(from html: String, pageURL: URL) -> [URL] {
        let pattern = #"<script[^>]+src=["']([^"']+\.js(?:\?[^"']*)?)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        let urls = matches.compactMap { match -> URL? in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return URL(string: String(html[range]), relativeTo: pageURL)?.absoluteURL
        }

        let uniqueURLs = Array(Set(urls)).sorted { lhs, rhs in
            lhs.absoluteString < rhs.absoluteString
        }
        let preferredPlayXboxURLs = uniqueURLs.filter {
            $0.absoluteString.contains("assets.play.xbox.com/playxbox/")
        }
        return preferredPlayXboxURLs.isEmpty ? uniqueURLs : preferredPlayXboxURLs
    }

    static func discoverAliasesFromClientJS(_ jsText: String) -> [GamePassSiglDiscoveryEntry] {
        var entries: [GamePassSiglDiscoveryEntry] = []
        var seenAliases = Set<String>()

        for (alias, fallbackSiglID) in fallbackAliasToSiglID {
            guard seenAliases.insert(alias).inserted else { continue }
            let aliasPattern = NSRegularExpression.escapedPattern(for: alias)
            let patterns = [
                "\(aliasPattern).{0,300}?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})",
                "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}).{0,300}?\(aliasPattern)"
            ]

            let discoveredSiglID = patterns.compactMap { pattern in
                firstMatch(in: jsText, pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators], captureGroup: 1)
            }.first

            let siglID = discoveredSiglID ?? fallbackSiglID
            entries.append(makeDiscoveryEntry(alias: alias, siglID: siglID, source: .clientJS))
        }

        return entries
    }

    static func parseSiglProductIDs(from data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        var output: [String] = []
        var seen = Set<String>()

        func appendIfNeeded(_ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            guard seen.insert(value).inserted else { return }
            output.append(value)
        }

        if let list = object as? [[String: Any]] {
            for item in list {
                appendIfNeeded(item["id"] as? String)
            }
            return output
        }

        if let dict = object as? [String: Any] {
            let candidates = (dict["products"] as? [[String: Any]])
                ?? (dict["items"] as? [[String: Any]])
                ?? (dict["data"] as? [[String: Any]])
                ?? []
            for item in candidates {
                appendIfNeeded(item["id"] as? String)
            }
            return output
        }

        return output
    }

    private static func walkJSON(_ value: Any, visitor: ([String: Any]) -> Void) {
        if let dict = value as? [String: Any] {
            visitor(dict)
            for child in dict.values {
                walkJSON(child, visitor: visitor)
            }
            return
        }
        if let array = value as? [Any] {
            for item in array {
                walkJSON(item, visitor: visitor)
            }
        }
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options,
        captureGroup: Int
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: captureGroup), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
