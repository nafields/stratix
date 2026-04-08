// CloudLibraryLoadState.swift
// Defines the cloud library load state.
//

import Foundation

enum CloudLibraryLoadState: Equatable, Sendable, Hashable {
    case notLoaded
    case restoredCached(ageSeconds: Int)
    case refreshingFromCache(ageSeconds: Int)
    case liveFresh
    case degradedCached(error: String, ageSeconds: Int)
    case failedNoCache(error: String)

    var diagnosticsValue: String {
        switch self {
        case .notLoaded:
            return "notLoaded"
        case .restoredCached(let ageSeconds):
            return "restoredCached(\(ageSeconds))"
        case .refreshingFromCache(let ageSeconds):
            return "refreshingFromCache(\(ageSeconds))"
        case .liveFresh:
            return "liveFresh"
        case .degradedCached(_, let ageSeconds):
            return "degradedCached(\(ageSeconds))"
        case .failedNoCache:
            return "failedNoCache"
        }
    }

    var hasCompletedInitialLoad: Bool {
        switch self {
        case .notLoaded:
            return false
        case .restoredCached, .refreshingFromCache, .liveFresh, .degradedCached, .failedNoCache:
            return true
        }
    }

    var isLiveFresh: Bool {
        self == .liveFresh
    }
}
