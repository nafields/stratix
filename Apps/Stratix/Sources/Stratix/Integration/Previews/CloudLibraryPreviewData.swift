// CloudLibraryPreviewData.swift
// Defines cloud library preview data for the Integration / Previews surface.
//

import Foundation
import StratixCore
import StratixModels
import XCloudAPI

enum CloudLibraryPreviewData {
    private static let capturedDumpTimestamp = "2026-02-26T23:51:49Z"
    private static let capturedProfileName = "stratix-preview"
    private static let capturedPresence = "Offline"
    private static let capturedGamerscore = "375"
    private static let capturedCloudLibraryTotal = 78
    private static let capturedConsoleTotal = 2
    private static let capturedProfileImageURL = URL(string: "https://images-eds-ssl.xboxlive.com/image?url=z951ykn43p4FqWbbFvR2Ec.8vbDhj8G2Xe7JngaTToBrrCmIEEXHC9UNrdJ6P7KIFXxmxGDtE9Vkd62rOpb7JUF_ds7a.6n_aHDK7ZA3NbAgydB9_rsvYhVdPdDeJEA1&format=png")

    static let sideRail = SideRailNavigationViewState(
        accountName: capturedProfileName,
        accountStatus: capturedPresence,
        accountDetail: "Gamerscore \(capturedGamerscore) • \(capturedCloudLibraryTotal) cloud titles",
        profileImageURL: capturedProfileImageURL,
        profileInitials: "D",
        navItems: [
            .init(id: .search, title: "Search", systemImage: "magnifyingglass"),
            .init(id: .home, title: "Home", systemImage: "house.fill"),
            .init(id: .library, title: "Library", systemImage: "square.grid.2x2.fill", badgeText: "\(capturedCloudLibraryTotal)"),
            .init(id: .consoles, title: "Consoles", systemImage: "tv.fill", badgeText: "\(capturedConsoleTotal)")
        ],
        trailingActions: []
    )

    static let cloudItems = CloudLibraryHomeScenario.cloudItems
    static let cloudSections = CloudLibraryHomeScenario.cloudSections
    static let home = CloudLibraryHomeScenario.home
    static let homeEmpty = CloudLibraryHomeScenario.homeEmpty
    static let library = CloudLibraryHomeScenario.library
    static let libraryEmpty = CloudLibraryHomeScenario.libraryEmpty
    static let detail = CloudLibraryHomeScenario.detail
    static let detailLongTitle = CloudLibraryHomeScenario.detailLongTitle

    static let statusLoading = CloudLibraryStatusViewState(
        kind: .loading,
        title: "Loading Game Pass",
        message: "Hydrating captured preview from dump \(capturedDumpTimestamp).",
        primaryActionTitle: nil
    )

    static let statusError = CloudLibraryStatusViewState(
        kind: .error,
        title: "Could not load Game Pass",
        message: "Preview fixture intentionally simulates a failed catalog refresh.",
        primaryActionTitle: "Retry"
    )

    static let statusEmpty = CloudLibraryStatusViewState(
        kind: .empty,
        title: "No cloud titles found",
        message: "Captured profile has no cloud titles in this preview state.",
        primaryActionTitle: "Refresh"
    )

    static var tileStates: [MediaTileViewState] {
        CloudLibraryHomeScenario.tileStates
    }
}

#if DEBUG
enum StratixPreviewFixtures {
    static let authFailureMessage = "Session expired. Sign in again to continue."

    static let deviceCodeInfo = DeviceCodeInfo(
        userCode: "ABCD-EFGH",
        verificationUri: "https://microsoft.com/link",
        verificationUriComplete: "https://microsoft.com/link?otc=ABCD-EFGH",
        expiresIn: 900,
        interval: 5,
        deviceCode: "preview-device-code"
    )
}

@MainActor
enum StratixPreviewStores {
    static func makeSettingsStore(
        profileName: String = "Stratix Preview",
        initialDestination: String = "home",
        initialSettingsCategory: String = "playback",
        configure: (SettingsStore) -> Void = { _ in }
    ) -> SettingsStore {
        let suiteName = "StratixPreviewStores.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        var shell = store.shell
        shell.profileName = profileName
        shell.lastDestinationRawValue = initialDestination
        shell.lastSettingsCategoryRawValue = initialSettingsCategory
        store.shell = shell

        configure(store)
        return store
    }

    static func makeCoordinator(settingsStore: SettingsStore) -> AppCoordinator {
        AppCoordinator(settingsStore: settingsStore)
    }
}

