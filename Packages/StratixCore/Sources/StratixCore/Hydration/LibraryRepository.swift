// LibraryRepository.swift
// Defines library repository for the Hydration surface.
//

import Foundation
import StratixModels

protocol LibraryRepository: Actor {
    func loadCachedSections() async -> [CloudLibrarySection]
    func saveSections(_ sections: [CloudLibrarySection]) async
    func loadCachedHomeMerchandising() async -> HomeMerchandisingSnapshot?
    func saveHomeMerchandising(_ snapshot: HomeMerchandisingSnapshot) async
    func loadUnifiedSectionsSnapshot() async -> DecodedLibrarySectionsCacheSnapshot?
    func saveUnifiedSectionsSnapshot(_ snapshot: LibrarySectionsDiskCacheSnapshot) async
    func flushUnifiedSectionsCache() async
    func clearUnifiedSectionsCache() async
}
