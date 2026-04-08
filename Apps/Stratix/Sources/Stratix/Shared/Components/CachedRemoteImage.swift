// CachedRemoteImage.swift
// Defines cached remote image for the Shared / Components surface.
//

import SwiftUI
import UIKit
import StratixCore

/// Shared SwiftUI image view that bridges view-driven artwork identity to the actor-backed
/// remote image pipeline and only updates displayed artwork when the cache identity changes.
struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    var kind: ArtworkKind = .poster
    var priority: ArtworkPriority = .normal
    var maxPixelSize: CGFloat? = nil
    var contentMode: ContentMode = .fill
    var onImageLoaded: (() -> Void)? = nil
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var displayKey: String?

    init(
        url: URL?,
        kind: ArtworkKind = .poster,
        priority: ArtworkPriority = .normal,
        maxPixelSize: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        onImageLoaded: (() -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.kind = kind
        self.priority = priority
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.onImageLoaded = onImageLoaded
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .onAppear {
                        onImageLoaded?()
                    }
            } else {
                placeholder()
            }
        }
        .task(id: cacheIdentity) {
            await loadImage()
        }
    }

    /// Includes URL, artwork role, and decode-size hint so differently sized uses of the same
    /// remote asset do not trample each other's cached display state.
    private var cacheIdentity: String {
        "\(url?.absoluteString ?? "nil")|\(kind.rawValue)|\(maxPixelSize.map { String(Int($0)) } ?? "full")"
    }

    /// Clears stale displayed artwork before awaiting a replacement so reused SwiftUI cells do
    /// not briefly show the wrong remote image.
    private func loadImage() async {
        guard let url else {
            await MainActor.run {
                clearImage()
            }
            return
        }
        let cacheKey = cacheIdentity
        if let cached = await RemoteImagePipeline.shared.cachedImage(for: cacheKey) {
            await MainActor.run {
                displayImage(cached, for: cacheKey)
            }
            return
        }

        await MainActor.run {
            clearImageIfDisplayingDifferentKey(cacheKey)
        }

        guard let loaded = await RemoteImagePipeline.shared.image(
            for: ArtworkRequest(url: url, kind: kind, priority: priority),
            cacheKey: cacheKey,
            maxPixelSize: maxPixelSize
        ) else {
            return
        }

        await MainActor.run {
            displayImage(loaded, for: cacheKey)
        }
    }

    @MainActor
    private func clearImage() {
        image = nil
        displayKey = nil
    }

    @MainActor
    private func clearImageIfDisplayingDifferentKey(_ cacheKey: String) {
        guard displayKey != cacheKey else { return }
        image = nil
    }

    @MainActor
    private func displayImage(_ image: UIImage, for cacheKey: String) {
        self.image = image
        displayKey = cacheKey
    }
}
