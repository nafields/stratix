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
    @State var lastFocusedGalleryIndex: Int?
    @State var lastFocusedDetailPanelID: String?
    @State var readiness = CloudLibraryTitleDetailReadinessState()
    @State var readinessTimeoutTask: Task<Void, Never>?
    @FocusState var focusedGalleryIndex: Int?
    @FocusState var focusedDetailPanelID: String?
    @State var pendingFocusTask: Task<Void, Never>?

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
        Group {
            if interceptExitCommand {
                detailBase
                    .onExitCommand(perform: goBack)
            } else {
                detailBase
            }
        }
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
        .onChange(of: focusedGalleryIndex) { _, newValue in
            if let index = newValue {
                lastFocusedGalleryIndex = index
            }
        }
        .onChange(of: focusedDetailPanelID) { _, newValue in
            if let panelID = newValue {
                lastFocusedDetailPanelID = panelID
            }
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

    func requestGalleryFocus() {
        guard !state.gallery.isEmpty else { return }

        let targetIndex = state.gallery.indices.contains(lastFocusedGalleryIndex ?? -1)
            ? lastFocusedGalleryIndex ?? 0
            : 0
        scheduleFocusTask {
            focusedGalleryIndex = targetIndex
        }
    }

    func requestDetailPanelFocus() {
        guard !state.detailPanels.isEmpty else { return }

        let rememberedID = lastFocusedDetailPanelID
        let targetID = state.detailPanels.contains(where: { $0.id == rememberedID })
            ? rememberedID
            : state.detailPanels.first?.id
        guard let targetID else { return }

        scheduleFocusTask {
            focusedDetailPanelID = targetID
        }
    }

    private func scheduleFocusTask(_ updateFocus: @escaping @MainActor () -> Void) {
        pendingFocusTask?.cancel()
        pendingFocusTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            updateFocus()
        }
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
