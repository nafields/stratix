// ShellUITestHarnessFixtures.swift
// Defines shell ui test harness fixtures for the Integration / UITestHarness surface.
//

import Foundation
import StratixModels

@MainActor
enum ShellUITestHarnessFixtures {
    static let profileName = "Stratix Preview"
    static let gamertag = "stratix.preview"
    static let gamerscore = "24310"
    static let profileImageURL: URL? = nil
    static let presenceState = "Online"
    static let featuredItemName = CloudLibraryPreviewData.cloudSections.flatMap(\.items).first?.name ?? "Preview Home"
    static let cloudLibraryCount = CloudLibraryPreviewData.cloudSections.flatMap(\.items).count
    static let consoleCount = 2
    static let friendsCount = 3

    static var homeState: CloudLibraryHomeViewState {
        let base = CloudLibraryPreviewData.home
        let hasContinueBadge = base.sections.contains { section in
            section.items.contains { item in
                if case .title(let titleItem) = item {
                    return titleItem.tile.badgeText != nil
                }
                return false
            }
        }
        let firstSection = base.sections.first
        let firstTitleItem = firstSection?.items.compactMap { item -> CloudLibraryHomeTitleRailItemViewState? in
            if case .title(let titleItem) = item {
                return titleItem
            }
            return nil
        }.first
        guard !hasContinueBadge,
              let firstSection,
              let firstTitleItem else {
            return base
        }

        let patchedFirstItem = MediaTileViewState(
            id: firstTitleItem.tile.id,
            titleID: firstTitleItem.tile.titleID,
            title: firstTitleItem.tile.title,
            subtitle: firstTitleItem.tile.subtitle,
            caption: firstTitleItem.tile.caption ?? "Resume in cloud",
            artworkURL: firstTitleItem.tile.artworkURL,
            badgeText: "Continue",
            aspect: firstTitleItem.tile.aspect
        )
        var patchedSections = base.sections
        patchedSections[0] = CloudLibraryRailSectionViewState(
            id: firstSection.id,
            alias: firstSection.alias,
            title: firstSection.title,
            subtitle: firstSection.subtitle,
            items: [
                .title(
                    CloudLibraryHomeTitleRailItemViewState(
                        id: firstTitleItem.id,
                        tile: patchedFirstItem,
                        action: firstTitleItem.action
                    )
                )
            ] + Array(firstSection.items.dropFirst())
        )
        return CloudLibraryHomeViewState(
            heroBackgroundURL: base.heroBackgroundURL,
            carouselItems: base.carouselItems,
            sections: patchedSections
        )
    }

    static var libraryState: CloudLibraryLibraryViewState {
        CloudLibraryPreviewData.library
    }

    static var homeTileLookup: [TitleID: CloudLibraryHomeScreen.TileLookupEntry] {
        var lookup: [TitleID: CloudLibraryHomeScreen.TileLookupEntry] = [:]
        for section in homeState.sections {
            for item in section.items {
                if case .title(let titleItem) = item {
                    lookup[titleItem.tile.titleID] = .init(
                        sectionID: section.id,
                        tile: titleItem.tile,
                        titleID: titleItem.tile.titleID
                    )
                }
            }
        }
        return lookup
    }

    static var libraryTileLookup: [TitleID: MediaTileViewState] {
        Dictionary(
            uniqueKeysWithValues: libraryState.gridItems.map {
                ($0.titleID, $0)
            }
        )
    }

    static func detailState(for tile: MediaTileViewState) -> CloudLibraryTitleDetailViewState {
        CloudLibraryPreviewData.cloudItems.first(where: { $0.titleId == tile.titleID.rawValue })
            .map { item in
                CloudLibraryTitleDetailViewState(
                    id: "uitest-\(item.titleId)",
                    title: item.name,
                    subtitle: item.publisherName,
                    heroImageURL: item.heroImageURL,
                    posterImageURL: item.posterImageURL,
                    ratingText: "UI Test",
                    legalText: nil,
                    descriptionText: item.shortDescription,
                    primaryAction: .init(id: "play", title: "Play", systemImage: "play.fill", style: .primary),
                    secondaryActions: [],
                    capabilityChips: [],
                    gallery: [],
                    achievementSummary: nil,
                    achievementItems: [],
                    achievementErrorText: nil,
                    detailPanels: [
                        .init(id: "about", title: "About", body: item.shortDescription ?? item.name)
                    ]
                )
            } ?? CloudLibraryPreviewData.detail
    }
}
