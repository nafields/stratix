// CloudLibraryHomeRailComponents.swift
// Defines cloud library home rail components for the CloudLibrary / Home surface.
//

import SwiftUI

struct HomeShowAllCardButton: View {
    let card: CloudLibraryHomeShowAllCardViewState
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onTap) {
            FocusAwareView { isFocused in
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: StratixTheme.Radius.md, style: .continuous)
                        .fill(backgroundFill(isFocused: isFocused))
                        .overlay(
                            RoundedRectangle(cornerRadius: StratixTheme.Radius.md, style: .continuous)
                                .stroke(borderColor(isFocused: isFocused), lineWidth: isFocused ? 2 : 1)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Show All", systemImage: "arrow.right.circle.fill")
                            .font(StratixTypography.rounded(26, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(.white)
                        Text(card.label)
                            .font(StratixTypography.rounded(16, weight: .semibold, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(Color.white.opacity(0.72))
                        Text("\(card.totalCount) games")
                            .font(StratixTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(Color.white.opacity(0.60))
                    }
                    .padding(22)
                }
                .frame(width: StratixTheme.Home.railTileWidth, height: StratixTheme.Home.railTileHeight)
                .scaleEffect(isFocused ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.13), value: isFocused)
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: StratixTheme.Radius.md)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
        .accessibilityIdentifier("home_show_all_\(card.alias)")
    }

    private func backgroundFill(isFocused: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isFocused ? 0.22 : 0.12),
                Color.white.opacity(isFocused ? 0.14 : 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func borderColor(isFocused: Bool) -> Color {
        isFocused ? StratixTheme.Colors.focusTint.opacity(0.92) : Color.white.opacity(0.20)
    }
}
