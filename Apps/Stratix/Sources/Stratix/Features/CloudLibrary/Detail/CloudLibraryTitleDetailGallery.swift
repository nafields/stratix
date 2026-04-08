// CloudLibraryTitleDetailGallery.swift
// Defines cloud library title detail gallery for the CloudLibrary / Detail surface.
//

import AVFoundation
import SwiftUI
import UIKit
#if canImport(CryptoKit)
import CryptoKit
#endif

extension CloudLibraryTitleDetailScreen {
    var gallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Gallery")
                .font(StratixTheme.Fonts.sectionTitle)
                .foregroundStyle(StratixTheme.Colors.textPrimary)

            if state.gallery.isEmpty && state.isHydrating {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            GalleryLoadingCardView()
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(state.gallery.enumerated()), id: \.element.id) { index, item in
                            GalleryThumbnailView(
                                item: item,
                                onSelect: {
                                    galleryPresentation = GalleryPresentation(
                                        mediaItems: state.gallery,
                                        initialIndex: index
                                    )
                                },
                                onMediaReady: {
                                    markMediaReady(galleryReadinessKey(for: item))
                                }
                            )
                            .focused($focusedGalleryIndex, equals: index)
                            .onMoveCommand { direction in
                                guard direction == .down else { return }
                                requestDetailPanelFocus()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .focusSection()
            }
        }
    }
}

private struct GalleryThumbnailView: View {
    let item: CloudLibraryGalleryItemViewState
    let onSelect: () -> Void
    let onMediaReady: () -> Void

    var body: some View {
        Button(action: onSelect) {
            FocusAwareView { isFocused in
                ZStack {
                    previewContent
                        .frame(width: 348, height: 196)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if item.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(StratixTheme.Colors.textPrimary)
                            .padding(22)
                            .background(Circle().fill(Color.black.opacity(0.58)))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 18)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.kind {
        case .image:
            CachedRemoteImage(
                url: item.mediaURL,
                kind: .gallery,
                maxPixelSize: 1_024,
                onImageLoaded: onMediaReady
            ) {
                LinearGradient(
                    colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .video:
            VideoThumbnailFrameView(
                videoURL: item.mediaURL,
                fallbackImageURL: item.thumbnailURL,
                onReady: onMediaReady
            )
        }
    }
}

private struct GalleryLoadingCardView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(StratixTheme.Colors.focusTint)
                    Text("Loading media")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.45)))
            )
        }
        .frame(width: 348, height: 196)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct VideoThumbnailFrameView: View {
    let videoURL: URL
    let fallbackImageURL: URL?
    let onReady: () -> Void

    @State private var frameImage: UIImage?

    var body: some View {
        Group {
            if let fallbackImageURL {
                CachedRemoteImage(
                    url: fallbackImageURL,
                    kind: .trailer,
                    maxPixelSize: 1_024,
                    onImageLoaded: onReady
                ) {
                    placeholder
                }
            } else if let frameImage {
                Image(uiImage: frameImage)
                    .resizable()
                    .scaledToFill()
                    .onAppear(perform: onReady)
            } else {
                placeholder
            }
        }
        .task(id: videoURL) {
            guard fallbackImageURL == nil else { return }
            await loadFrameImage()
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @MainActor
    private func loadFrameImage() async {
        if Task.isCancelled { return }
        if let cached = await VideoFrameThumbnailCache.shared.image(for: videoURL) {
            if Task.isCancelled { return }
            frameImage = cached
            return
        }

        let extracted = await VideoFrameExtractor.extractThumbnail(from: videoURL)
        if Task.isCancelled { return }
        guard let extracted else { return }

        await VideoFrameThumbnailCache.shared.setImage(extracted, for: videoURL)
        if Task.isCancelled { return }
        frameImage = extracted
    }
}

enum VideoFrameExtractor {
    static func extractThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let durationSeconds = await assetDurationSeconds(asset)
        let sampleSeconds = makeSampleSeconds(durationSeconds: durationSeconds)
        guard !sampleSeconds.isEmpty else { return nil }
        let minimumAcceptableTime = minimumAcceptedFrameSecond(durationSeconds: durationSeconds)

        return await Task.detached(priority: .utility) {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 720)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            for second in sampleSeconds {
                do {
                    let time = CMTime(seconds: second, preferredTimescale: 600)
                    let result = try await generator.image(at: time)
                    let actualSeconds = CMTimeGetSeconds(result.actualTime)

                    if actualSeconds.isFinite, second >= minimumAcceptableTime, actualSeconds < minimumAcceptableTime {
                        continue
                    }
                    return UIImage(cgImage: result.image)
                } catch {
                    continue
                }
            }
            return nil
        }
        .value
    }

    private static func assetDurationSeconds(_ asset: AVURLAsset) async -> Double? {
        if let loadedDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(loadedDuration)
            if seconds.isFinite, seconds > 0 {
                return seconds
            }
        }
        return nil
    }

    private static func makeSampleSeconds(durationSeconds: Double?) -> [Double] {
        var candidates: [Double] = []

        if let durationSeconds, durationSeconds > 1 {
            let maxSeek = max(0.8, durationSeconds - 0.5)
            let ratioSamples = [0.55, 0.72, 0.84, 0.42]
                .map { ratio in max(0.8, min(durationSeconds * ratio, maxSeek)) }
            candidates.append(contentsOf: ratioSamples)
            candidates.append(contentsOf: [28, 22, 18, 14, 10, 6, 3].map { max(0.8, min($0, maxSeek)) })
        } else {
            candidates.append(contentsOf: [22, 16, 12, 8, 5, 3])
        }

        var seen = Set<Int>()
        var unique: [Double] = []
        for second in candidates {
            let bucket = Int((second * 10).rounded())
            if seen.insert(bucket).inserted {
                unique.append(second)
            }
        }
        return unique
    }

    private static func minimumAcceptedFrameSecond(durationSeconds: Double?) -> Double {
        if let durationSeconds, durationSeconds > 0 {
            return max(2.0, min(9.0, durationSeconds * 0.18))
        }
        return 2.0
    }
}

actor VideoFrameThumbnailCache {
    static let shared = VideoFrameThumbnailCache()
    private static let algorithmVersion = "thumb-v3"

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let directoryURL: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directoryURL = caches.appendingPathComponent("stratix.videoFrameThumbs", isDirectory: true)
        cache.countLimit = 24
        cache.totalCostLimit = 48 * 1_024 * 1_024
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> UIImage? {
        let key = cacheKey(for: url)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let fileURL = fileURL(for: url)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: Self.imageCostBytes(image))
        return image
    }

    func setImage(_ image: UIImage, for url: URL) {
        let key = cacheKey(for: url)
        cache.setObject(image, forKey: key, cost: Self.imageCostBytes(image))
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: fileURL(for: url), options: .atomic)
    }

    private func cacheKey(for url: URL) -> NSString {
        "\(Self.algorithmVersion)|\(url.absoluteString)" as NSString
    }

    private func fileURL(for url: URL) -> URL {
        directoryURL.appendingPathComponent("\(hash(for: cacheKey(for: url) as String)).jpg")
    }

    private func hash(for value: String) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "\(value.hashValue)"
        return String(encoded.prefix(120))
        #endif
    }

    private static func imageCostBytes(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
