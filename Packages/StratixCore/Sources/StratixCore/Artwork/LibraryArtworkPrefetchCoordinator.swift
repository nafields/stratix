// LibraryArtworkPrefetchCoordinator.swift
// Defines the library artwork prefetch coordinator for the Artwork surface.
//

import DiagnosticsKit
import Foundation
import StratixModels

@MainActor
struct LibraryArtworkPrefetchCoordinator {
    enum PrefetchResult: Sendable {
        case completed
        case noSpace
        case failed
    }

    struct Dependencies: Sendable {
        let taskRegistry: TaskRegistry
        let artworkPipeline: ArtworkPipeline
        let logger: GLogger
        let isSuspendedForStreaming: @MainActor @Sendable () -> Bool
        let isArtworkPrefetchDisabledForSession: @MainActor @Sendable () -> Bool
        let setArtworkPrefetchDisabledForSession: @MainActor @Sendable (Bool) -> Void
        let lastArtworkPrefetchStartedAt: @MainActor @Sendable () -> Date?
        let setLastArtworkPrefetchStartedAt: @MainActor @Sendable (Date?) -> Void
        let artworkPrefetchLastCompletedAtByURL: @MainActor @Sendable () -> [String: Date]
        let setArtworkPrefetchLastCompletedAtByURL: @MainActor @Sendable ([String: Date]) -> Void
        let applyAction: @MainActor @Sendable (LibraryAction) -> Void
    }

    func prefetchArtworkURLs(
        _ urls: [URL],
        reason: String,
        recentTTL: TimeInterval,
        limit: Int,
        dependencies: Dependencies
    ) async {
        guard !dependencies.isSuspendedForStreaming() else {
            dependencies.logger.info("Artwork prefetch skipped: suspended for streaming")
            return
        }
        guard !dependencies.isArtworkPrefetchDisabledForSession() else { return }
        var seen = Set<String>()
        var uniqueURLs: [URL] = []
        uniqueURLs.reserveCapacity(max(1, limit))
        for url in urls {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            uniqueURLs.append(url)
            if uniqueURLs.count >= max(1, limit) {
                break
            }
        }
        for url in uniqueURLs {
            guard !Task.isCancelled else { return }
            let prefetchResult = await prefetchArtworkURL(
                Self.artworkRequest(url: url, kind: .poster, priority: .low),
                reason: reason,
                recentTTL: recentTTL,
                dependencies: dependencies
            )
            if prefetchResult == .noSpace {
                await disableArtworkPrefetchForSession(
                    reason: "storage_full_during_prefetch",
                    dependencies: dependencies
                )
                return
            }
        }
    }

