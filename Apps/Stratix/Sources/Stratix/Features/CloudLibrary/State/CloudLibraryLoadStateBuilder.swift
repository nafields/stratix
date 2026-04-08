// CloudLibraryLoadStateBuilder.swift
// Defines cloud library load state builder for the Features / CloudLibrary surface.
//

import Foundation
import StratixCore

struct CloudLibraryLoadStateBuilder {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func makeLoadState(from snapshot: CloudLibraryStateSnapshot) -> CloudLibraryLoadState {
        let ageSeconds = cacheAgeSeconds(cacheSavedAt: snapshot.cacheSavedAt)

        if let error = snapshot.lastError, !error.isEmpty {
            return snapshot.hasCachedContent
                ? .degradedCached(error: error, ageSeconds: ageSeconds)
                : .failedNoCache(error: error)
        }

        if snapshot.isLoading && snapshot.hasCachedContent {
            return .refreshingFromCache(ageSeconds: ageSeconds)
        }

        if snapshot.hasCachedContent && snapshot.hasRecoveredLiveHomeMerchandisingThisSession {
            return .liveFresh
        }

        if snapshot.hasCachedContent {
            return .restoredCached(ageSeconds: ageSeconds)
        }

        return .notLoaded
    }

    func makeLoadState(from state: LibraryState) -> CloudLibraryLoadState {
        makeLoadState(from: CloudLibraryStateSnapshot(state: state))
    }

    private func cacheAgeSeconds(cacheSavedAt: Date?) -> Int {
        guard let cacheSavedAt else { return 0 }
        return max(0, Int(now().timeIntervalSince(cacheSavedAt)))
    }

    private static func formattedAge(_ ageSeconds: Int) -> String {
        switch ageSeconds {
        case 0..<60:
            return "\(ageSeconds)s ago"
        case 60..<3600:
            return "\(max(1, ageSeconds / 60))m ago"
        default:
            return "\(max(1, ageSeconds / 3600))h ago"
        }
    }
}
