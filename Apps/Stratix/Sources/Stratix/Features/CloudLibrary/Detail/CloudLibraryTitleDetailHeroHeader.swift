// CloudLibraryTitleDetailHeroHeader.swift
// Defines cloud library title detail hero header for the CloudLibrary / Detail surface.
//

import SwiftUI

extension CloudLibraryTitleDetailScreen {
    var heroHeader: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let sideInset = StratixTheme.Detail.heroSideInset
            let innerPadding = StratixTheme.Detail.heroInnerPadding
            let panelWidth = width
            let interItemSpacing = StratixTheme.Detail.heroInterItemSpacing
            let textMaxWidth = max(panelWidth - (innerPadding * 2) - heroPosterWidth - interItemSpacing, 360)

            ZStack(alignment: .topLeading) {
                if showsHeroArtwork {
                    heroArtwork(width: width, containerMinY: proxy.frame(in: .global).minY, proxy: proxy)
                } else {
                    Color.clear
                        .frame(width: width, height: heroHeight)
                }

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .frame(width: panelWidth, height: heroHeight)
                    .padding(.leading, sideInset)

                heroInfo(panelWidth: panelWidth, textMaxWidth: textMaxWidth)
                    .frame(width: panelWidth, height: heroHeight, alignment: .topLeading)
                    .padding(.leading, sideInset + innerPadding)
                    .padding(.trailing, innerPadding)
                    .padding(.vertical, 50)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: heroHeight)
    }

    func inlineActionBar(maxWidth: CGFloat) -> some View {
        Group {
            if !allActions.isEmpty {
                ActionButtonBar(actions: allActions, onSelect: handle)
                    .frame(maxWidth: maxWidth, alignment: .leading)
            }
        }
    }

    var allActions: [CloudLibraryActionViewState] {
        [state.primaryAction]
    }

    func handle(_ action: CloudLibraryActionViewState) {
        guard action.id != state.primaryAction.id else {
            onPrimaryAction()
            return
        }
        onSecondaryAction(action)
    }

    func heroInfo(panelWidth: CGFloat, textMaxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 22) {
                poster

                VStack(alignment: .leading, spacing: 12) {
                    if let contextLabel = state.contextLabel, !contextLabel.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(contextLabel)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                    }

                    Text(state.title)
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: textMaxWidth, alignment: .leading)

                    if let subtitle = state.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.textSecondary)
                            .lineLimit(2)
                            .frame(maxWidth: textMaxWidth, alignment: .leading)
                    }

                    if let descriptionText = state.descriptionText, !descriptionText.isEmpty {
                        Text(descriptionText)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.textSecondary)
                            .lineLimit(3)
                            .frame(maxWidth: textMaxWidth, alignment: .leading)
                    }

                    if !state.capabilityChips.isEmpty {
                        ChipGroupView(chips: state.capabilityChips)
                            .frame(width: textMaxWidth, alignment: .leading)
                    }

                    if let gallerySummaryText {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 13, weight: .bold))
                            Text(gallerySummaryText)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                    }

                    if let achievementSummaryText {
                        HStack(spacing: 10) {
                            Image(systemName: "rosette")
                                .font(.system(size: 13, weight: .bold))
                            Text(achievementSummaryText)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                    }

                    ratingPanel
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(maxWidth: min(max(panelWidth - 60, 420), 560), alignment: .leading)
                        .padding(.top, 2)

                    inlineActionBar(maxWidth: textMaxWidth)
                        .padding(.top, 6)
                }
                .layoutPriority(1)
                .frame(maxWidth: textMaxWidth, alignment: .leading)
            }
        }
        .focusSection()
    }

    var poster: some View {
        let posterURL = state.posterImageURL ?? state.heroImageURL

        return CachedRemoteImage(
            url: posterURL,
            kind: .poster,
            maxPixelSize: 900,
            onImageLoaded: {
                if let posterURL {
                    markMediaReady(mediaReadinessKey(.poster(posterURL)))
                }
            }
        ) {
            ZStack {
                Color.white.opacity(0.08)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(StratixTheme.Colors.textMuted)
            }
        }
        .frame(width: heroPosterWidth, height: heroPosterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    func heroArtwork(width: CGFloat, containerMinY: CGFloat, proxy: GeometryProxy) -> some View {
        let heroURL = state.heroImageURL ?? state.posterImageURL
        let expectedShellTopInset = StratixTheme.Layout.sideRailTopInset + 10
        let measuredInset = max(0, containerMinY)
        let viewportOffsetY = min(measuredInset, expectedShellTopInset + 8)
        let viewportHeight = max(proxy.size.height, heroHeight + viewportOffsetY + 1)

        return CachedRemoteImage(
            url: heroURL,
            kind: .hero,
            maxPixelSize: 1_920,
            onImageLoaded: {
                if let heroURL {
                    markMediaReady(mediaReadinessKey(.hero(heroURL)))
                }
            }
        ) {
            LinearGradient(
                colors: [
                    StratixTheme.Colors.bgTop.opacity(0.96),
                    StratixTheme.Colors.bgBottom.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: width, height: viewportHeight)
        .offset(y: -viewportOffsetY)
        .frame(width: width, height: heroHeight)
        .background(StratixTheme.Colors.bgBottom)
        .clipped()
        .ignoresSafeArea()
        .overlay(
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.62), location: 0.0),
                        .init(color: Color.black.opacity(0.34), location: 0.44),
                        .init(color: Color.black.opacity(0.30), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.48), location: 0.0),
                        .init(color: Color.black.opacity(0.26), location: 0.22),
                        .init(color: Color.black.opacity(0.34), location: 0.62),
                        .init(color: Color.black.opacity(0.74), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.0),
                        .init(color: StratixTheme.Colors.bgBottom.opacity(0.40), location: 0.68),
                        .init(color: StratixTheme.Colors.bgBottom.opacity(0.90), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }

    var ratingPanel: some View {
        GlassCard(cornerRadius: 20, fill: Color.black.opacity(0.34), stroke: Color.white.opacity(0.12), shadowOpacity: 0.15) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rating & info")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)

                if let rating = state.ratingText, !rating.isEmpty {
                    Text(rating)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.focusTint)
                }

                if let legal = state.legalText, !legal.isEmpty {
                    Text(legal)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var gallerySummaryText: String? {
        let screenshotCount = state.gallery.filter { $0.kind == .image }.count
        let trailerCount = state.gallery.filter { $0.kind == .video }.count
        var parts: [String] = []

        if screenshotCount > 0 {
            parts.append("\(screenshotCount) screenshot\(screenshotCount == 1 ? "" : "s")")
        }
        if trailerCount > 0 {
            parts.append("\(trailerCount) trailer\(trailerCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var achievementSummaryText: String? {
        if let summary = state.achievementSummary {
            return "\(summary.unlockedAchievements)/\(summary.totalAchievements) achievements • \(summary.unlockPercent)%"
        }
        if let error = state.achievementErrorText, !error.isEmpty {
            return error
        }
        return nil
    }
}