    func prefetchLibraryArtwork(
        _ sections: [CloudLibrarySection],
        dependencies: Dependencies
    ) async {
        guard !dependencies.isSuspendedForStreaming() else {
            dependencies.logger.info("Library artwork prefetch skipped: suspended for streaming")
            return
        }
        if let inFlight: Task<Void, Never> = await dependencies.taskRegistry.task(id: libraryArtworkPrefetchTaskID),
           !inFlight.isCancelled {
            dependencies.logger.info("Library artwork prefetch skipped: existing task still running")
            return
        }
        if let lastRunAt = dependencies.lastArtworkPrefetchStartedAt(),
           Date().timeIntervalSince(lastRunAt) < 30 {
            dependencies.logger.info("Library artwork prefetch skipped: recently attempted")
            return
        }
        guard !dependencies.isArtworkPrefetchDisabledForSession() else { return }
        guard !Self.isStorageConstrainedForPrefetch() else {
            await disableArtworkPrefetchForSession(
                reason: "low_available_capacity",
                dependencies: dependencies
            )
            return
        }
        dependencies.setLastArtworkPrefetchStartedAt(Date())

        let prioritizedItems: [CloudLibraryItem] = {
            let mruItems = sections.first(where: { $0.id == "mru" })?.items ?? []
            let libraryItems = sections
                .filter { $0.id != "mru" }
                .flatMap(\.items)
            return mruItems + libraryItems
        }()

        var seen = Set<String>()
        var prioritizedRequests: [ArtworkRequest] = []
        let startupArtworkPrefetchLimit = 24
        prioritizedRequests.reserveCapacity(startupArtworkPrefetchLimit)
        for item in prioritizedItems {
            let candidates: [(URL, ArtworkKind)] = [
                (item.heroImageURL, .hero),
                (item.posterImageURL, .poster),
                (item.artURL, .poster)
            ].compactMap { url, kind in
                guard let url else { return nil }
                return (url, kind)
            }
            for (candidate, kind) in candidates {
                let key = candidate.absoluteString
                guard seen.insert(key).inserted else { continue }
                prioritizedRequests.append(Self.artworkRequest(url: candidate, kind: kind, priority: .low))
                if prioritizedRequests.count >= startupArtworkPrefetchLimit {
                    break
                }
            }
            if prioritizedRequests.count >= startupArtworkPrefetchLimit {
                break
            }
        }
        guard !prioritizedRequests.isEmpty else { return }

        dependencies.logger.info(
            "Library artwork prefetch scheduled: requested=\(prioritizedRequests.count)"
        )

        let registry = dependencies.taskRegistry
        _ = await dependencies.taskRegistry.register(Task { @MainActor [registry] in
            if !dependencies.isSuspendedForStreaming() {
                for batch in prioritizedRequests.chunked(into: 3) {
                    if Task.isCancelled || dependencies.isSuspendedForStreaming() { break }
                    var results: [PrefetchResult] = []
                    for request in batch {
                        if dependencies.isSuspendedForStreaming() { break }
                        let result = await prefetchArtworkURL(
                            request,
                            reason: "startup_library",
                            recentTTL: 600,
                            dependencies: dependencies
                        )
                        results.append(result)
                    }
                    if results.contains(.noSpace) {
                        await disableArtworkPrefetchForSession(
                            reason: "storage_full_during_prefetch",
                            dependencies: dependencies
                        )
                        break
                    }
                }
            }
            await registry.remove(id: libraryArtworkPrefetchTaskID)
        }, id: libraryArtworkPrefetchTaskID)
    }

    func prefetchVisibleHomeArtwork(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot,
        dependencies: Dependencies
    ) async {
        guard !dependencies.isSuspendedForStreaming() else { return }
        guard !dependencies.isArtworkPrefetchDisabledForSession() else { return }
        let requests = Array(
            Self.visibleHomeArtworkRequests(
                sections: sections,
                merchandising: merchandising
            ).prefix(StratixConstants.Hydration.visibleHomeArtworkPrefetchLimit)
        )
        guard !requests.isEmpty else { return }
        var results: [PrefetchResult] = []
        for request in requests {
            let result = await prefetchArtworkURL(
                request,
                reason: "startup_home_visible",
                recentTTL: 600,
                dependencies: dependencies
            )
            results.append(result)
        }
        if results.contains(.noSpace) {
            await disableArtworkPrefetchForSession(
                reason: "storage_full_during_visible_home_prefetch",
                dependencies: dependencies
            )
        }
    }

    func disableArtworkPrefetchForSession(
        reason: String,
        dependencies: Dependencies
    ) async {
        guard !dependencies.isArtworkPrefetchDisabledForSession() else { return }
        dependencies.setArtworkPrefetchDisabledForSession(true)
        dependencies.applyAction(.artworkPrefetchThrottleSet(true))
        await dependencies.taskRegistry.cancel(id: libraryArtworkPrefetchTaskID)
        await dependencies.taskRegistry.cancelGroup(artworkPrefetchTaskGroupID)
        dependencies.setArtworkPrefetchLastCompletedAtByURL([:])
        dependencies.logger.warning("Library artwork prefetch disabled for this session: \(reason)")
    }

