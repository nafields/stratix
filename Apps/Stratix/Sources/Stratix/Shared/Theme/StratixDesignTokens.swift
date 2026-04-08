// StratixDesignTokens.swift
// Defines stratix design tokens for the Shared / Theme surface.
//

import SwiftUI

/// Central typography helpers that keep custom scaling behavior consistent across tvOS and
/// Dynamic Type sizes used by the Stratix design system.
enum StratixTypography {
    /// Applies the repo's rounded-system typography with the same Dynamic Type scaling curve
    /// used across shell, library, and detail surfaces.
    static func rounded(
        _ baseSize: CGFloat,
        weight: Font.Weight = .regular,
        dynamicTypeSize: DynamicTypeSize
    ) -> Font {
        .system(size: scaledSize(baseSize, for: dynamicTypeSize), weight: weight, design: .rounded)
    }

    /// Uses the shared Dynamic Type scaling curve for non-rounded system fonts as well.
    static func system(
        _ baseSize: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        dynamicTypeSize: DynamicTypeSize
    ) -> Font {
        .system(size: scaledSize(baseSize, for: dynamicTypeSize), weight: weight, design: design)
    }

    /// Maps tvOS Dynamic Type buckets onto the repo's fixed design-size scale.
    static func scaledSize(_ baseSize: CGFloat, for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let scale: CGFloat
        switch dynamicTypeSize {
        case .xSmall:
            scale = 0.90
        case .small:
            scale = 0.94
        case .medium:
            scale = 0.97
        case .large:
            scale = 1.00
        case .xLarge:
            scale = 1.12
        case .xxLarge:
            scale = 1.22
        case .xxxLarge:
            scale = 1.32
        case .accessibility1:
            scale = 1.40
        case .accessibility2:
            scale = 1.50
        case .accessibility3:
            scale = 1.60
        case .accessibility4:
            scale = 1.72
        case .accessibility5:
            scale = 1.84
        @unknown default:
            scale = 1.00
        }

        return round(baseSize * scale)
    }
}

/// Design-token namespace for shared spacing, sizing, color, and typography constants.
enum StratixTheme {
    enum Spacing {
        static let xxs: CGFloat = 6
        static let xs: CGFloat = 10
        static let sm: CGFloat = 14
        static let md: CGFloat = 20
        static let lg: CGFloat = 28
        static let xl: CGFloat = 40
        static let xxl: CGFloat = 56
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 24
        static let xl: CGFloat = 34
    }

    enum Layout {
        static let maxContentWidth: CGFloat = .greatestFiniteMagnitude
        static let outerPadding: CGFloat = 0
        static let sideRailTopInset: CGFloat = 75
        static let heroHeight: CGFloat = 650
        static let tileWidth: CGFloat = 236
        static let tileHeight: CGFloat = 324
    }

    enum Shell {
        static let contentTopPadding: CGFloat = 12
        static let contentBottomPadding: CGFloat = 18
        static let sideRailTopPadding: CGFloat = 10
        static let sideRailBottomPadding: CGFloat = 12
        static let sideRailInsetLeading: CGFloat = 0
        static let sideRailCollapsedPanelWidth: CGFloat = 188
        static let sideRailExpandedPanelWidth: CGFloat = 336
        static let contentGap: CGFloat = 0
        static let contentLeadingInset: CGFloat = 0
        static let browseRouteLeadingInset: CGFloat = 156
    }

    enum SideRail {
        static let railCollapsedWidth: CGFloat = 92
        static let railExpandedWidth: CGFloat = 242
        static let panelCollapsedWidth: CGFloat = 188
        static let panelExpandedWidth: CGFloat = 336
        static let iconSize: CGFloat = 22
        static let labelSize: CGFloat = 38
        static let rowHeight: CGFloat = 56
        static let verticalPadding: CGFloat = 18
        static let horizontalPadding: CGFloat = 10
        static let rowSpacing: CGFloat = 8
    }

    enum Home {
        static let sectionSpacing: CGFloat = 44
        static let tileFocusScale: CGFloat = 1.12
        static let tileFocusBreathing: CGFloat = 18
        static let railEdgeFocusInset: CGFloat = 0
        static let railHorizontalPadding: CGFloat = 92
        static let railTopPadding: CGFloat = 0
        static let sectionHeaderHorizontalPadding: CGFloat = 132
        static let heroArtworkLeadingBleed: CGFloat = -188
        static let heroArtworkTrailingBleed: CGFloat = -24
        static let heroContentLeading: CGFloat = 136
        static let heroContentTrailing: CGFloat = 136
        static let heroContentVertical: CGFloat = 336
        static let heroActionTopPadding: CGFloat = 8
        static let heroContentMaxWidth: CGFloat = 760
        static let heroDescriptionMaxWidth: CGFloat = 620
        static let heroMetadataHeight: CGFloat = 44
        static let heroDescriptionHeight: CGFloat = 120
        static let heroDotsBottomInset: CGFloat = 88
        static let heroRailOverlap: CGFloat = 116
        static let railTileWidth: CGFloat = 248
        static let railTileHeight: CGFloat = 340
    }

    enum Library {
        static let sectionSpacing: CGFloat = 24
        static let gridItemWidth: CGFloat = 252
        static let gridItemSpacing: CGFloat = 22
        static let gridEdgeFocusInset: CGFloat = 16
        static let chipHorizontalPadding: CGFloat = 14
        static let chipVerticalPadding: CGFloat = 10
    }

    enum Search {
        static let sectionSpacing: CGFloat = 24
        static let contentTopPadding: CGFloat = 8
        static let gridItemWidth: CGFloat = 252
        static let gridItemSpacing: CGFloat = 22
        static let gridHorizontalPadding: CGFloat = 16
    }

    enum Detail {
        static let heroHeight: CGFloat = 600
        static let heroPosterWidth: CGFloat = 338
        static let heroPosterHeight: CGFloat = 507
        static let contentSectionSpacing: CGFloat = 28
        static let contentTopPadding: CGFloat = 36
        static let contentBottomPadding: CGFloat = 40
        static let heroSideInset: CGFloat = 25
        static let heroInnerPadding: CGFloat = 24
        static let heroInterItemSpacing: CGFloat = 20
    }

    enum Colors {
        static let bgTop = Color(red: 0.03, green: 0.06, blue: 0.08)
        static let bgBottom = Color(red: 0.01, green: 0.02, blue: 0.03)
        static let glassFill = Color.white.opacity(0.07)
        static let glassStroke = Color.white.opacity(0.16)
        static let elevatedGlass = Color(red: 0.08, green: 0.12, blue: 0.14).opacity(0.76)
        static let panelFill = Color.black.opacity(0.34)
        static let focusTint = Color(red: 0.72, green: 0.95, blue: 0.34)
        static let accent = Color(red: 0.36, green: 0.82, blue: 0.33)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.75)
        static let textMuted = Color.white.opacity(0.55)
        static let warning = Color.orange
    }

    enum Fonts {
        static let shellTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let nav = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let heroTitle = Font.system(size: 48, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 30, weight: .bold, design: .rounded)
        static let detailTitle = Font.system(size: 50, weight: .heavy, design: .rounded)
        static let cardTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
    }
}
