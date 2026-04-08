// CloudLibraryTitleDetailFullscreenMedia.swift
// Defines cloud library title detail fullscreen media for the CloudLibrary / Detail surface.
//

import AVKit
import SwiftUI
import UIKit

struct GalleryFullscreenViewer: View {
    let mediaItems: [CloudLibraryGalleryItemViewState]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @FocusState private var gallerySurfaceFocused: Bool

    init(mediaItems: [CloudLibraryGalleryItemViewState], initialIndex: Int) {
        self.mediaItems = mediaItems
        let maxIndex = max(mediaItems.count - 1, 0)
        _selection = State(initialValue: min(max(initialIndex, 0), maxIndex))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()

            if !mediaItems.isEmpty {
                TabView(selection: $selection) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                        ZStack {
                            Color.black.ignoresSafeArea()

                            switch item.kind {
                            case .image:
                                CachedRemoteImage(url: item.mediaURL, kind: .gallery, maxPixelSize: 1_920, contentMode: .fit) {
                                    ProgressView()
                                        .controlSize(.large)
                                        .tint(StratixTheme.Colors.focusTint)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 90)
                                .padding(.vertical, 80)
                            case .video:
                                TrailerVideoSurface(
                                    streamURL: item.mediaURL,
                                    posterURL: item.thumbnailURL,
                                    isActive: selection == index
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 90)
                                .padding(.vertical, 80)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }

            if !mediaItems.isEmpty {
                Text("\(selection + 1) / \(mediaItems.count)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .padding(.trailing, 34)
                    .padding(.bottom, 34)
            }
        }
        .overlay {
            Color.clear
                .focusable(true)
                .focused($gallerySurfaceFocused)
                .gamePassDisableSystemFocusEffect()
        }
        .onExitCommand {
            dismiss()
        }
        .onMoveCommand(perform: handleMoveCommand)
        .onAppear {
            gallerySurfaceFocused = true
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard !mediaItems.isEmpty else { return }

        switch direction {
        case .left:
            selection = max(selection - 1, 0)
        case .right:
            selection = min(selection + 1, mediaItems.count - 1)
        default:
            break
        }
    }
}

private struct TrailerVideoSurface: View {
    let streamURL: URL
    let posterURL: URL?
    let isActive: Bool

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let posterURL {
                CachedRemoteImage(url: posterURL, kind: .trailer, maxPixelSize: 1_920, contentMode: .fit) {
                    Color.black
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let player {
                TrailerInlinePlayerView(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(StratixTheme.Colors.focusTint)
            }
        }
        .background(Color.black)
        .onAppear {
            configurePlayerIfNeeded()
            updatePlaybackState()
        }
        .onDisappear {
            player?.pause()
        }
        .onChange(of: isActive) { _, _ in
            updatePlaybackState()
        }
    }

    private func configurePlayerIfNeeded() {
        guard player == nil else { return }

        let player = AVPlayer(url: streamURL)
        player.actionAtItemEnd = .pause
        self.player = player

        if isActive {
            player.seek(to: .zero)
            player.play()
        }
    }

    private func updatePlaybackState() {
        guard let player else { return }

        if isActive {
            player.seek(to: .zero)
            player.play()
        } else {
            player.pause()
        }
    }
}

private struct TrailerInlinePlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TrailerPlayerContainerView {
        let view = TrailerPlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: TrailerPlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class TrailerPlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