    static func visibleHomeArtworkRequests(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot
    ) -> [ArtworkRequest] {
        let mruItems = sections.first(where: { $0.id == "mru" })?.items
            ?? sections.flatMap(\.items).filter(\.isInMRU)
        let allItems = LibraryController.allLibraryItems(from: sections)
        let featuredItem = merchandising.recentlyAddedItems.first ?? mruItems.first ?? allItems.first

        var requests: [ArtworkRequest] = []
        var seenURLs = Set<String>()

        func append(_ url: URL?, kind: ArtworkKind) {
            guard let url else { return }
            let key = url.absoluteString
            guard seenURLs.insert(key).inserted else { return }
            requests.append(artworkRequest(url: url, kind: kind, priority: .high))
        }

        append(featuredItem?.heroImageURL ?? featuredItem?.artURL, kind: .hero)
        for item in merchandising.recentlyAddedItems.prefix(StratixConstants.Hydration.visibleCarouselItemCount) {
            append(item.heroImageURL ?? item.artURL, kind: .hero)
            append(item.posterImageURL ?? item.artURL ?? item.heroImageURL, kind: .poster)
        }
        for item in mruItems.prefix(StratixConstants.Hydration.visibleHomeRowItemCount) {
            append(item.posterImageURL ?? item.artURL ?? item.heroImageURL, kind: .poster)
        }
        for row in merchandising.rows.prefix(StratixConstants.Hydration.visibleHomeRowCount) {
            for item in row.items.prefix(StratixConstants.Hydration.visibleHomeRowItemCount) {
                append(item.posterImageURL ?? item.artURL ?? item.heroImageURL, kind: .poster)
            }
        }

        return requests
    }

    private func prefetchArtworkURL(
        _ request: ArtworkRequest,
        reason: String,
        recentTTL: TimeInterval,
        dependencies: Dependencies
    ) async -> PrefetchResult {
        guard !dependencies.isSuspendedForStreaming() else { return .failed }
        let key = request.url.absoluteString

        if let lastCompletedAt = dependencies.artworkPrefetchLastCompletedAtByURL()[key],
           Date().timeIntervalSince(lastCompletedAt) < recentTTL {
            return .completed
        }

        if let inFlight: Task<PrefetchResult, Never> = await dependencies.taskRegistry.task(
            group: artworkPrefetchTaskGroupID,
            key: key
        ) {
            return await inFlight.value
        }

        let task: Task<PrefetchResult, Never> = Task.detached(priority: .background) { [artworkPipeline = dependencies.artworkPipeline] in
            let outcome = await artworkPipeline.prefetch(
                request,
                reason: reason,
                recentTTL: recentTTL
            )
            switch outcome {
            case .noSpace:
                return .noSpace
            case .failed:
                return .failed
            case .completed, .skippedCached, .skippedRecent:
                return .completed
            }
        }
        _ = await dependencies.taskRegistry.register(task, group: artworkPrefetchTaskGroupID, key: key)
        let prefetchResult = await task.value
        await dependencies.taskRegistry.remove(group: artworkPrefetchTaskGroupID, key: key)

        if prefetchResult == .completed {
            var completedByURL = dependencies.artworkPrefetchLastCompletedAtByURL()
            completedByURL[key] = Date()
            if completedByURL.count > 400 {
                let cutoff = Date().addingTimeInterval(-3_600)
                completedByURL = completedByURL.filter { $0.value >= cutoff }
            }
            dependencies.setArtworkPrefetchLastCompletedAtByURL(completedByURL)
        }

        return prefetchResult
    }

    private static func artworkRequest(
        url: URL,
        kind: ArtworkKind,
        priority: ArtworkPriority
    ) -> ArtworkRequest {
        ArtworkRequest(url: url, kind: kind, priority: priority)
    }

    private static func isStorageConstrainedForPrefetch() -> Bool {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey]
        guard let values = try? cacheDirectory.resourceValues(forKeys: keys) else {
            return false
        }
        let availableBytes = values.volumeAvailableCapacity.map(Int64.init)
        return (availableBytes ?? Int64.max) < 300_000_000
    }
}

private let libraryArtworkPrefetchTaskID = "libraryArtworkPrefetch"
private let artworkPrefetchTaskGroupID = "artworkPrefetch"
