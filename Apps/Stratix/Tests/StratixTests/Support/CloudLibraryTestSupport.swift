// CloudLibraryTestSupport.swift
// Provides shared support for the Stratix / StratixTests surface.
//

import Foundation
import StratixModels
@testable import StratixCore
import XCloudAPI

#if canImport(Stratix)
@testable import Stratix
#endif

@MainActor
enum CloudLibraryTestSupport {
    static var retainedSettingsStores: [SettingsStore] = []

    static func makeSettingsStore(testName: String = #function) -> SettingsStore {
        let suiteName = "CloudLibraryTests.\(testName).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        retainedSettingsStores.append(store)
        return store
    }

    static func makeItem(
        titleID: String = "halo-title",
        productID: String = "halo-product",
        name: String = "Halo Infinite"
    ) -> CloudLibraryItem {
        CloudLibraryItem(
            titleId: titleID,
            productId: productID,
            name: name,
            shortDescription: "Test item",
            artURL: URL(string: "https://example.com/\(titleID).png"),
            posterImageURL: nil,
            heroImageURL: URL(string: "https://example.com/\(titleID)-hero.png"),
            galleryImageURLs: [],
            publisherName: "Xbox Game Studios",
            attributes: [],
            supportedInputTypes: [],
            isInMRU: false
        )
    }

    static func makeDetail(
        productId: String = "halo-product",
        title: String = "Halo Infinite"
    ) -> CloudLibraryProductDetail {
        CloudLibraryProductDetail(
            productId: productId,
            title: title,
            publisherName: "Xbox Game Studios",
            shortDescription: "Test detail",
            longDescription: "Long test detail",
            developerName: "343 Industries",
            releaseDate: "2021-12-08",
            capabilityLabels: [],
            genreLabels: [],
            mediaAssets: [],
            galleryImageURLs: [],
            trailers: [],
            achievementSummary: nil
        )
    }

    static func makeLibraryState(
        sections: [CloudLibrarySection] = [],
        productDetails: [ProductID: CloudLibraryProductDetail] = [:],
        isLoading: Bool = false,
        lastError: String? = nil,
        needsReauth: Bool = false,
        lastHydratedAt: Date? = nil,
        cacheSavedAt: Date? = nil,
        hasCompletedInitialHomeMerchandising: Bool = false,
        homeMerchandisingSessionSource: HomeMerchandisingSessionSource = .none,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool = false,
        catalogRevision: UInt64 = 1,
        detailRevision: UInt64 = 0,
        homeRevision: UInt64 = 0,
        sceneContentRevision: UInt64 = 1
    ) -> LibraryState {
        let items = sections.flatMap(\.items)
        let itemsByTitleID = Dictionary(
            items.map { (TitleID(rawValue: $0.titleId), $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let itemsByProductID = Dictionary(
            items.map { (ProductID(rawValue: $0.productId), $0) },
            uniquingKeysWith: { current, _ in current }
        )
        return LibraryState(
            sections: sections,
            itemsByTitleID: itemsByTitleID,
            itemsByProductID: itemsByProductID,
            productDetails: productDetails,
            isLoading: isLoading,
            lastError: lastError,
            needsReauth: needsReauth,
            lastHydratedAt: lastHydratedAt,
            cacheSavedAt: cacheSavedAt,
            isArtworkPrefetchThrottled: false,
            homeMerchandising: nil,
            discoveryEntries: [],
            isHomeMerchandisingLoading: false,
            hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
            homeMerchandisingSessionSource: homeMerchandisingSessionSource,
            hasRecoveredLiveHomeMerchandisingThisSession: hasRecoveredLiveHomeMerchandisingThisSession,
            catalogRevision: catalogRevision,
            detailRevision: detailRevision,
            homeRevision: homeRevision,
            sceneContentRevision: sceneContentRevision
        )
    }

    static func makeLibraryStateSnapshot(
        sections: [CloudLibrarySection] = [],
        productDetails: [ProductID: CloudLibraryProductDetail] = [:],
        isLoading: Bool = false,
        lastError: String? = nil,
        needsReauth: Bool = false,
        lastHydratedAt: Date? = nil,
        cacheSavedAt: Date? = nil,
        hasCompletedInitialHomeMerchandising: Bool = false,
        homeMerchandisingSessionSource: HomeMerchandisingSessionSource = .none,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool = false,
        catalogRevision: UInt64 = 1,
        detailRevision: UInt64 = 0,
        homeRevision: UInt64 = 0,
        sceneContentRevision: UInt64 = 1
    ) -> CloudLibraryStateSnapshot {
        CloudLibraryStateSnapshot(
            state: makeLibraryState(
                sections: sections,
                productDetails: productDetails,
                isLoading: isLoading,
                lastError: lastError,
                needsReauth: needsReauth,
                lastHydratedAt: lastHydratedAt,
                cacheSavedAt: cacheSavedAt,
                hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
                homeMerchandisingSessionSource: homeMerchandisingSessionSource,
                hasRecoveredLiveHomeMerchandisingThisSession: hasRecoveredLiveHomeMerchandisingThisSession,
                catalogRevision: catalogRevision,
                detailRevision: detailRevision,
                homeRevision: homeRevision,
                sceneContentRevision: sceneContentRevision
            )
        )
    }

    static func makeProfileController(
        gameDisplayName: String = "Player One",
        gamertag: String = "playerone",
        gamerscore: String = "88000",
        friendsCount: Int = 44,
        friendsLastUpdatedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        friendsErrorText: String? = nil
    ) -> ProfileController {
        let controller = ProfileController()
        controller.setCurrentUserProfile(
            XboxCurrentUserProfile(
                xuid: "xuid-1",
                gamertag: gamertag,
                gameDisplayName: gameDisplayName,
                gameDisplayPicRaw: URL(string: "https://example.com/profile.png"),
                gamerscore: gamerscore
            )
        )
        controller.setCurrentUserPresence(
            XboxCurrentUserPresence(
                xuid: "xuid-1",
                state: "online",
                devices: [],
                lastSeen: nil
            )
        )
        controller.setSocialPeopleTotalCount(friendsCount)
        controller.setSocialPeopleLastUpdatedAt(friendsLastUpdatedAt)
        controller.setLastSocialPeopleError(friendsErrorText)
        return controller
    }
}
