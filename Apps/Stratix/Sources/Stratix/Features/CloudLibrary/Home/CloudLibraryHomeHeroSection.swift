// CloudLibraryHomeHeroSection.swift
// Defines cloud library home hero section for the CloudLibrary / Home surface.
//

import SwiftUI

extension CloudLibraryHomeScreen {
    var heroSection: some View {
        ZStack(alignment: .topLeading) {
            carouselContainer
                .allowsHitTesting(false)
                .ignoresSafeArea()

            heroOverlay
        }
        .frame(maxWidth: .infinity)
        .frame(height: StratixTheme.Layout.heroHeight)
        .padding(.bottom, 236)
    }

    var carouselContainer: some View {
        ZStack(alignment: .topLeading) {
            carouselBackground
            sideGradient
            bottomGradient
        }
    }

    var heroOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                CloudLibraryHomeHeroTitleInfoView(
                    item: currentCarouselItem,
                    dynamicTypeSize: dynamicTypeSize
                )
                carouselButtons
                    .focusScope(heroButtonFocusNamespace)
                    .focusSection()
            }
            .padding(.leading, StratixTheme.Home.heroContentLeading)
            .padding(.trailing, StratixTheme.Home.heroContentTrailing)
            .padding(.top, StratixTheme.Home.heroContentVertical)

            Spacer(minLength: 0)

            CloudLibraryHomeCarouselDotsView(
                carouselIndex: carouselIndex,
                totalCount: state.carouselItems.count
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, StratixTheme.Home.heroDotsBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var carouselBackground: some View {
        Group {
            if let url = currentCarouselItem?.heroBackgroundURL ?? state.heroBackgroundURL {
                CachedRemoteImage(url: url, kind: .hero, maxPixelSize: 1_920) {
                    Color.black.opacity(0.6)
                }
            } else {
                Color.black.opacity(0.6)
            }
        }
        .offset(y: carouselArtworkVerticalOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    var sideGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.72), location: 0.0),
                .init(color: Color.black.opacity(0.46), location: 0.18),
                .init(color: Color.black.opacity(0.20), location: 0.44),
                .init(color: Color.clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var bottomGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color.clear, location: 0.0),
                .init(color: Color.black.opacity(0.24), location: 0.66),
                .init(color: Color.black.opacity(0.94), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var scrollContentFadeBackground: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: StratixTheme.Layout.heroHeight - scrollFadeHeight)

            LinearGradient(
                stops: [
                    .init(color: Color.clear, location: 0.0),
                    .init(color: Color.black.opacity(0.28), location: 0.38),
                    .init(color: Color.black.opacity(0.72), location: 0.78),
                    .init(color: Color.black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: scrollFadeHeight)

            Color.black
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    var carouselButtons: some View {
        HStack(spacing: 14) {
            CarouselCTAButton(title: "Play Now", systemImage: "play.fill", style: .primary, expandWidth: true) {
                if let item = currentCarouselItem {
                    onSelectCarouselPlay(item)
                }
            }
            .frame(width: StratixTheme.Layout.tileWidth)
            .accessibilityIdentifier("home_carousel_play")
            .focused($focusedTarget, equals: .carouselPlay)
            .prefersDefaultFocus(in: heroButtonFocusNamespace)
            .onMoveCommand(perform: handlePlayButtonMove)

            CarouselCTAButton(
                title: nil,
                systemImage: "info.circle",
                style: .secondary,
                accessibilityLabel: "Details"
            ) {
                if let item = currentCarouselItem {
                    onSelectCarouselDetails(item)
                }
            }
            .accessibilityIdentifier("home_carousel_details")
            .focused($focusedTarget, equals: .carouselDetails)
            .onMoveCommand(perform: handleDetailsButtonMove)
        }
    }
}
