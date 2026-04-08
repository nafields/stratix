// CloudLibraryTitleDetailMediaReadiness.swift
// Defines cloud library title detail media readiness for the CloudLibrary / Detail surface.
//

import SwiftUI

enum CloudLibraryInitialMediaKey: Hashable {
    case hero(URL)
    case poster(URL)
    case gallery(URL)
}

struct CloudLibraryTitleDetailReadinessState: Equatable {
    enum BeginResult: Equatable {
        case unchanged
        case waitingForRequiredMedia
        case readyImmediately
    }

    private(set) var stateID: String?
    private(set) var requiredMediaKeys: Set<String> = []
    private(set) var readyMediaKeys: Set<String> = []
    private(set) var hasReportedInitialMediaReady = false

    mutating func begin(
        for stateID: String,
        requiredMediaKeys: Set<String>
    ) -> BeginResult {
        guard self.stateID != stateID else { return .unchanged }

        self.stateID = stateID
        self.requiredMediaKeys = requiredMediaKeys
        readyMediaKeys = []
        hasReportedInitialMediaReady = requiredMediaKeys.isEmpty
        return hasReportedInitialMediaReady ? .readyImmediately : .waitingForRequiredMedia
    }

    mutating func markReady(_ key: String?) -> Bool {
        guard let key, !hasReportedInitialMediaReady else { return false }

        readyMediaKeys.insert(key)
        guard requiredMediaKeys.isSubset(of: readyMediaKeys) else { return false }

        hasReportedInitialMediaReady = true
        return true
    }

    mutating func forceReady() -> Bool {
        guard !hasReportedInitialMediaReady else { return false }
        hasReportedInitialMediaReady = true
        return true
    }
}

extension CloudLibraryTitleDetailScreen {
    private func insertReadinessKey(_ key: String?, into keys: inout Set<String>) {
        guard let key else { return }
        keys.insert(key)
    }

    func startInitialMediaReadinessGate() {
        let beginResult = readiness.begin(
            for: state.id,
            requiredMediaKeys: initialRequiredMediaKeys()
        )

        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil

        switch beginResult {
        case .unchanged:
            return
        case .readyImmediately:
            notifyInitialMediaReady()
            return
        case .waitingForRequiredMedia:
            break
        }

        readinessTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            await MainActor.run {
                forceInitialMediaReady()
            }
        }
    }

    func initialRequiredMediaKeys() -> Set<String> {
        var keys: Set<String> = []

        if let heroURL = state.heroImageURL {
            insertReadinessKey(mediaReadinessKey(.hero(heroURL)), into: &keys)
        } else if let posterURL = state.posterImageURL {
            insertReadinessKey(mediaReadinessKey(.poster(posterURL)), into: &keys)
        }

        for item in state.gallery.prefix(1) {
            insertReadinessKey(galleryReadinessKey(for: item), into: &keys)
        }
        return keys
    }

    func mediaReadinessKey(_ key: CloudLibraryInitialMediaKey?) -> String? {
        guard let key else { return nil }

        switch key {
        case .hero(let url):
            return "hero|\(url.absoluteString)"
        case .poster(let url):
            return "poster|\(url.absoluteString)"
        case .gallery(let url):
            return "gallery|\(url.absoluteString)"
        }
    }

    func galleryReadinessKey(for item: CloudLibraryGalleryItemViewState) -> String? {
        switch item.kind {
        case .image:
            return mediaReadinessKey(.gallery(item.mediaURL))
        case .video:
            guard let thumbnailURL = item.thumbnailURL else { return nil }
            return mediaReadinessKey(.gallery(thumbnailURL))
        }
    }

    func markMediaReady(_ key: String?) {
        if readiness.markReady(key) {
            notifyInitialMediaReady()
        }
    }

    func forceInitialMediaReady() {
        guard readiness.forceReady() else { return }
        notifyInitialMediaReady()
    }

    func notifyInitialMediaReady() {
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil
        onInitialMediaReady?()
    }

    func prefetchTrailerThumbnails() async {
        let trailerURLs = state.gallery
            .filter { $0.kind == .video && $0.thumbnailURL == nil }
            .map(\.mediaURL)
        guard !trailerURLs.isEmpty else { return }

        let targets = Array(trailerURLs.prefix(10))
        await withTaskGroup(of: Void.self) { group in
            for url in targets {
                group.addTask(priority: .background) {
                    if Task.isCancelled { return }
                    if await VideoFrameThumbnailCache.shared.image(for: url) != nil {
                        return
                    }
                    if let image = await VideoFrameExtractor.extractThumbnail(from: url) {
                        if Task.isCancelled { return }
                        await VideoFrameThumbnailCache.shared.setImage(image, for: url)
                    }
                }
            }
        }
    }
}
