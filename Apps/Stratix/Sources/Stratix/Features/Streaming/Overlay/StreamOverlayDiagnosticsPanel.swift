// StreamOverlayDiagnosticsPanel.swift
// Defines stream overlay diagnostics panel for the Streaming / Overlay surface.
//

import SwiftUI
import StratixModels
import StreamingCore

/// Shows the in-stream diagnostics panel with game info, achievements, stats, and actions.
struct StreamOverlayDetailsPanel: View {
    let session: any StreamingSessionFacade
    let surfaceModel: StreamSurfaceModel
    let overlayState: StreamOverlayState
    let onCloseOverlay: () -> Void
    let onDisconnect: () -> Void
    @FocusState var focusedTarget: StreamOverlayState.FocusTarget?

    /// Renders the detail panel and keeps the requested focus target synchronized.
    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()

            HStack {
                GlassCard(
                    cornerRadius: 30,
                    fill: Color.black.opacity(0.84),
                    stroke: Color.white.opacity(0.12),
                    shadowOpacity: 0.34
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, 26)
                            .padding(.top, 22)
                            .padding(.bottom, 18)

                        divider

                        VStack(alignment: .leading, spacing: 16) {
                            gameInfoCard
                            achievementsCard
                            statsCard
                            shortcutRow
                            disconnectRow
                        }
                        .padding(20)
                    }
                    .frame(width: 760, alignment: .topLeading)
                }
                .padding(.leading, 34)
                .padding(.top, 22)
                .padding(.bottom, 22)

                Spacer(minLength: 0)
            }
        }
        .background {
            Button(action: onCloseOverlay) {
                Color.clear
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .accessibilityLabel("Close overlay")
        }
        .onAppear {
            syncFocus(using: overlayState.focusTarget)
        }
        .onChange(of: overlayState.focusTarget, initial: true) { _, nextFocusTarget in
            syncFocus(using: nextFocusTarget)
        }
    }

    /// Renders the panel header with artwork, status, and metadata pills.
    var header: some View {
        HStack(alignment: .top, spacing: 16) {
            overlayArtwork
                .frame(width: 180, height: 102)

            VStack(alignment: .leading, spacing: 8) {
                Text(overlayState.overlayInfo.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Circle()
                        .fill(overlayState.lifecycle.overlayStateColor)
                        .frame(width: 10, height: 10)
                    Text(overlayState.overlayInfo.subtitle)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textSecondary)
                        .lineLimit(1)
                    Text("•")
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                    Text(overlayState.lifecycle.overlayStateLabel)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .lineLimit(1)
                }

                if !overlayState.overlayInfo.metadataPills.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(overlayState.overlayInfo.metadataPills.enumerated()), id: \.offset) { _, text in
                                pill(text)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            closeGlyph
        }
    }

    /// Renders the game-information card for the current stream item.
    var gameInfoCard: some View {
        infoCard(title: "Game Information", systemImage: "gamecontroller.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text(overlayState.overlayInfo.description ?? "No additional game details are available yet.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                HStack(spacing: 12) {
                    Text("Stream")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .textCase(.uppercase)
                    Text(overlayState.lifecycle.overlayStateLabel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Renders the achievement summary card when achievement data is available.
    var achievementsCard: some View {
        infoCard(title: "Achievements", systemImage: "rosette") {
            VStack(alignment: .leading, spacing: 10) {
                if let summary = overlayState.overlayInfo.achievementSummary {
                    Text("Unlocked \(summary.unlockedAchievements) / \(summary.totalAchievements) (\(summary.unlockPercent)%)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textPrimary)
                    if let unlockedScore = summary.unlockedGamerscore,
                       let totalScore = summary.totalGamerscore {
                        Text("Gamerscore: \(unlockedScore) / \(totalScore)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.textSecondary)
                    }
                }

                if !overlayState.overlayInfo.recentAchievements.isEmpty {
                    ForEach(overlayState.overlayInfo.recentAchievements.prefix(3)) { item in
                        Text(item.unlocked ? "Unlocked: \(item.name)" : "\(item.name)\(item.percentComplete.map { " (\($0)%)" } ?? "")")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                if let achievementDetail = overlayState.overlayInfo.achievementDetail, !achievementDetail.isEmpty {
                    Text(achievementDetail)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    /// Renders the artwork block or its gradient fallback.
    var overlayArtwork: some View {
        if let imageURL = overlayState.overlayInfo.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    artworkFallback
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        } else {
            artworkFallback
        }
    }

    /// Fallback artwork treatment used when the stream has no artwork URL.
    var artworkFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [StratixTheme.Colors.focusTint.opacity(0.9), StratixTheme.Colors.accent.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.85))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// Thin divider used to separate the header from the panel body.
    var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 24)
    }

    /// Shared card shell used by the detail panel sections.
    func infoCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(
            cornerRadius: 18,
            fill: Color.white.opacity(0.04),
            stroke: Color.white.opacity(0.08),
            shadowOpacity: 0.06
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(StratixTheme.Colors.focusTint)
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .textCase(.uppercase)
                }

                content()
            }
            .padding(16)
        }
    }

    /// Renders a compact metadata pill for the overlay header.
    func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(StratixTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    /// Moves focus to the requested overlay control when the test harness asks for it.
    private func syncFocus(using target: StreamOverlayState.FocusTarget?) {
        guard let target else {
            focusedTarget = nil
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard overlayState.showsDetailsPanel else { return }
            focusedTarget = target
        }
    }
}
