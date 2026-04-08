// ArtworkPipeline.swift
// Defines artwork pipeline for the Artwork surface.
//

import Foundation
import CryptoKit
import DiagnosticsKit

public enum ArtworkKind: String, Sendable {
    case poster
    case hero
    case gallery
    case trailer
    case avatar
}

public enum ArtworkPriority: Int, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case immediate = 3
}

public enum ArtworkSource: String, Sendable {
    case memory
    case disk
    case network
}

public enum ArtworkLoadMode: Sendable {
    case defaultLoad
    case prefetch
}

public struct ArtworkRequest: Hashable, Sendable {
    public let url: URL
    public let kind: ArtworkKind
    public let priority: ArtworkPriority

    public init(url: URL, kind: ArtworkKind, priority: ArtworkPriority = .normal) {
        self.url = url
        self.kind = kind
        self.priority = priority
    }

    var cacheKey: String {
        ArtworkPipeline.cacheKey(for: url)
    }
}

public struct ArtworkResponse: Sendable {
    public let data: Data
    public let source: ArtworkSource
}

public enum ArtworkPrefetchOutcome: String, Sendable {
    case completed
    case skippedCached
    case skippedRecent
    case failed
    case noSpace
}

public typealias ArtworkDataFetcher = @Sendable (URL) async throws -> Data

public struct ArtworkDiskCachePolicy: Sendable {
    public let maxTotalBytes: Int64
    public let maxFileCount: Int
    public let pruneAfterWriteCount: Int

    public init(
        maxTotalBytes: Int64 = 512 * 1_024 * 1_024,
        maxFileCount: Int = 4_000,
        pruneAfterWriteCount: Int = 24
    ) {
        self.maxTotalBytes = maxTotalBytes
        self.maxFileCount = maxFileCount
        self.pruneAfterWriteCount = pruneAfterWriteCount
    }
}

