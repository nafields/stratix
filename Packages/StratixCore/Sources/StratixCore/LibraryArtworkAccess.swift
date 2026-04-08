// LibraryArtworkAccess.swift
// Defines library artwork access.
//

import Foundation
import StratixModels

@MainActor
extension LibraryController {
    public var shouldThrottleArtworkPrefetch: Bool {
        isArtworkPrefetchDisabledForSession
    }

    public func noteArtworkPrefetchFailure(_ error: Error) async {
        guard Self.isNoSpaceError(error) else { return }
        await disableArtworkPrefetchForSession(reason: "storage_full")
    }

    public func prefetchArtworkURLs(
        _ urls: [URL],
        reason: String,
        recentTTL: TimeInterval = 600,
        limit: Int = 6
    ) async {
        await artworkPrefetchCoordinator.prefetchArtworkURLs(
            urls,
            reason: reason,
            recentTTL: recentTTL,
            limit: limit,
            dependencies: artworkPrefetchDependencies()
        )
    }

    func prefetchLibraryArtwork(_ sections: [CloudLibrarySection]) async {
        await artworkPrefetchCoordinator.prefetchLibraryArtwork(
            sections,
            dependencies: artworkPrefetchDependencies()
        )
    }

    func prefetchVisibleHomeArtwork(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot
    ) async {
        await artworkPrefetchCoordinator.prefetchVisibleHomeArtwork(
            sections: sections,
            merchandising: merchandising,
            dependencies: artworkPrefetchDependencies()
        )
    }

    private func artworkPrefetchDependencies() -> LibraryArtworkPrefetchCoordinator.Dependencies {
        .init(
            taskRegistry: taskRegistry,
            artworkPipeline: artworkPipeline,
            logger: logger,
            isSuspendedForStreaming: { [weak self] in
                self?.isSuspendedForStreaming ?? true
            },
            isArtworkPrefetchDisabledForSession: { [weak self] in
                self?.isArtworkPrefetchDisabledForSession ?? true
            },
            setArtworkPrefetchDisabledForSession: { [weak self] value in
                self?.isArtworkPrefetchDisabledForSession = value
            },
            lastArtworkPrefetchStartedAt: { [weak self] in
                self?.lastArtworkPrefetchStartedAt
            },
            setLastArtworkPrefetchStartedAt: { [weak self] value in
                self?.lastArtworkPrefetchStartedAt = value
            },
            artworkPrefetchLastCompletedAtByURL: { [weak self] in
                self?.artworkPrefetchLastCompletedAtByURL ?? [:]
            },
            setArtworkPrefetchLastCompletedAtByURL: { [weak self] value in
                self?.artworkPrefetchLastCompletedAtByURL = value
            },
            applyAction: { [weak self] action in
                self?.apply(action)
            }
        )
    }

    private func disableArtworkPrefetchForSession(reason: String) async {
        await artworkPrefetchCoordinator.disableArtworkPrefetchForSession(
            reason: reason,
            dependencies: artworkPrefetchDependencies()
        )
    }

    nonisolated private static func isNoSpaceError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(POSIXErrorCode.ENOSPC.rawValue) {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            if underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(POSIXErrorCode.ENOSPC.rawValue) {
                return true
            }
            if underlying.domain == NSCocoaErrorDomain, underlying.code == NSFileWriteOutOfSpaceError {
                return true
            }
        }
        return false
    }
}
