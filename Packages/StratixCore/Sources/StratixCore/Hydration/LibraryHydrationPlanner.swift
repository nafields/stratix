// LibraryHydrationPlanner.swift
// Defines library hydration planner for the Hydration surface.
//

import Foundation
import StratixModels

protocol LibraryHydrationPlanning: Sendable {
    func hasFreshCompleteStartupSnapshot(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> Bool

    func requiresUnifiedHydration(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> Bool

    func startupRestoreDecision(for snapshot: LibrarySectionsDiskCacheSnapshot) -> LibraryHydrationPlanner.StartupRestoreDecision
    func startupRestoreDecision(for snapshot: DecodedLibrarySectionsCacheSnapshot) -> LibraryHydrationPlanner.StartupRestoreDecision
    func shouldApplyUnifiedSectionsCache(_ snapshot: LibrarySectionsDiskCacheSnapshot) -> Bool
    func shouldApplyUnifiedSectionsCache(_ snapshot: DecodedLibrarySectionsCacheSnapshot) -> Bool
    func makeStartupRestoreResult(
        payload: LibraryStartupCachePayload,
        shouldLoadProductDetails: Bool,
        shouldLoadSections: Bool,
        expectedCacheVersion: Int
    ) -> LibraryStartupRestoreResult
    func makeShellBootPlan(
        isAuthenticated: Bool,
        hasFreshCompleteStartupSnapshot: Bool
    ) -> ShellBootHydrationPlan?
    func makePostStreamPlan(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> PostStreamHydrationPlan
    func isUnifiedHydrationStale(generatedAt: Date) -> Bool
}

struct LibraryHydrationPlanner: LibraryHydrationPlanning, Sendable {
    enum StartupRestoreDecision: Equatable, Sendable {
        case applyUnifiedSnapshot
        case reject(String)
    }

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func hasFreshCompleteStartupSnapshot(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> Bool {
        guard !sections.isEmpty else { return false }
        guard homeMerchandising != nil else { return false }
        guard hasCompletedInitialHomeMerchandising else { return false }
        guard let hydratedAt = lastHydratedAt ?? cacheSavedAt else { return false }
        return !isUnifiedHydrationStale(generatedAt: hydratedAt)
    }

    func requiresUnifiedHydration(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> Bool {
        !hasFreshCompleteStartupSnapshot(
            sections: sections,
            homeMerchandising: homeMerchandising,
            hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
            lastHydratedAt: lastHydratedAt,
            cacheSavedAt: cacheSavedAt
        )
    }

    func startupRestoreDecision(for snapshot: LibrarySectionsDiskCacheSnapshot) -> StartupRestoreDecision {
        if snapshot.sections.isEmpty { return .reject("sections_empty") }
        if !snapshot.isUnifiedHomeReady { return .reject("home_not_ready") }
        if snapshot.homeMerchandising == nil { return .reject("home_missing") }
        if snapshot.siglDiscovery == nil { return .reject("discovery_missing") }
        if !metadataMatchesCurrentHydrationConfig(snapshot.metadata) { return .reject("market_or_language_mismatch") }
        if !metadataIsCompleteEnough(snapshot.metadata) { return .reject("metadata_incomplete") }
        if isUnifiedHydrationStale(generatedAt: snapshot.savedAt) { return .reject("stale") }
        return .applyUnifiedSnapshot
    }

    func startupRestoreDecision(for snapshot: DecodedLibrarySectionsCacheSnapshot) -> StartupRestoreDecision {
        if snapshot.sections.isEmpty { return .reject("sections_empty") }
        if !snapshot.isUnifiedHomeReady { return .reject("home_not_ready") }
        if snapshot.homeMerchandising == nil { return .reject("home_missing") }
        if snapshot.discovery == nil { return .reject("discovery_missing") }
        if !metadataMatchesCurrentHydrationConfig(snapshot.metadata) { return .reject("market_or_language_mismatch") }
        if !metadataIsCompleteEnough(snapshot.metadata) { return .reject("metadata_incomplete") }
        if isUnifiedHydrationStale(generatedAt: snapshot.savedAt) { return .reject("stale") }
        return .applyUnifiedSnapshot
    }

    func shouldApplyUnifiedSectionsCache(_ snapshot: LibrarySectionsDiskCacheSnapshot) -> Bool {
        startupRestoreDecision(for: snapshot) == .applyUnifiedSnapshot
    }

    func shouldApplyUnifiedSectionsCache(_ snapshot: DecodedLibrarySectionsCacheSnapshot) -> Bool {
        startupRestoreDecision(for: snapshot) == .applyUnifiedSnapshot
    }

    func makeStartupRestoreResult(
        payload: LibraryStartupCachePayload,
        shouldLoadProductDetails: Bool,
        shouldLoadSections: Bool,
        expectedCacheVersion: Int
    ) -> LibraryStartupRestoreResult {
        let productDetailsOutcome: ProductDetailsStartupRestoreOutcome?
        if shouldLoadProductDetails {
            switch payload.productDetails {
            case .snapshot(let snapshot):
                if snapshot.cacheVersion == expectedCacheVersion {
                    productDetailsOutcome = .apply(snapshot.details)
                } else {
                    productDetailsOutcome = .rejectVersionMismatch(
                        found: snapshot.cacheVersion,
                        expected: expectedCacheVersion
                    )
                }
            case .legacyUnversioned:
                productDetailsOutcome = .rejectLegacyUnversioned
            case .unavailable:
                productDetailsOutcome = .unavailable
            }
        } else {
            productDetailsOutcome = nil
        }

        let sectionsOutcome: SectionsStartupRestoreOutcome?
        if shouldLoadSections {
            if let snapshot = payload.sectionsSnapshot {
                if snapshot.cacheVersion != expectedCacheVersion {
                    sectionsOutcome = .rejectVersionMismatch(
                        found: snapshot.cacheVersion,
                        expected: expectedCacheVersion
                    )
                } else if shouldApplyUnifiedSectionsCache(snapshot) {
                    sectionsOutcome = .apply(snapshot)
                } else {
                    let rejection: String
                    switch startupRestoreDecision(for: snapshot) {
                    case .applyUnifiedSnapshot:
                        rejection = "unknown"
                    case .reject(let reason):
                        rejection = reason
                    }
                    sectionsOutcome = .rejectUnifiedSnapshot(reason: rejection, snapshot: snapshot)
                }
            } else {
                sectionsOutcome = .unavailable
            }
        } else {
            sectionsOutcome = nil
        }

        return LibraryStartupRestoreResult(
            productDetails: productDetailsOutcome,
            sections: sectionsOutcome
        )
    }

    func makeShellBootPlan(
        isAuthenticated: Bool,
        hasFreshCompleteStartupSnapshot: Bool
    ) -> ShellBootHydrationPlan? {
        guard isAuthenticated else { return nil }
        if hasFreshCompleteStartupSnapshot {
            return ShellBootHydrationPlan(
                mode: .prefetchCached,
                statusText: "Loading cached library...",
                deferInitialRoutePublication: false,
                minimumVisibleDuration: .milliseconds(150),
                decisionDescription: "fresh unified home snapshot restored"
            )
        }
        return ShellBootHydrationPlan(
            mode: .refreshNetwork,
            statusText: "Syncing your cloud library...",
            deferInitialRoutePublication: true,
            minimumVisibleDuration: .milliseconds(300),
            decisionDescription: "no fresh unified home snapshot"
        )
    }

    func makePostStreamPlan(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        hasCompletedInitialHomeMerchandising: Bool,
        lastHydratedAt: Date?,
        cacheSavedAt: Date?
    ) -> PostStreamHydrationPlan {
        guard !sections.isEmpty else {
            return PostStreamHydrationPlan(
                mode: .refreshNetwork,
                decisionDescription: "sections_missing"
            )
        }
        guard homeMerchandising != nil else {
            return PostStreamHydrationPlan(
                mode: .refreshNetwork,
                decisionDescription: "home_missing"
            )
        }
        guard hasCompletedInitialHomeMerchandising else {
            return PostStreamHydrationPlan(
                mode: .refreshNetwork,
                decisionDescription: "home_incomplete"
            )
        }
        guard let hydratedAt = lastHydratedAt ?? cacheSavedAt else {
            return PostStreamHydrationPlan(
                mode: .refreshNetwork,
                decisionDescription: "snapshot_age_unknown"
            )
        }
        guard !isUnifiedHydrationStale(generatedAt: hydratedAt) else {
            return PostStreamHydrationPlan(
                mode: .refreshNetwork,
                decisionDescription: "snapshot_stale"
            )
        }
        return PostStreamHydrationPlan(
            mode: .refreshMRUDelta,
            decisionDescription: "fresh_unified_snapshot"
        )
    }

    func isUnifiedHydrationStale(generatedAt: Date) -> Bool {
        return max(0, now().timeIntervalSince(generatedAt)) >= StratixConstants.Hydration.effectiveCombinedHomeTTL
    }

    func preferredStartupSnapshot(
        currentBest: LibrarySectionsDiskCacheSnapshot?,
        candidate: LibrarySectionsDiskCacheSnapshot
    ) -> LibrarySectionsDiskCacheSnapshot {
        guard let currentBest else { return candidate }
        return completenessScore(candidate.metadata) >= completenessScore(currentBest.metadata)
            ? candidate
            : currentBest
    }

    private func metadataMatchesCurrentHydrationConfig(_ metadata: LibraryHydrationMetadata) -> Bool {
        let config = LibraryHydrationConfig()
        let marketMatches = metadata.market == "unknown" || metadata.market == config.market
        let languageMatches = metadata.language == "unknown" || metadata.language == config.language
        return marketMatches && languageMatches
    }

    private func metadataIsCompleteEnough(_ metadata: LibraryHydrationMetadata) -> Bool {
        guard !metadata.completenessBySectionID.isEmpty else { return true }
        return !metadata.completenessBySectionID.values.contains(false)
    }

    private func completenessScore(_ metadata: LibraryHydrationMetadata) -> Int {
        metadata.completenessBySectionID.values.reduce(into: 0) { score, isComplete in
            if isComplete {
                score += 1
            }
        }
    }
}
