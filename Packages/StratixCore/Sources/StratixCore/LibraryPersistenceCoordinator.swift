// LibraryPersistenceCoordinator.swift
// Defines the library persistence coordinator.
//

import Foundation
import StratixModels

@MainActor
extension LibraryController {
    /// Captures the controller's current library snapshot and schedules a unified cache write.
    func saveCloudLibrarySectionsCache() {
        saveCloudLibrarySectionsCache(
            sections: sections,
            homeMerchandising: homeMerchandising,
            discovery: cachedHomeMerchandisingDiscovery,
            savedAt: .now,
            isUnifiedHomeReady: hasCompletedInitialHomeMerchandising
        )
    }

    /// Queues the unified sections/home/discovery snapshot onto the persistence store without
    /// blocking the main-actor library controller.
    func saveCloudLibrarySectionsCache(
        sections currentSections: [CloudLibrarySection],
        homeMerchandising currentHomeMerchandising: HomeMerchandisingSnapshot?,
        discovery currentDiscovery: CachedHomeMerchandisingDiscovery?,
        savedAt: Date,
        isUnifiedHomeReady: Bool
    ) {
        guard !currentSections.isEmpty else { return }
        logHydrationDebug(
            "cache_save unifiedReady=\(isUnifiedHomeReady) savedAtAge=\(formattedAge(since: savedAt)) \(describeSections(currentSections)) \(describeHomeMerchandising(currentHomeMerchandising)) \(describeDiscovery(currentDiscovery))"
        )
        let persistenceStore = hydrationPersistenceStore
        sectionsCacheScheduleTask = Task(priority: .background) {
            await persistenceStore.scheduleUnifiedSectionsCache(
                sections: currentSections,
                homeMerchandising: currentHomeMerchandising,
                discovery: currentDiscovery,
                savedAt: savedAt,
                isUnifiedHomeReady: isUnifiedHomeReady
            )
        }
    }

    /// Queues a product-details cache write using the controller's current detail dictionary.
    func saveProductDetailsCache() {
        let persistenceStore = hydrationPersistenceStore
        let productDetails = self.productDetails
        productDetailsCacheScheduleTask = Task {
            await persistenceStore.scheduleProductDetailsCache(details: productDetails)
        }
    }

    func flushProductDetailsCacheForTesting() async {
        await productDetailsCacheScheduleTask?.value
        await hydrationPersistenceStore.flushProductDetailsCache()
    }

    func flushSectionsCacheForTesting() async {
        await sectionsCacheScheduleTask?.value
        await hydrationPersistenceStore.flushUnifiedSectionsCache()
    }

    /// Removes all persisted library caches so tests or sign-out flows start from a clean disk state.
    func clearPersistedLibraryCaches() {
        let repositoryURL = cacheLocations.repository
        let legacyRepositoryURL = cacheLocations.sections
            .deletingPathExtension()
            .appendingPathExtension("swiftdata")
        var persistedCacheURLs = [
            cacheLocations.details,
            cacheLocations.sections,
            repositoryURL,
            URL(fileURLWithPath: repositoryURL.path + "-shm"),
            URL(fileURLWithPath: repositoryURL.path + "-wal"),
            cacheLocations.homeMerchandising
        ]
        if legacyRepositoryURL != repositoryURL {
            persistedCacheURLs.append(contentsOf: [
                legacyRepositoryURL,
                URL(fileURLWithPath: legacyRepositoryURL.path + "-shm"),
                URL(fileURLWithPath: legacyRepositoryURL.path + "-wal"),
            ])
        }

        for cacheURL in persistedCacheURLs {
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    /// Restores disk caches once per authenticated session and only for the cache fragments that
    /// have not already been loaded into memory.
    func restoreDiskCachesIfNeeded(isAuthenticated: Bool) async {
        guard isAuthenticated else { return }
        let shouldLoadProductDetailsCache = !hasLoadedProductDetailsCache
        let shouldLoadSectionsCache = !hasLoadedSectionsCache && sections.isEmpty
        guard shouldLoadProductDetailsCache || shouldLoadSectionsCache else { return }
        do {
            let restoreResult = try await hydrationOrchestrator.performStartupRestore(
                controller: self,
                request: makeHydrationRequest(trigger: .startupRestore)
            )
            await applyHydrationOrchestrationResult(restoreResult)
            if shouldLoadProductDetailsCache {
                hasLoadedProductDetailsCache = true
            }
            if shouldLoadSectionsCache {
                hasLoadedSectionsCache = true
            }
        } catch {
            logger.warning("Startup restore failed: \(logString(for: error))")
        }
    }
}