enum StratixShellPreviewFixtures {
    private static let referenceDate = ISO8601DateFormatter().date(from: "2026-03-06T12:00:00Z") ?? Date(timeIntervalSince1970: 1_772_798_400)

    static let sections: [CloudLibrarySection] = CloudLibraryPreviewData.cloudSections.map { section in
        CloudLibrarySection(
            id: section.id,
            name: section.name,
            items: section.items.map { item in
                CloudLibraryItem(
                    titleId: item.titleId,
                    productId: item.productId,
                    name: item.name,
                    shortDescription: item.shortDescription,
                    artURL: nil,
                    posterImageURL: nil,
                    heroImageURL: nil,
                    galleryImageURLs: [],
                    publisherName: item.publisherName,
                    attributes: item.attributes,
                    supportedInputTypes: item.supportedInputTypes,
                    isInMRU: item.isInMRU
                )
            }
        )
    }

    static let featuredItem: CloudLibraryItem = sections
        .flatMap(\.items)
        .first
        ?? CloudLibraryItem(
            titleId: "preview-home",
            productId: "preview-home",
            name: "Preview Home",
            shortDescription: "Fallback preview item",
            artURL: nil,
            posterImageURL: nil,
            heroImageURL: nil,
            galleryImageURLs: [],
            publisherName: "Stratix",
            attributes: [],
            supportedInputTypes: ["Controller"],
            isInMRU: true
        )

    static let secondaryItem: CloudLibraryItem = sections
        .flatMap(\.items)
        .dropFirst(3)
        .first
        ?? featuredItem

    static let detailItem: CloudLibraryItem = sections
        .flatMap(\.items)
        .first(where: { $0.name.localizedCaseInsensitiveContains("Cities") })
        ?? secondaryItem

    static let continuePlayingItem: CloudLibraryItem = sections
        .flatMap(\.items)
        .first(where: \.isInMRU)
        ?? featuredItem

    static let productDetails: [ProductID: CloudLibraryProductDetail] = {
        var map: [ProductID: CloudLibraryProductDetail] = [:]
        let entries: [(CloudLibraryItem, Bool)] = [
            (featuredItem, false),
            (secondaryItem, true),
            (detailItem, true),
            (continuePlayingItem, false)
        ]
        for (item, longCopy) in entries {
            let productID = ProductID(item.productId)
            guard map[productID] == nil else { continue }
            map[productID] = makeDetail(for: item, longCopy: longCopy)
        }
        return map
    }()

    static let achievementSnapshots: [String: TitleAchievementSnapshot] = {
        var map: [String: TitleAchievementSnapshot] = [:]
        let entries: [(CloudLibraryItem, Int, Int)] = [
            (featuredItem, 19, 52),
            (detailItem, 28, 40),
            (secondaryItem, 11, 32),
            (continuePlayingItem, 23, 44)
        ]
        for (item, unlocked, total) in entries where map[item.titleId] == nil {
            map[item.titleId] = makeAchievement(for: item, unlocked: unlocked, total: total)
        }
        return map
    }()

    static let profile = XboxCurrentUserProfile(
        xuid: "2533274900000001",
        gamertag: "stratix-preview",
        gameDisplayName: "Stratix Preview",
        gameDisplayPicRaw: nil,
        gamerscore: "24310"
    )

    static let presence = XboxCurrentUserPresence(
        xuid: "2533274900000001",
        state: "Online",
        devices: [
            XboxPresenceDevice(
                type: "Xbox Series X",
                titles: [
                    XboxPresenceTitle(id: featuredItem.titleId, name: featuredItem.name, placement: "Full", state: "Active")
                ]
            )
        ],
        lastSeen: XboxPresenceLastSeen(
            titleId: secondaryItem.titleId,
            titleName: secondaryItem.name,
            deviceType: "Cloud Gaming",
            timestamp: referenceDate.addingTimeInterval(-5_400)
        )
    )

    static let cachedFriends: [XboxSocialPerson] = [
        XboxSocialPerson(
            xuid: "281463100000001",
            gamertag: "pixelpilot",
            displayName: "Pixel Pilot",
            realName: nil,
            displayPicRaw: nil,
            gamerScore: "11840",
            presenceState: "Online",
            presenceText: "Playing \(featuredItem.name)",
            isFavorite: true,
            isFollowingCaller: true,
            isFollowedByCaller: true
        ),
        XboxSocialPerson(
            xuid: "281463100000002",
            gamertag: "nightdrive",
            displayName: "Night Drive",
            realName: nil,
            displayPicRaw: nil,
            gamerScore: "8740",
            presenceState: "Offline",
            presenceText: "Last seen in \(secondaryItem.name)",
            isFavorite: false,
            isFollowingCaller: true,
            isFollowedByCaller: false
        ),
        XboxSocialPerson(
            xuid: "281463100000003",
            gamertag: "coopcaptain",
            displayName: "Co-op Captain",
            realName: nil,
            displayPicRaw: nil,
            gamerScore: "15210",
            presenceState: "Online",
            presenceText: "Looking for group",
            isFavorite: true,
            isFollowingCaller: true,
            isFollowedByCaller: true
        )
    ]

