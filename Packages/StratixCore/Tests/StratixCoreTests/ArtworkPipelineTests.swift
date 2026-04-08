// ArtworkPipelineTests.swift
// Exercises artwork pipeline behavior.
//

import Foundation
import Testing
@testable import StratixCore

@Suite(.serialized)
struct ArtworkPipelineTests {
    @Test
    func data_deduplicatesInflightRequests() async throws {
        let counter = CounterBox()
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(cacheDirectory: tempDir) { _ in
            await counter.increment()
            try? await Task.sleep(nanoseconds: 120_000_000)
            return Data([0x01, 0x02, 0x03])
        }

        let request = ArtworkRequest(
            url: URL(string: "https://example.com/poster.png")!,
            kind: .poster,
            priority: .normal
        )

        async let first = pipeline.data(for: request)
        async let second = pipeline.data(for: request)
        _ = try await (first, second)

        let value = await counter.value
        #expect(value == 1)
    }

    @Test
    func prefetch_skipsCachedItems() async {
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(cacheDirectory: tempDir) { _ in
            Data([0xAA])
        }
        let request = ArtworkRequest(
            url: URL(string: "https://example.com/hero.jpg")!,
            kind: .hero,
            priority: .normal
        )

        _ = try? await pipeline.data(for: request)
        let outcome = await pipeline.prefetch(request, reason: "test_cached", recentTTL: 60)

        #expect(outcome == .skippedCached)
    }

    @Test
    func prefetch_respectsRecentTTL() async {
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(cacheDirectory: tempDir) { _ in
            Data([0xBB])
        }
        let request = ArtworkRequest(
            url: URL(string: "https://example.com/trailer.png")!,
            kind: .trailer,
            priority: .low
        )

        let first = await pipeline.prefetch(request, reason: "test_ttl", recentTTL: 300)
        let second = await pipeline.prefetch(request, reason: "test_ttl", recentTTL: 300)

        #expect(first == .completed || first == .skippedCached)
        #expect(second == .skippedRecent)
    }

    @Test
    func diskCachePathPersistsToDisk() async throws {
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(cacheDirectory: tempDir) { _ in
            Data([0xCC])
        }
        let request = ArtworkRequest(
            url: URL(string: "https://example.com/gallery.png")!,
            kind: .gallery,
            priority: .normal
        )

        _ = try await pipeline.data(for: request)
        let diskURL = await pipeline.diskCacheURL(for: request)

        #expect(FileManager.default.fileExists(atPath: diskURL.path))
    }

