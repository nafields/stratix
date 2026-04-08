// SwiftDataLibraryRepository.swift
// Defines the SwiftData-backed repository used for persisted library hydration snapshots.
//

import Foundation
import StratixModels
import SwiftData

@Model
/// Stores the single persisted unified-library snapshot payload in SwiftData.
final class UnifiedLibraryCacheRecord {
    @Attribute(.unique) var key: String
    var savedAt: Date
    var payload: Data

    init(
        key: String,
        savedAt: Date,
        payload: Data
    ) {
        self.key = key
        self.savedAt = savedAt
        self.payload = payload
    }
}

/// Backs the unified hydration snapshot with a single SwiftData record so startup restore can
/// read and update cached library state without juggling multiple persistence files.
actor SwiftDataLibraryRepository: LibraryRepository {
    private static let storeName = "StratixLibraryRepository"
    private static let unifiedSnapshotKey = "unified_sections_snapshot"
    private static let refreshSource = "swiftdata_library_repository"

    private let modelContainer: ModelContainer

    /// Creates the SwiftData repository using either an explicit store URL or an in-memory container.
    init(
        storeURL: URL? = nil,
        isStoredInMemoryOnly: Bool = false
    ) throws {
        let schema = Schema([UnifiedLibraryCacheRecord.self])
        let configuration = if let storeURL {
            ModelConfiguration(
                Self.storeName,
                schema: schema,
                url: storeURL
            )
        } else {
            ModelConfiguration(
                Self.storeName,
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        }
        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    /// Loads the cached section list from the persisted unified snapshot.
    func loadCachedSections() async -> [CloudLibrarySection] {
        await loadUnifiedSectionsSnapshot()?.sections ?? []
    }

    /// Saves the latest section list while preserving the rest of the unified snapshot payload.
    func saveSections(_ sections: [CloudLibrarySection]) async {
        let snapshot = await mergedSnapshot(
            sections: sections,
            homeMerchandising: nil,
            preserveHomeMerchandising: true,
            isUnifiedHomeReady: nil
        )
        await saveUnifiedSectionsSnapshot(snapshot)
    }

    /// Loads the cached home-merchandising snapshot when one exists.
    func loadCachedHomeMerchandising() async -> HomeMerchandisingSnapshot? {
        await loadUnifiedSectionsSnapshot()?.homeMerchandising
    }

    /// Saves the home-merchandising snapshot into the unified persistence record.
    func saveHomeMerchandising(_ snapshot: HomeMerchandisingSnapshot) async {
        let merged = await mergedSnapshot(
            sections: nil,
            homeMerchandising: snapshot,
            preserveHomeMerchandising: false,
            isUnifiedHomeReady: true
        )
        await saveUnifiedSectionsSnapshot(merged)
    }

    /// Loads and decodes the unified persisted library snapshot.
    func loadUnifiedSectionsSnapshot() async -> DecodedLibrarySectionsCacheSnapshot? {
        let context = makeContext()
        guard let record = try? fetchUnifiedRecord(in: context),
              let snapshot = try? JSONDecoder().decode(LibrarySectionsDiskCacheSnapshot.self, from: record.payload) else {
            return nil
        }
        return snapshot.decodedSnapshot
    }

    /// Rewrites the single persisted snapshot record with the latest unified cache payload.
    func saveUnifiedSectionsSnapshot(_ snapshot: LibrarySectionsDiskCacheSnapshot) async {
        let context = makeContext()
        guard let payload = try? JSONEncoder().encode(snapshot) else { return }
        do {
            if let record = try fetchUnifiedRecord(in: context) {
                record.savedAt = snapshot.savedAt
                record.payload = payload
            } else {
                context.insert(
                    UnifiedLibraryCacheRecord(
                        key: Self.unifiedSnapshotKey,
                        savedAt: snapshot.savedAt,
                        payload: payload
                    )
                )
            }
            try context.save()
        } catch {
            return
        }
    }

    /// No-ops because the SwiftData-backed store persists writes immediately.
    func flushUnifiedSectionsCache() async {}

    /// Deletes the persisted unified library snapshot from the store.
    func clearUnifiedSectionsCache() async {
        let context = makeContext()
        guard let record = try? fetchUnifiedRecord(in: context) else { return }
        context.delete(record)
        try? context.save()
    }

    /// Fetches the single unified snapshot record from the current model context.
    private func fetchUnifiedRecord(
        in context: ModelContext
    ) throws -> UnifiedLibraryCacheRecord? {
        let key = Self.unifiedSnapshotKey
        let descriptor = FetchDescriptor<UnifiedLibraryCacheRecord>(
            predicate: #Predicate<UnifiedLibraryCacheRecord> {
                $0.key == key
            }
        )
        return try context.fetch(descriptor).first
    }

    /// Creates a fresh model context for one repository operation.
    private func makeContext() -> ModelContext {
        ModelContext(modelContainer)
    }

    /// Preserves the untouched portion of the unified snapshot when only one cache fragment changed.
    private func mergedSnapshot(
        sections: [CloudLibrarySection]?,
        homeMerchandising: HomeMerchandisingSnapshot?,
        preserveHomeMerchandising: Bool,
        isUnifiedHomeReady: Bool?
    ) async -> LibrarySectionsDiskCacheSnapshot {
        let existingSnapshot = await loadUnifiedSectionsSnapshot()
        return LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
            sections: sections ?? existingSnapshot?.sections ?? [],
            homeMerchandising: preserveHomeMerchandising
                ? existingSnapshot?.homeMerchandising
                : homeMerchandising,
            discovery: existingSnapshot?.discovery,
            savedAt: existingSnapshot?.savedAt ?? .now,
            isUnifiedHomeReady: isUnifiedHomeReady ?? existingSnapshot?.isUnifiedHomeReady ?? false,
            refreshSource: Self.refreshSource,
            trigger: Self.refreshSource
        )
    }
}
