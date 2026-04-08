// LibraryHydrationPersistence.swift
// Defines library hydration persistence.
//

import Foundation
import StratixModels

actor DiskSnapshotWriter<Snapshot: Codable & Sendable> {
    private let url: URL
    private let debounceDuration: Duration
    private var latestSnapshot: Snapshot?
    private var writeLoopTask: Task<Void, Never>?

    init(url: URL, debounceDuration: Duration = .milliseconds(200)) {
        self.url = url
        self.debounceDuration = debounceDuration
    }

    func schedule(snapshot: Snapshot) {
        latestSnapshot = snapshot
        guard writeLoopTask == nil else { return }
        writeLoopTask = Task {
            await runWriteLoop()
        }
    }

    func flush() async {
        while writeLoopTask != nil || latestSnapshot != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func runWriteLoop() async {
        var needsInitialDebounce = true

        while true {
            if needsInitialDebounce {
                try? await Task.sleep(for: debounceDuration)
            }

            guard let snapshot = latestSnapshot else {
                writeLoopTask = nil
                return
            }

            latestSnapshot = nil
            if let data = try? JSONEncoder().encode(snapshot) {
                let directoryURL = url.deletingLastPathComponent()
                try? FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
                try? data.write(to: url, options: .atomic)
            }

            if latestSnapshot == nil {
                writeLoopTask = nil
                return
            }

            needsInitialDebounce = false
        }
    }
}

actor LibraryHydrationPersistenceStore {
    private let productDetailsWriter: DiskSnapshotWriter<ProductDetailsDiskCacheSnapshot>
    private let libraryRepository: any LibraryRepository
    private var hydrationGeneration: UInt64 = 0

    init(
        detailsURL: URL,
        libraryRepository: any LibraryRepository
    ) {
        self.productDetailsWriter = DiskSnapshotWriter(
            url: detailsURL,
            debounceDuration: .milliseconds(200)
        )
        self.libraryRepository = libraryRepository
    }

    init(
        detailsURL: URL,
        sectionsURL: URL
    ) {
        let repository: any LibraryRepository
        do {
            repository = try SwiftDataLibraryRepository(storeURL: sectionsURL)
        } catch {
            fatalError("Failed to initialize library repository: \(error)")
        }
        self.init(detailsURL: detailsURL, libraryRepository: repository)
    }

    func scheduleProductDetailsCache(
        details: [ProductID: CloudLibraryProductDetail],
        savedAt: Date = .now,
        refreshSource: String = "product_details_cache"
    ) async {
        let metadata = makeHydrationMetadata(
            savedAt: savedAt,
            refreshSource: refreshSource,
            homeReady: false,
            trigger: "product_details_refresh"
        )
        let snapshot = ProductDetailsDiskCacheSnapshot(
            savedAt: savedAt,
            details: details,
            metadata: metadata
        )
        await productDetailsWriter.schedule(snapshot: snapshot)
    }

    func flushProductDetailsCache() async {
        await productDetailsWriter.flush()
    }

    func scheduleUnifiedSectionsCache(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        discovery: HomeMerchandisingDiscoveryCachePayload?,
        savedAt: Date,
        isUnifiedHomeReady: Bool,
        refreshSource: String = "unified_sections_cache"
    ) async {
        guard !sections.isEmpty else { return }
        let metadata = makeHydrationMetadata(
            savedAt: savedAt,
            refreshSource: refreshSource,
            homeReady: isUnifiedHomeReady,
            trigger: refreshSource,
            completenessBySectionID: Dictionary(
                uniqueKeysWithValues: sections.map { ($0.id, !$0.items.isEmpty) }
            )
        )
        let snapshot = LibrarySectionsDiskCacheSnapshot(
            savedAt: savedAt,
            sections: LibraryHydrationSnapshotCodec.sectionSnapshots(from: sections),
            homeMerchandising: homeMerchandising.map {
                LibraryHydrationSnapshotCodec.makeHomeMerchandisingDiskCacheSnapshot($0, metadata: metadata)
            },
            siglDiscovery: discovery.map {
                LibraryHydrationSnapshotCodec.makeHomeMerchandisingDiscoveryDiskCacheSnapshot($0, metadata: metadata)
            },
            isUnifiedHomeReady: isUnifiedHomeReady,
            metadata: metadata
        )
        await libraryRepository.saveUnifiedSectionsSnapshot(snapshot)
    }

    func flushUnifiedSectionsCache() async {
        await libraryRepository.flushUnifiedSectionsCache()
    }

    func schedule(_ intent: LibraryHydrationPersistenceIntent) async {
        await schedule(intent, publicationPlan: nil, publicationResult: nil)
    }

    func schedule(
        _ intent: LibraryHydrationPersistenceIntent,
        publicationPlan: LibraryHydrationPublicationPlan?,
        publicationResult: LibraryHydrationPublicationResult?
    ) async {
        switch intent {
        case .none:
            return
        case .unifiedSections(let sections):
            await libraryRepository.saveUnifiedSectionsSnapshot(
                finalizedSectionsSnapshot(
                    sections,
                    publicationPlan: publicationPlan,
                    publicationResult: publicationResult
                )
            )
        case .productDetails(let details):
            await productDetailsWriter.schedule(
                snapshot: finalizedProductDetailsSnapshot(
                    details,
                    publicationPlan: publicationPlan,
                    publicationResult: publicationResult
                )
            )
        case .unifiedSectionsAndProductDetails(let sections, let details):
            await libraryRepository.saveUnifiedSectionsSnapshot(
                finalizedSectionsSnapshot(
                    sections,
                    publicationPlan: publicationPlan,
                    publicationResult: publicationResult
                )
            )
            await productDetailsWriter.schedule(
                snapshot: finalizedProductDetailsSnapshot(
                    details,
                    publicationPlan: publicationPlan,
                    publicationResult: publicationResult
                )
            )
        }
    }

    static func makeUnifiedSectionsSnapshot(
        sections: [CloudLibrarySection],
        homeMerchandising: HomeMerchandisingSnapshot?,
        discovery: HomeMerchandisingDiscoveryCachePayload?,
        savedAt: Date,
        isUnifiedHomeReady: Bool,
        refreshSource: String = "unified_sections_cache",
        trigger: String = "unified_sections_cache",
        publicationPlan: LibraryHydrationPublicationPlan? = nil
    ) -> LibrarySectionsDiskCacheSnapshot {
        let config = LibraryHydrationConfig()
        let metadata = LibraryHydrationMetadata(
            snapshotID: UUID(),
            generatedAt: savedAt,
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
            market: config.market,
            language: config.language,
            refreshSource: refreshSource,
            hydrationGeneration: 0,
            homeReady: isUnifiedHomeReady,
            completenessBySectionID: Dictionary(
                uniqueKeysWithValues: sections.map { ($0.id, !$0.items.isEmpty) }
            ),
            deferredStages: publicationPlan?.stages ?? [],
            trigger: trigger
        )
        return LibrarySectionsDiskCacheSnapshot(
            savedAt: savedAt,
            sections: LibraryHydrationSnapshotCodec.sectionSnapshots(from: sections),
            homeMerchandising: homeMerchandising.map {
                LibraryHydrationSnapshotCodec.makeHomeMerchandisingDiskCacheSnapshot($0, metadata: metadata)
            },
            siglDiscovery: discovery.map {
                LibraryHydrationSnapshotCodec.makeHomeMerchandisingDiscoveryDiskCacheSnapshot($0, metadata: metadata)
            },
            isUnifiedHomeReady: isUnifiedHomeReady,
            metadata: metadata
        )
    }

    static func makeProductDetailsSnapshot(
        details: [ProductID: CloudLibraryProductDetail],
        savedAt: Date,
        refreshSource: String = "product_details_cache",
        trigger: String = "product_details_refresh"
    ) -> ProductDetailsDiskCacheSnapshot {
        let config = LibraryHydrationConfig()
        let metadata = LibraryHydrationMetadata(
            snapshotID: UUID(),
            generatedAt: savedAt,
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
            market: config.market,
            language: config.language,
            refreshSource: refreshSource,
            hydrationGeneration: 0,
            homeReady: false,
            completenessBySectionID: [:],
            deferredStages: [],
            trigger: trigger
        )
        return ProductDetailsDiskCacheSnapshot(
            savedAt: savedAt,
            details: details,
            metadata: metadata
        )
    }

    private func nextHydrationGeneration() -> UInt64 {
        hydrationGeneration &+= 1
        return hydrationGeneration
    }

    private func makeHydrationMetadata(
        savedAt: Date,
        refreshSource: String,
        homeReady: Bool,
        trigger: String,
        deferredStages: [LibraryHydrationStage] = [],
        completenessBySectionID: [String: Bool] = [:]
    ) -> LibraryHydrationMetadata {
        let config = LibraryHydrationConfig()
        return LibraryHydrationMetadata(
            snapshotID: UUID(),
            generatedAt: savedAt,
            cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion,
            market: config.market,
            language: config.language,
            refreshSource: refreshSource,
            hydrationGeneration: nextHydrationGeneration(),
            homeReady: homeReady,
            completenessBySectionID: completenessBySectionID,
            deferredStages: deferredStages,
            trigger: trigger
        )
    }

    private func finalizedSectionsSnapshot(
        _ snapshot: LibrarySectionsDiskCacheSnapshot,
        publicationPlan: LibraryHydrationPublicationPlan?,
        publicationResult: LibraryHydrationPublicationResult?
    ) -> LibrarySectionsDiskCacheSnapshot {
        let deferredStages = remainingStages(
            publicationPlan: publicationPlan,
            publicationResult: publicationResult
        )
        let completeness = Dictionary(
            uniqueKeysWithValues: snapshot.sections.map { ($0.id, !$0.items.isEmpty) }
        )
        let metadata = makeHydrationMetadata(
            savedAt: snapshot.savedAt,
            refreshSource: snapshot.metadata.refreshSource,
            homeReady: snapshot.isUnifiedHomeReady,
            trigger: snapshot.metadata.trigger,
            deferredStages: deferredStages,
            completenessBySectionID: completeness
        )
        return LibrarySectionsDiskCacheSnapshot(
            savedAt: snapshot.savedAt,
            sections: snapshot.sections,
            homeMerchandising: snapshot.homeMerchandising,
            siglDiscovery: snapshot.siglDiscovery,
            isUnifiedHomeReady: snapshot.isUnifiedHomeReady,
            cacheVersion: snapshot.cacheVersion,
            metadata: metadata
        )
    }

    private func finalizedProductDetailsSnapshot(
        _ snapshot: ProductDetailsDiskCacheSnapshot,
        publicationPlan: LibraryHydrationPublicationPlan?,
        publicationResult: LibraryHydrationPublicationResult?
    ) -> ProductDetailsDiskCacheSnapshot {
        let metadata = makeHydrationMetadata(
            savedAt: snapshot.savedAt,
            refreshSource: snapshot.metadata.refreshSource,
            homeReady: false,
            trigger: snapshot.metadata.trigger,
            deferredStages: remainingStages(
                publicationPlan: publicationPlan,
                publicationResult: publicationResult
            ),
            completenessBySectionID: [:]
        )
        return ProductDetailsDiskCacheSnapshot(
            savedAt: snapshot.savedAt,
            details: snapshot.details,
            cacheVersion: snapshot.cacheVersion,
            metadata: metadata
        )
    }

    private func remainingStages(
        publicationPlan: LibraryHydrationPublicationPlan?,
        publicationResult: LibraryHydrationPublicationResult?
    ) -> [LibraryHydrationStage] {
        guard let publicationPlan else { return [] }
        let completed = Set(publicationResult?.completedStages ?? [])
        return publicationPlan.stages.filter { !completed.contains($0) }
    }
}

private enum LibraryHydrationSnapshotCodec {
    static func sectionSnapshots(from sections: [CloudLibrarySection]) -> [LibrarySectionDiskCacheSnapshot] {
        sections.map { section in
            LibrarySectionDiskCacheSnapshot(
                id: section.id,
                name: section.name,
                items: section.items.map(libraryItemSnapshot(from:))
            )
        }
    }

    static func libraryItemSnapshot(from item: CloudLibraryItem) -> LibraryItemDiskCacheSnapshot {
        LibraryItemDiskCacheSnapshot(
            titleId: TitleID(rawValue: item.titleId),
            productId: ProductID(rawValue: item.productId),
            name: item.name,
            shortDescription: item.shortDescription,
            artURL: item.artURL?.absoluteString,
            posterImageURL: item.posterImageURL?.absoluteString,
            heroImageURL: item.heroImageURL?.absoluteString,
            galleryImageURLs: item.galleryImageURLs.map(\.absoluteString),
            publisherName: item.publisherName,
            attributes: item.attributes.map { attribute in
                LibraryAttributeDiskCacheSnapshot(
                    name: attribute.name,
                    localizedName: attribute.localizedName
                )
            },
            supportedInputTypes: item.supportedInputTypes,
            isInMRU: item.isInMRU
        )
    }

    static func makeHomeMerchandisingDiskCacheSnapshot(
        _ snapshot: HomeMerchandisingSnapshot,
        metadata: LibraryHydrationMetadata
    ) -> HomeMerchandisingDiskCacheSnapshot {
        HomeMerchandisingDiskCacheSnapshot(
            savedAt: snapshot.generatedAt,
            recentlyAddedItems: snapshot.recentlyAddedItems.map(libraryItemSnapshot(from:)),
            rows: snapshot.rows.map { row in
                HomeMerchandisingRowDiskCacheSnapshot(
                    alias: row.alias,
                    label: row.label,
                    source: row.source.rawValue,
                    items: row.items.map(libraryItemSnapshot(from:))
                )
            },
            metadata: metadata
        )
    }

    static func makeHomeMerchandisingDiscoveryDiskCacheSnapshot(
        _ snapshot: HomeMerchandisingDiscoveryCachePayload,
        metadata: LibraryHydrationMetadata
    ) -> HomeMerchandisingDiscoveryDiskCacheSnapshot {
        HomeMerchandisingDiscoveryDiskCacheSnapshot(
            savedAt: snapshot.savedAt,
            entries: snapshot.entries.map { entry in
                HomeMerchandisingDiscoveryEntryDiskCacheSnapshot(
                    alias: entry.alias,
                    label: entry.label,
                    siglID: entry.siglID,
                    source: entry.source.rawValue
                )
            },
            metadata: metadata
        )
    }
}
