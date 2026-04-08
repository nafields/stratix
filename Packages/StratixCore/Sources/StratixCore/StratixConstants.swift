// StratixConstants.swift
// Defines stratix constants.
//

import Foundation

/// Central namespace for shared timing, cache, and hydration constants.
public enum StratixConstants {

    public enum Timing {
        /// Nanoseconds to wait before treating a focus change as "settled".
        public static let focusSettleDebounceNanoseconds: UInt64 = 60_000_000

        /// Nanoseconds to wait before recording a focus-target event on simple screens.
        public static let focusTargetDebounceNanoseconds: UInt64 = 90_000_000

        /// Nanoseconds to wait before triggering a visible-tile prefetch sweep.
        public static let visiblePrefetchDebounceNanoseconds: UInt64 = 140_000_000

        /// Nanoseconds before the shell-boot hydration fallback fires and the
        /// app proceeds to the main shell even if hydration hasn't completed.
        public static let shellBootFallbackTimeoutNanoseconds: UInt64 = 20_000_000_000

        /// Nanoseconds between achievement-refresh polls while a stream is active.
        public static let achievementRefreshIntervalNanoseconds: UInt64 = 120_000_000_000
    }

    public enum Cache {
        /// Maximum number of entries kept in the detail-state hot cache.
        public static let detailHotCacheCapacity = 5
    }

    public enum Hydration {
        /// Production TTL for the combined library + home merchandising snapshot.
        public static let combinedHomeTTL: TimeInterval = 6 * 60 * 60

        /// Short TTL used when explicitly enabled for local testing.
        public static let combinedHomeTestingTTL: TimeInterval = 60

        /// Maximum number of visible Home artwork requests to block on before first render.
        public static let visibleHomeArtworkPrefetchLimit = 14

        /// Number of carousel / recently-added titles to treat as immediately visible.
        public static let visibleCarouselItemCount = 5

        /// Number of rail items to treat as immediately visible for each top Home row.
        public static let visibleHomeRowItemCount = 4

        /// Number of top Home rows to block on for visible artwork.
        public static let visibleHomeRowCount = 3

        public static var effectiveCombinedHomeTTL: TimeInterval {
            if let overrideSeconds = ProcessInfo.processInfo.environment["STRATIX_LIBRARY_HYDRATION_TTL_SECONDS"],
               let parsedSeconds = TimeInterval(overrideSeconds),
               parsedSeconds > 0 {
                return parsedSeconds
            }
            return combinedHomeTTL
        }
    }
}
