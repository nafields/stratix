// LibraryHostResolver.swift
// Defines library host resolver for the Hydration surface.
//

import Foundation
import XCloudAPI

@MainActor
enum LibraryHostResolver {
    static func resolve(
        tokens: StreamTokens,
        gsToken: String,
        preferredHost: String? = nil,
        logInfo: (String) -> Void,
        logWarning: (String) -> Void,
        formatError: (Error) -> String,
        isHTTPResponseError: (Error) -> Bool
    ) async throws -> String {
        for host in makeCandidates(tokens: tokens, preferredHost: preferredHost) {
            do {
                logInfo("Cloud library probing host: \(host)")
                let client = XCloudAPIClient(baseHost: host, gsToken: gsToken)
                _ = try await client.getCloudTitles()
                logInfo("Cloud library probe succeeded: \(host)")
                return host
            } catch {
                if isHTTPResponseError(error) {
                    logWarning("Cloud library probe reached valid host with HTTP error (\(formatError(error))): \(host)")
                    return host
                }
                logWarning("Cloud library probe failed (\(host)): \(formatError(error))")
            }
        }

        throw AuthError.invalidResponse("Could not resolve a working xCloud library host.")
    }

    static func makeCandidates(tokens: StreamTokens, preferredHost: String?) -> [String] {
        var candidates: [String] = []

        func appendUnique(_ rawHost: String?) {
            guard let rawHost else { return }
            var normalized = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !normalized.isEmpty else { return }
            if !normalized.hasPrefix("http://"), !normalized.hasPrefix("https://") {
                normalized = "https://\(normalized)"
            }
            if !candidates.contains(normalized) {
                candidates.append(normalized)
            }
        }

        appendUnique(preferredHost)
        let config = LibraryHydrationConfig()
        appendUnique(tokens.xcloudHost)
        appendUnique(tokens.xcloudF2PHost)
        appendUnique(config.defaultLibraryHost)
        for host in config.fallbackHosts {
            appendUnique(host)
        }

        return candidates
    }
}
