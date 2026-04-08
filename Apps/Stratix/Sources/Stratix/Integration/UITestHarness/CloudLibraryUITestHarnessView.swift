// CloudLibraryUITestHarnessView.swift
// Defines the cloud library ui test harness view used in the Integration / UITestHarness surface.
//

import SwiftUI

struct CloudLibraryUITestHarnessView: View {
    @State private var selectedTile: MediaTileViewState?
    @State private var autoDetailScheduled = false

    private var homeState: CloudLibraryHomeViewState {
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

    private var detailState: CloudLibraryTitleDetailViewState {
        guard let selectedTile else {
            return CloudLibraryPreviewData.detail
        }

        return CloudLibraryPreviewData.cloudItems.first(where: { $0.titleId == selectedTile.titleID.rawValue })
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

    private var continueBadgeCount: Int {
        homeState.sections
            .flatMap(\.items)
            .filter { item in
                if case .title(let titleItem) = item {
                    return titleItem.tile.badgeText != nil
                }
                return false
            }
            .count
    }

    var body: some View {
        Group {
            if selectedTile == nil {
                ZStack(alignment: .topTrailing) {
                    CloudLibraryHomeScreen(
                        state: homeState,
                        onSelectRailItem: { item in
                            if case .title(let titleItem) = item {
                                selectedTile = titleItem.tile
                            }
                        },
                        onSelectCarouselPlay: { item in
                            selectedTile = MediaTileViewState(
                                id: item.id,
                                titleID: item.titleID,
                                title: item.title,
                                subtitle: item.subtitle,
                                caption: nil,
                                artworkURL: item.artworkURL,
                                badgeText: nil,
                                aspect: .portrait
                            )
                        },
                        onSelectCarouselDetails: { item in
                            selectedTile = MediaTileViewState(
                                id: item.id,
                                titleID: item.titleID,
                                title: item.title,
                                subtitle: item.subtitle,
                                caption: nil,
                                artworkURL: item.artworkURL,
                                badgeText: nil,
                                aspect: .portrait
                            )
                        }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("gamepass_home_screen")

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                if let fallbackTile = homeState.sections.first?.items.compactMap({ item -> MediaTileViewState? in
                                    if case .title(let titleItem) = item {
                                        return titleItem.tile
                                    }
                                    return nil
                                }).first {
                                    selectedTile = fallbackTile
                                }
                            } label: {
                                Text("Open Detail (UI Test) [\(continueBadgeCount)]")
                                    .font(.system(size: 18, weight: .bold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.black.opacity(0.7), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("gamepass_open_detail_button")
                        }
                    }
                    .padding(28)
                }
                .onAppear {
                    guard StratixLaunchMode.isGamePassHomeAutoDetailUITestEnabled else { return }
                    guard !autoDetailScheduled else { return }
                    autoDetailScheduled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        guard selectedTile == nil else { return }
                        if let fallbackTile = homeState.sections.first?.items.compactMap({ item -> MediaTileViewState? in
                            if case .title(let titleItem) = item {
                                return titleItem.tile
                            }
                            return nil
                        }).first {
                            selectedTile = fallbackTile
                        }
                    }
                }
            } else {
                ZStack(alignment: .topTrailing) {
                    CloudLibraryTitleDetailScreen(
                        state: detailState,
                        onPrimaryAction: {},
                        onBack: {
                            selectedTile = nil
                        },
                        onSecondaryAction: { _ in },
                        showsAmbientBackground: false,
                        showsHeroArtwork: true,
                        usesOuterPadding: true,
                        interceptExitCommand: false
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("gamepass_detail_screen")
                }
            }
        }
    }
}