    static let readyConsoles: [RemoteConsole] = decodeConsoles(
        """
        [
          {
            "deviceName": "Primary Series X",
            "serverId": "preview-console-seriesx",
            "powerState": "ConnectedStandby",
            "consoleType": "Xbox Series X",
            "playPath": "/consoles/preview-console-seriesx/play",
            "outOfHomeWarning": false,
            "wirelessWarning": false,
            "isDevKit": false
          },
          {
            "deviceName": "Secondary Series S",
            "serverId": "preview-console-seriess",
            "powerState": "On",
            "consoleType": "Xbox Series S",
            "playPath": "/consoles/preview-console-seriess/play",
            "outOfHomeWarning": false,
            "wirelessWarning": true,
            "isDevKit": false
          }
        ]
        """
    )

    private static func makeDetail(for item: CloudLibraryItem, longCopy: Bool) -> CloudLibraryProductDetail {
        let screenshotOne = previewFileURL("\(item.titleId)-screen-1.jpg")
        let screenshotTwo = previewFileURL("\(item.titleId)-screen-2.jpg")
        let trailerURL = previewFileURL("\(item.titleId)-trailer.mp4")
        let longDescription = longCopy
            ? "\(item.shortDescription ?? "Preview detail.") This preview intentionally uses longer copy so Canvas can expose line-wrapping, spacing, and metadata balance across the shell detail layout without needing live services."
            : item.shortDescription

        return CloudLibraryProductDetail(
            productId: item.productId,
            title: item.name,
            publisherName: item.publisherName,
            shortDescription: item.shortDescription,
            longDescription: longDescription,
            developerName: item.publisherName ?? "Preview Studio",
            releaseDate: "2026-03-06",
            capabilityLabels: item.attributes.map(\.localizedName),
            genreLabels: ["Action Adventure", "Cloud"],
            mediaAssets: [
                CloudLibraryMediaAsset(kind: .image, url: screenshotOne, priority: 0, source: .productDetails),
                CloudLibraryMediaAsset(kind: .image, url: screenshotTwo, priority: 1, source: .productDetails),
                CloudLibraryMediaAsset(
                    kind: .video,
                    url: trailerURL,
                    thumbnailURL: screenshotOne,
                    title: "Launch Trailer",
                    priority: 2,
                    source: .productDetails
                )
            ],
            galleryImageURLs: [screenshotOne, screenshotTwo],
            trailers: [
                CloudLibraryTrailer(title: "Launch Trailer", playbackURL: trailerURL, thumbnailURL: screenshotOne)
            ],
            achievementSummary: achievementSnapshots[item.titleId]?.summary
        )
    }

    private static func makeAchievement(for item: CloudLibraryItem, unlocked: Int, total: Int) -> TitleAchievementSnapshot {
        let summary = TitleAchievementSummary(
            titleId: item.titleId,
            titleName: item.name,
            totalAchievements: total,
            unlockedAchievements: unlocked,
            totalGamerscore: total * 20,
            unlockedGamerscore: unlocked * 20
        )
        return TitleAchievementSnapshot(
            titleId: item.titleId,
            summary: summary,
            achievements: [
                AchievementProgressItem(
                    id: "\(item.titleId)-1",
                    name: "Opening Move",
                    unlocked: true,
                    percentComplete: 100,
                    gamerscore: 15,
                    unlockedAt: referenceDate.addingTimeInterval(-86_400)
                ),
                AchievementProgressItem(id: "\(item.titleId)-2", name: "Deep Dive", unlocked: false, percentComplete: 54, gamerscore: 25, unlockedAt: nil),
                AchievementProgressItem(id: "\(item.titleId)-3", name: "Clean Sweep", unlocked: false, percentComplete: 12, gamerscore: 30, unlockedAt: nil)
            ]
        )
    }

    private static func previewFileURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    private static func decodeConsoles(_ json: String) -> [RemoteConsole] {
        let data = Data(json.utf8)
        return (try? JSONDecoder().decode([RemoteConsole].self, from: data)) ?? []
    }
}
#endif