public actor ArtworkPipeline {
    public static let shared = ArtworkPipeline()

    private let logger = GLogger(category: .ui)
    private let memoryCache = NSCache<NSString, NSData>()
    private var inFlight: [String: Task<ArtworkResponse?, Error>] = [:]
    private var recentPrefetchByKey: [String: Date] = [:]
    private let cacheDirectory: URL
    private let diskCachePolicy: ArtworkDiskCachePolicy
    private let fetcher: ArtworkDataFetcher
    private var writesSinceLastPrune = 0
    private var pruneTask: Task<Void, Never>?

    public init(
        cacheDirectory: URL? = nil,
        diskCachePolicy: ArtworkDiskCachePolicy = ArtworkDiskCachePolicy(),
        fetcher: @escaping ArtworkDataFetcher = ArtworkPipeline.defaultFetcher
    ) {
        let caches = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = caches.appendingPathComponent("stratix.artwork", isDirectory: true)
        self.diskCachePolicy = diskCachePolicy
        self.fetcher = fetcher
        memoryCache.countLimit = 256
        memoryCache.totalCostLimit = 128 * 1_024 * 1_024
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    public func cachedData(for request: ArtworkRequest) async -> ArtworkResponse? {
        let key = request.cacheKey as NSString
        if let cached = memoryCache.object(forKey: key) {
            logger.debug("Artwork cache hit (memory) kind=\(request.kind.rawValue) url=\(request.url.absoluteString)")
            return ArtworkResponse(data: cached as Data, source: .memory)
        }

        let diskURL = diskCacheURL(for: request)
        if let data = try? Data(contentsOf: diskURL, options: .mappedIfSafe) {
            memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: diskURL.path)
            logger.debug("Artwork cache hit (disk) kind=\(request.kind.rawValue) url=\(request.url.absoluteString)")
            return ArtworkResponse(data: data, source: .disk)
        }

        return nil
    }

    public func data(for request: ArtworkRequest, mode: ArtworkLoadMode = .defaultLoad) async throws -> ArtworkResponse? {
        if let cached = await cachedData(for: request) {
            return cached
        }

        let key = request.cacheKey
        let task: Task<ArtworkResponse?, Error>
        if let existing = inFlight[key] {
            task = existing
            logger.debug("Artwork request joined in-flight kind=\(request.kind.rawValue) url=\(request.url.absoluteString)")
        } else {
            logger.debug("Artwork cache miss kind=\(request.kind.rawValue) url=\(request.url.absoluteString)")
            task = Task<ArtworkResponse?, Error>(priority: taskPriority(for: request.priority)) { [fetcher] in
                if Task.isCancelled { return nil }
                let priorityLabel = request.priority
                let kindLabel = request.kind
                let urlLabel = request.url.absoluteString
                let _ = (priorityLabel, kindLabel, urlLabel)
                let data = try await fetcher(request.url)
                if Task.isCancelled { return nil }
                return ArtworkResponse(data: data, source: .network)
            }
            inFlight[key] = task
            logger.debug(
                "Artwork fetch started kind=\(request.kind.rawValue) priority=\(request.priority.rawValue) url=\(request.url.absoluteString)"
            )
        }

        do {
            let response = try await task.value
            inFlight[key] = nil
            guard let response else { return nil }
            try await persist(response.data, for: request)
            logger.debug("Artwork fetch complete kind=\(request.kind.rawValue) url=\(request.url.absoluteString)")
            return response
        } catch {
            if error is CancellationError {
                logger.debug("Artwork request cancelled kind=\(request.kind.rawValue) url=\(request.url.absoluteString)")
                throw error
            }
            inFlight[key] = nil
            if (error as NSError).code == NSURLErrorCancelled {
                logger.debug("Artwork fetch cancelled kind=\(request.kind.rawValue) url=\(request.url.absoluteString)")
            } else {
                logger.warning("Artwork fetch failed kind=\(request.kind.rawValue) url=\(request.url.absoluteString) error=\(error.localizedDescription)")
            }
            throw error
        }
    }

    public func prefetch(
        _ request: ArtworkRequest,
        reason: String,
        recentTTL: TimeInterval
    ) async -> ArtworkPrefetchOutcome {
        let key = request.cacheKey
        if let last = recentPrefetchByKey[key],
           Date().timeIntervalSince(last) < recentTTL {
            logger.debug("Artwork prefetch skipped (recent TTL) reason=\(reason) url=\(request.url.absoluteString)")
            return .skippedRecent
        }

        if let cached = await cachedData(for: request) {
            logger.debug("Artwork prefetch skipped (cached) reason=\(reason) url=\(request.url.absoluteString) source=\(cached.source.rawValue)")
            recentPrefetchByKey[key] = Date()
            trimRecentPrefetchCacheIfNeeded()
            return .skippedCached
        }

        logger.debug("Artwork prefetch start reason=\(reason) kind=\(request.kind.rawValue) url=\(request.url.absoluteString)")
        do {
            let response = try await data(for: request, mode: .prefetch)
            if response != nil {
                recentPrefetchByKey[key] = Date()
                trimRecentPrefetchCacheIfNeeded()
                return .completed
            }
            return .failed
        } catch {
            if Self.isNoSpaceError(error) {
                logger.warning("Artwork prefetch failed (no space) reason=\(reason) url=\(request.url.absoluteString)")
                return .noSpace
            }
            return .failed
        }
    }

    public func diskCacheURL(for request: ArtworkRequest) -> URL {
        let kindFolder = cacheDirectory.appendingPathComponent(request.kind.rawValue, isDirectory: true)
        return kindFolder.appendingPathComponent(request.cacheKey).appendingPathExtension("img")
    }

    func flushPendingPruneForTesting() async {
        await pruneTask?.value
    }

    func forcePruneDiskCacheForTesting() async {
        await pruneDiskCacheIfNeeded(reason: "forced_test", force: true)
    }

    private func persist(_ data: Data, for request: ArtworkRequest) async throws {
        let key = request.cacheKey as NSString
        memoryCache.setObject(data as NSData, forKey: key, cost: data.count)

        let url = diskCacheURL(for: request)
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            if Self.isNoSpaceError(error) {
                logger.warning("Artwork disk write failed (no space) url=\(request.url.absoluteString)")
            }
            throw error
        }
        writesSinceLastPrune += 1
        schedulePruneIfNeeded()
    }

    private func trimRecentPrefetchCacheIfNeeded() {
        if recentPrefetchByKey.count <= 400 { return }
        let cutoff = Date().addingTimeInterval(-3_600)
        recentPrefetchByKey = recentPrefetchByKey.filter { $0.value >= cutoff }
    }

    private func schedulePruneIfNeeded() {
        guard writesSinceLastPrune >= diskCachePolicy.pruneAfterWriteCount else { return }
        guard pruneTask == nil else { return }
        writesSinceLastPrune = 0
        pruneTask = Task { [weak self] in
            guard let self else { return }
            await self.pruneDiskCacheIfNeeded(reason: "scheduled_write_budget", force: false)
        }
    }

    private func pruneDiskCacheIfNeeded(reason: String, force: Bool) async {
        defer { pruneTask = nil }

        let files = allCachedFiles()
        guard !files.isEmpty else { return }

        let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
        if !force,
           totalBytes <= diskCachePolicy.maxTotalBytes,
           files.count <= diskCachePolicy.maxFileCount {
            logger.debug(
                "Artwork prune skipped reason=\(reason) bytes=\(totalBytes) files=\(files.count)"
            )
            return
        }

        var bytesToRemove = max(0, totalBytes - diskCachePolicy.maxTotalBytes)
        var filesToRemove = max(0, files.count - diskCachePolicy.maxFileCount)
        var removedBytes: Int64 = 0
        var removedFiles = 0

        for file in files.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            if !force, bytesToRemove <= 0, filesToRemove <= 0 {
                break
            }
            do {
                try FileManager.default.removeItem(at: file.url)
                removedBytes += file.size
                removedFiles += 1
                bytesToRemove = max(0, bytesToRemove - file.size)
                filesToRemove = max(0, filesToRemove - 1)
            } catch {
                logger.warning("Artwork prune remove failed path=\(file.url.lastPathComponent) error=\(error.localizedDescription)")
            }
        }

        logger.info(
            "Artwork prune complete reason=\(reason) removedFiles=\(removedFiles) removedBytes=\(removedBytes)"
        )
    }

    private func taskPriority(for priority: ArtworkPriority) -> TaskPriority {
        switch priority {
        case .low: return .background
        case .normal: return .utility
        case .high: return .userInitiated
        case .immediate: return .high
        }
    }

    public static func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    public static func defaultFetcher(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 6
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private static func isNoSpaceError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileWriteOutOfSpaceError
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(POSIXErrorCode.ENOSPC.rawValue)
        }
        return false
    }

    private func allCachedFiles() -> [CachedArtworkFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [CachedArtworkFile] = []
        while let next = enumerator.nextObject() as? URL {
            guard let values = try? next.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }
            files.append(
                CachedArtworkFile(
                    url: next,
                    size: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }
        return files
    }
}

private struct CachedArtworkFile: Sendable {
    let url: URL
    let size: Int64
    let modifiedAt: Date
}
