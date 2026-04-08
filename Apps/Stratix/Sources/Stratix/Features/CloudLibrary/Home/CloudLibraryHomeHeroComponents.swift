// CloudLibraryHomeHeroComponents.swift
// Defines cloud library home hero components for the CloudLibrary / Home surface.
//

import SwiftUI

struct CloudLibraryHomeHeroTitleInfoView: View {
    let item: CloudLibraryHomeCarouselItemViewState?
    let dynamicTypeSize: DynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Xbox Game Pass", systemImage: "xbox.logo")
                .font(StratixTypography.rounded(18, weight: .semibold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(Color.white.opacity(0.90))

            if let item {
                Text(item.title)
                    .font(StratixTypography.rounded(64, weight: .heavy, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(height: 156, alignment: .topLeading)
                    .frame(maxWidth: StratixTheme.Home.heroContentMaxWidth, alignment: .leading)
                    .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 3)

                HStack(alignment: .center, spacing: 16) {
                    HomeHeroRatingBadge(title: item.ratingBadgeText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.subtitle ?? " ")
                            .font(StratixTypography.rounded(22, weight: .semibold, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(1)

                        Text(item.categoryLabel ?? " ")
                            .font(StratixTypography.rounded(18, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(Color.white.opacity(0.64))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: StratixTheme.Home.heroMetadataHeight, alignment: .leading)
                .frame(maxWidth: StratixTheme.Home.heroContentMaxWidth, alignment: .leading)

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(StratixTypography.rounded(18, weight: .regular, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(height: StratixTheme.Home.heroDescriptionHeight, alignment: .topLeading)
                        .frame(maxWidth: StratixTheme.Home.heroDescriptionMaxWidth, alignment: .leading)
                } else {
                    Color.clear
                        .frame(height: StratixTheme.Home.heroDescriptionHeight)
                }
            } else {
                Text("No recently added titles available")
                    .font(StratixTypography.rounded(48, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(.white)
                    .frame(height: 156, alignment: .topLeading)
                    .frame(maxWidth: StratixTheme.Home.heroContentMaxWidth, alignment: .leading)

                Color.clear
                    .frame(height: StratixTheme.Home.heroMetadataHeight)

                Color.clear
                    .frame(height: StratixTheme.Home.heroDescriptionHeight)
            }
        }
        .frame(maxWidth: StratixTheme.Home.heroContentMaxWidth, alignment: .leading)
    }
}

struct CloudLibraryHomeCarouselDotsView: View {
    let carouselIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if totalCount > 1 {
                ForEach(0..<totalCount, id: \.self) { index in
                    Circle()
                        .fill(
                            index == carouselIndex
                                ? StratixTheme.Colors.focusTint
                                : Color.white.opacity(0.34)
                        )
                        .frame(width: 10, height: 10)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carousel page \(carouselIndex + 1) of \(totalCount)")
        .accessibilityIdentifier("home_carousel_page_dots")
    }
}

struct HomeHeroRatingBadge: View {
    let title: String?

    var body: some View {
        Group {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: 54, height: 54)
                    .opacity(0.0)
            }
        }
        .frame(width: 54, height: 54)
        .accessibilityHidden(true)
    }
}

struct CarouselCTAButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String?
    let systemImage: String
    let style: Style
    var expandWidth: Bool = false
    var accessibilityID: String? = nil
    var accessibilityLabel: String? = nil
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onTap) {
            FocusAwareView { isFocused in
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(StratixTypography.system(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))

                    if let title, !title.isEmpty {
                        Text(title)
                            .font(StratixTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    }
                }
                .foregroundStyle(style == .primary ? Color.black : Color.white)
                .padding(.horizontal, title == nil ? 18 : 26)
                .padding(.vertical, 13)
                .frame(maxWidth: expandWidth ? .infinity : nil)
                .frame(minWidth: title == nil ? 60 : nil)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            style == .primary
                                ? (isFocused ? StratixTheme.Colors.focusTint.opacity(0.90) : StratixTheme.Colors.focusTint)
                                : Color.white.opacity(isFocused ? 0.22 : 0.12)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            style == .primary ? Color.clear : Color.white.opacity(0.28),
                            lineWidth: 1.5
                        )
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.13), value: isFocused)
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 30)
                .zIndex(isFocused ? 10 : 0)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
        .accessibilityLabel(accessibilityLabel ?? title ?? "")
        .accessibilityIdentifier(accessibilityID ?? accessibilityLabel ?? title ?? systemImage)
    }
}
