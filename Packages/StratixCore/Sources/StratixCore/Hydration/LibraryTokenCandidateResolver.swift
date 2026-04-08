// LibraryTokenCandidateResolver.swift
// Defines library token candidate resolver for the Hydration surface.
//

import Foundation
import XCloudAPI

@MainActor
enum LibraryTokenCandidateResolver {
    static func makeCandidates(
        tokens: StreamTokens
    ) -> [(label: String, token: String, preferredHost: String?)] {
        var candidates: [(label: String, token: String, preferredHost: String?)] = []
        let config = LibraryHydrationConfig()
        if let xcloudToken = tokens.xcloudToken, !xcloudToken.isEmpty, xcloudToken != tokens.xhomeToken {
            candidates.append(("xCloud", xcloudToken, tokens.xcloudHost))
        }
        if let f2pToken = tokens.xcloudF2PToken, !f2pToken.isEmpty,
           f2pToken != tokens.xcloudToken, f2pToken != tokens.xhomeToken {
            candidates.append(("xCloudF2P", f2pToken, config.canonicalF2PLibraryHost))
        }
        if !tokens.xhomeToken.isEmpty {
            candidates.append(("xHome", tokens.xhomeToken, tokens.xhomeHost))
        }
        return candidates
    }
}