    @Test
    func metadataCacheMigratesToApplicationSupport() {
        let filename = "stratix.test-metadata-\(UUID().uuidString).json"
        let legacy = MetadataCacheStore.legacyURL(for: filename)
        let target = MetadataCacheStore.appSupportDirectory().appendingPathComponent(filename)

        try? Data("seed".utf8).write(to: legacy, options: .atomic)
        let resolved = MetadataCacheStore.url(for: filename)

        #expect(resolved == target)
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: legacy.path) == false)

        try? FileManager.default.removeItem(at: target)
    }

    @Test
    func prefetchURLsHonorsLimit() async {
        let counter = CounterBox()
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(cacheDirectory: tempDir) { _ in
            await counter.increment()
            return Data([0xDD])
        }
        let controller = await MainActor.run {
            LibraryController(artworkPipeline: pipeline)
        }
        let urls = (0..<10).compactMap { URL(string: "https://example.com/\($0).png") }

        await controller.prefetchArtworkURLs(urls, reason: "test_limit", limit: 3)

        let value = await counter.value
        #expect(value == 3)
    }

    @Test
    func visibleLoadAndPrefetch_shareInflightRequest() async throws {
        let counter = CounterBox()
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(cacheDirectory: tempDir) { _ in
            await counter.increment()
            try? await Task.sleep(nanoseconds: 120_000_000)
            return Data([0x10, 0x11])
        }
        let request = ArtworkRequest(
            url: URL(string: "https://example.com/shared.png")!,
            kind: .poster,
            priority: .normal
        )

        async let prefetch = pipeline.prefetch(request, reason: "visible_join", recentTTL: 60)
        async let visible = pipeline.data(for: ArtworkRequest(url: request.url, kind: .poster, priority: .high))
        let (prefetchOutcome, visibleResponse) = await (prefetch, try visible)

        let fetchCount = await counter.value
        #expect(fetchCount == 1)
        #expect(prefetchOutcome == .completed || prefetchOutcome == .skippedCached)
        #expect(visibleResponse?.data == Data([0x10, 0x11]))
    }

    @Test
    func cancellingOneJoinedRequest_doesNotCancelSharedFetch() async throws {
        let counter = CounterBox()
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(cacheDirectory: tempDir) { _ in
            await counter.increment()
            try await Task.sleep(nanoseconds: 180_000_000)
            return Data([0x21, 0x22])
        }
        let request = ArtworkRequest(
            url: URL(string: "https://example.com/cancel-shared.png")!,
            kind: .hero,
            priority: .normal
        )

        let first = Task {
            try await pipeline.data(for: request)
        }
        let second = Task {
            try await pipeline.data(for: ArtworkRequest(url: request.url, kind: .hero, priority: .high))
        }

        try? await Task.sleep(nanoseconds: 30_000_000)
        first.cancel()

        do {
            _ = try await first.value
        } catch {
            #expect(error is CancellationError)
        }

        let response = try await second.value
        let fetchCount = await counter.value
        #expect(fetchCount == 1)
        #expect(response?.data == Data([0x21, 0x22]))
    }

    @Test
    func sameURLDifferentPriority_deduplicatesNetworkFetch() async throws {
        let counter = CounterBox()
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(cacheDirectory: tempDir) { _ in
            await counter.increment()
            try? await Task.sleep(nanoseconds: 90_000_000)
            return Data([0x31, 0x32])
        }
        let url = URL(string: "https://example.com/reprioritized.png")!

        async let normal = pipeline.data(for: ArtworkRequest(url: url, kind: .poster, priority: .normal))
        async let high = pipeline.data(for: ArtworkRequest(url: url, kind: .poster, priority: .high))
        _ = try await (normal, high)

        let fetchCount = await counter.value
        #expect(fetchCount == 1)
    }

    @Test
    func metadataCacheDoesNotOverwriteExistingTarget() throws {
        let root = makeTempDirectory()
        let appSupport = root.appendingPathComponent("app-support", isDirectory: true)
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let filename = "stratix-existing-target.json"
        let target = appSupport.appendingPathComponent(filename)
        let legacyFile = legacy.appendingPathComponent(filename)
        try Data("target".utf8).write(to: target)
        try Data("legacy".utf8).write(to: legacyFile)

        let resolved = MetadataCacheStore.resolvedURL(
            for: filename,
            appSupportDirectory: appSupport,
            legacyDirectory: legacy,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
            copyItem: { try FileManager.default.copyItem(at: $0, to: $1) }
        )

        #expect(resolved == target)
        #expect(try Data(contentsOf: target) == Data("target".utf8))
        #expect(FileManager.default.fileExists(atPath: legacyFile.path))
    }

    @Test
    func metadataCacheFallsBackToCopyWhenMoveFails() throws {
        let root = makeTempDirectory()
        let appSupport = root.appendingPathComponent("app-support", isDirectory: true)
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let filename = "stratix-copy-fallback.json"
        let legacyFile = legacy.appendingPathComponent(filename)
        let target = appSupport.appendingPathComponent(filename)
        try Data("legacy".utf8).write(to: legacyFile)

        let resolved = MetadataCacheStore.resolvedURL(
            for: filename,
            appSupportDirectory: appSupport,
            legacyDirectory: legacy,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            moveItem: { _, _ in throw CocoaError(.fileWriteUnknown) },
            copyItem: { try FileManager.default.copyItem(at: $0, to: $1) }
        )

        #expect(resolved == target)
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: legacyFile.path))
    }

    @Test
    func metadataCacheMigrationIsIdempotent() throws {
        let root = makeTempDirectory()
        let appSupport = root.appendingPathComponent("app-support", isDirectory: true)
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let filename = "stratix-repeat.json"
        let legacyFile = legacy.appendingPathComponent(filename)
        let target = appSupport.appendingPathComponent(filename)
        try Data("legacy".utf8).write(to: legacyFile)

        let first = MetadataCacheStore.resolvedURL(
            for: filename,
            appSupportDirectory: appSupport,
            legacyDirectory: legacy,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
            copyItem: { try FileManager.default.copyItem(at: $0, to: $1) }
        )
        let second = MetadataCacheStore.resolvedURL(
            for: filename,
            appSupportDirectory: appSupport,
            legacyDirectory: legacy,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
            copyItem: { try FileManager.default.copyItem(at: $0, to: $1) }
        )

        #expect(first == target)
        #expect(second == target)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test
    func diskPrune_enforcesByteAndFileLimits() async throws {
        let tempDir = makeTempDirectory()
        let pipeline = ArtworkPipeline(
            cacheDirectory: tempDir,
            diskCachePolicy: ArtworkDiskCachePolicy(maxTotalBytes: 3, maxFileCount: 2, pruneAfterWriteCount: 1)
        ) { url in
            Data(url.lastPathComponent.utf8.prefix(2))
        }

        for index in 0..<3 {
            let request = ArtworkRequest(
                url: URL(string: "https://example.com/\(index).png")!,
                kind: .poster,
                priority: .normal
            )
            _ = try await pipeline.data(for: request)
        }
        await pipeline.flushPendingPruneForTesting()

        let cacheRoot = tempDir.appendingPathComponent("stratix.artwork", isDirectory: true)
        let files = cachedFiles(at: cacheRoot)
        let totalBytes = files.reduce(Int64(0)) { partial, file in
            partial + Int64((try? Data(contentsOf: file).count) ?? 0)
        }

        #expect(files.count <= 1)
        #expect(totalBytes <= 3)
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("artwork-pipeline-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cachedFiles(at root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { !$0.hasDirectoryPath }
    }
}

private actor CounterBox {
    private(set) var value: Int = 0

    func increment() {
        value += 1
    }
}
