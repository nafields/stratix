// MediaTileView.swift
// Defines the media tile view used in the Shared / Components surface.
//

import SwiftUI

func recordMediaTileMoveDirection(_ direction: MoveCommandDirection) {
    // Intentionally no-op: motion comes from native tvOS focus/parallax behavior.
}

/// Shared game/media tile used across library, home, and search surfaces with custom artwork,
/// badge, and focus rendering.
struct MediaTileView: View {
    let state: MediaTileViewState
    let onSelect: () -> Void
    /// Allows specific callers to override the environment focus state when they need a
    /// deterministic visual focus treatment during routing or restoration.
    var forcedFocus: Bool? = nil
    var presentation: MediaTilePresentation = .standard
    var artworkOverrideSize: CGSize? = nil

    private let focusScale: CGFloat = 1.0
    private let titleBlockHeight: CGFloat = 46
    private let subtitleBlockHeight: CGFloat = 22

    var body: some View {
        Button(action: onSelect) {
            FocusAwareView { labelFocused in
                let activeFocus = forcedFocus ?? labelFocused

                VStack(alignment: .leading, spacing: 12) {
                    artworkView(activeFocus: activeFocus)

                    if presentation == .standard {
                        titleBlock(activeFocus: activeFocus)
                    }
                }
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
        .accessibilityIdentifier("game_tile_\(state.titleID.rawValue)")
        .accessibilityLabel(Text(state.title))
        .accessibilityValue(Text(state.badgeText ?? state.caption ?? ""))
    }

    /// Selects the standard portrait tile sizing or wider landscape presentation based on tile aspect.
    private var artworkSize: CGSize {
        if let artworkOverrideSize {
            return artworkOverrideSize
        }
        switch state.aspect {
        case .portrait:
            return CGSize(width: StratixTheme.Layout.tileWidth, height: StratixTheme.Layout.tileHeight)
        case .landscape:
            return CGSize(width: 360, height: 202)
        }
    }

    /// Builds the artwork surface and overlays the badge/focus treatment shared by all tile variants.
    private func artworkView(activeFocus: Bool) -> some View {
        let artwork = CachedRemoteImage(
            url: state.artworkURL,
            kind: state.aspect == .portrait ? .poster : .hero,
            maxPixelSize: state.aspect == .portrait ? 900 : 1_280
        ) {
            ZStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.28))
            }
        }
        .frame(width: artworkSize.width, height: artworkSize.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: StratixTheme.Radius.md, style: .continuous))
        .overlay(alignment: .topLeading) {
            if presentation == .standard, let badge = state.badgeText {
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(StratixTheme.Colors.focusTint))
                    .padding(10)
                    .accessibilityLabel(Text(badge))
                    .accessibilityIdentifier("game_tile_badge_\(state.titleID.rawValue)")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: StratixTheme.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(activeFocus ? 0.22 : 0.10), lineWidth: 1)
        )
        .opacity(activeFocus ? 1.0 : 0.90)
        .saturation(activeFocus ? 1.0 : 0.88)

        let focusRing = ZStack {
            RoundedRectangle(cornerRadius: StratixTheme.Radius.md + 4, style: .continuous)
                .stroke(activeFocus ? StratixTheme.Colors.focusTint.opacity(0.9) : Color.clear, lineWidth: activeFocus ? 2.6 : 0)

            RoundedRectangle(cornerRadius: StratixTheme.Radius.md + 4, style: .continuous)
                .stroke(activeFocus ? Color.white.opacity(0.9) : Color.clear, lineWidth: activeFocus ? 1.0 : 0)
        }
        .padding(-5)
        .allowsHitTesting(false)

        return ZStack {
            artwork
            focusRing
        }
        .frame(width: artworkSize.width, height: artworkSize.height)
        .scaleEffect(activeFocus ? focusScale : 1.0)
    }

    /// Keeps title, subtitle, and caption heights stable so rows do not jump as focus changes.
    private func titleBlock(activeFocus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(activeFocus ? Color.white : Color.white.opacity(0.92))
                .lineLimit(2)
                .frame(width: artworkSize.width, height: titleBlockHeight, alignment: .topLeading)

            if let subtitle = state.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(activeFocus ? 0.72 : 0.52))
                    .lineLimit(1)
                    .frame(width: artworkSize.width, height: subtitleBlockHeight, alignment: .topLeading)
            } else {
                Color.clear
                    .frame(width: artworkSize.width, height: subtitleBlockHeight)
            }

            if let caption = state.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(activeFocus ? 0.52 : 0.36))
                    .lineLimit(1)
                    .frame(width: artworkSize.width, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
    }
}

#if DEBUG
#Preview("MediaTileView", traits: .fixedLayout(width: 920, height: 620)) {
    ZStack {
        Color.black
        HStack(spacing: 24) {
            MediaTileView(state: CloudLibraryPreviewData.tileStates[0], onSelect: {})
            MediaTileView(state: CloudLibraryPreviewData.tileStates[1], onSelect: {}, forcedFocus: true)
        }
        .padding(60)
    }
}
#endif
