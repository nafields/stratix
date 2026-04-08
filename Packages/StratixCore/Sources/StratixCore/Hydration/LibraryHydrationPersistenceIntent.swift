// LibraryHydrationPersistenceIntent.swift
// Defines library hydration persistence intent for the Hydration surface.
//

import Foundation

enum LibraryHydrationPersistenceIntent: Sendable, Equatable {
    case none
    case unifiedSections(LibrarySectionsDiskCacheSnapshot)
    case productDetails(ProductDetailsDiskCacheSnapshot)
    case unifiedSectionsAndProductDetails(
        sections: LibrarySectionsDiskCacheSnapshot,
        details: ProductDetailsDiskCacheSnapshot
    )
}
