// CloudLibraryTitleDetailScreen.swift
// Defines the cloud library title detail screen for the CloudLibrary / Detail surface.
//

import SwiftUI

struct CloudLibraryTitleDetailScreen: View, Equatable {
    struct GalleryPresentation: Identifiable {
        let id = UUID()
        let mediaItems: [CloudLibraryGalleryItemViewState]
        let initialIndex: Int
    }

    let state: CloudLibraryTitleDetailViewState
    let onPrimaryAction: () -> Void
    var onBack: (() -> Void)? = nil
    var onSecondaryAction: (CloudLibraryActionViewState) -> Void = { _ in }
    var showsAmbientBackground = true
    var showsHeroArtwork = true
    var usesOuterPadding = true
    var interceptExitCommand = true
    var onInitialMediaReady: (() -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @State var galleryPresentation: GalleryPresentation?
    @State var readiness = CloudLibraryTitleDetailReadinessState()
    @State var readinessTimeoutTask: Task<Void, Never>?
    @FocusState var focusedGalleryIndex: Int?
    @FocusState var focusedDetailPanelID: String?

    let heroHeight = StratixTheme.Detail.heroHeight
    let heroPosterWidth = StratixTheme.Detail.heroPosterWidth
    let heroPosterHeight = StratixTheme.Detail.heroPosterHeight

    nonisolated static func == (lhs: CloudLibraryTitleDetailScreen, rhs: CloudLibraryTitleDetailScreen) -> Bool {
        lhs.state == rhs.state &&
        lhs.showsAmbientBackground == rhs.showsAmbientBackground &&
        lhs.showsHeroArtwork == rhs.showsHeroArtwork &&
        lhs.usesOuterPadding == rhs.usesOuterPadding &&
        lhs.interceptExitCommand == rhs.interceptExitCommand
    }

    var body: some View {
        detailBase
            .onExitCommand(perform: exitCommandAction)
    }

    private var exitCommandAction: (() -> Void)? {
        guard interceptExitCommand else { return nil }
        return { goBack() }
    }

    private var detailBase: some View {
        Group {
            if showsAmbientBackground {
                ZStack {
                    CloudLibraryAmbientBackground(imageURL: nil)
                    contentScroll
                }
            } else {
                contentScroll
            }
        }
        .navigationTitle("")
        .fullScreenCover(item: $galleryPresentation) { presentation in
            GalleryFullscreenViewer(
                mediaItems: presentation.mediaItems,
                initialIndex: presentation.initialIndex
            )
        }
        .onAppear(perform: startInitialMediaReadinessGate)
        .task(id: state.id) {
            await prefetchTrailerThumbnails()
            startInitialMediaReadinessGate()
        }
        .onDisappear {
            readinessTimeoutTask?.cancel()
            readinessTimeoutTask = nil
        }
    }

    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StratixTheme.Detail.contentSectionSpacing) {
                heroHeader

                if !state.gallery.isEmpty || state.isHydrating {
                    gallerySection
                }

                if !state.detailPanels.isEmpty {
                    detailPanelsSection
                }
            }
            .padding(.horizontal, usesOuterPadding ? StratixTheme.Layout.outerPadding : 0)
            .padding(.top, usesOuterPadding ? StratixTheme.Detail.contentTopPadding : 0)
            .padding(.bottom, StratixTheme.Detail.contentBottomPadding)
            .gamePassOuterFrame()
        }
        .accessibilityIdentifier("route_detail_root")
        .scrollIndicators(.hidden)
    }

    private func goBack() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }
}

#if DEBUG
#Preview("CloudLibraryDetail Content", traits: .fixedLayout(width: 1920, height: 1080)) {
    NavigationStack {
        CloudLibraryTitleDetailScreen(
            state: CloudLibraryPreviewData.detail,
            onPrimaryAction: {}
        )
    }
}

#Preview("CloudLibraryDetail Long Title", traits: .fixedLayout(width: 1920, height: 1080)) {
    NavigationStack {
        CloudLibraryTitleDetailScreen(
            state: CloudLibraryPreviewData.detailLongTitle,
            onPrimaryAction: {}
        )
    }
}
#endif
