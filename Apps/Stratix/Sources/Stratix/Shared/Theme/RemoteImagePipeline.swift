// RemoteImagePipeline.swift
// Defines remote image pipeline for the Shared / Theme surface.
//

import UIKit
import ImageIO
import StratixCore
import OSLog
import os.signpost

/// Actor-backed shared artwork loader that deduplicates in-flight requests and keeps a decoded
/// UIImage cache for the SwiftUI image views layered on top of it.
actor RemoteImagePipeline {
    static let shared = RemoteImagePipeline()
    private static let perfLogger = Logger(subsystem: "com.stratix.app", category: "CloudLibraryPerf")
    private static let perfSignpostLog = OSLog(subsystem: "com.stratix.app", category: "CloudLibraryPerf")

    private let decodedCache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        decodedCache.countLimit = 160
        decodedCache.totalCostLimit = 192 * 1_024 * 1_024
    }

    /// Returns a previously decoded image without starting any new network or decode work.
    func cachedImage(for key: String) -> UIImage? {
        decodedCache.object(forKey: key as NSString)
    }

    /// Resolves one artwork request through the decoded cache, in-flight dedupe map, and
    /// fetch/decode pipeline in that order.
    func image(
        for request: ArtworkRequest,
        cacheKey: String,
        maxPixelSize: CGFloat?
    ) async -> UIImage? {
        let signpostID: OSSignpostID? = {
            #if DEBUG
            return OSSignpostID(log: Self.perfSignpostLog)
            #else
            return nil
            #endif
        }()
        #if DEBUG
        if let signpostID {
            os_signpost(
                .begin,
                log: Self.perfSignpostLog,
                name: "ArtworkRequest",
                signpostID: signpostID,
                "kind=%{public}s url=%{public}s",
                request.kind.rawValue,
                request.url.absoluteString
            )
        }
        #endif
        var source = "miss"
        defer {
            #if DEBUG
            if let signpostID {
                os_signpost(
                    .end,
                    log: Self.perfSignpostLog,
                    name: "ArtworkRequest",
                    signpostID: signpostID,
                    "kind=%{public}s url=%{public}s source=%{public}s",
                    request.kind.rawValue,
                    request.url.absoluteString,
                    source
                )
            }
            #endif
        }
        if let cached = decodedCache.object(forKey: cacheKey as NSString) {
            source = "decoded_cache"
            #if DEBUG
            Self.perfLogger.log("artwork_ready source=decoded_cache kind=\(request.kind.rawValue, privacy: .public) url=\(request.url.absoluteString, privacy: .public)")
            #endif
            return cached
        }
        if let task = inFlight[cacheKey] {
            let image = await task.value
            source = image == nil ? "inflight_miss" : "inflight_hit"
            return image
        }

        let task = Task<UIImage?, Never>(priority: Self.taskPriority(for: request.priority)) {
            await Self.fetchImage(request: request, maxPixelSize: maxPixelSize)
        }
        inFlight[cacheKey] = task
        let image = await task.value
        inFlight[cacheKey] = nil

        if let image {
            decodedCache.setObject(
                image,
                forKey: cacheKey as NSString,
                cost: Self.imageCostBytes(image)
            )
            source = "shared_pipeline"
        } else {
            source = "pipeline_miss"
        }
        return image
    }

    private static func fetchImage(request: ArtworkRequest, maxPixelSize: CGFloat?) async -> UIImage? {
        guard let response = try? await ArtworkPipeline.shared.data(for: request) else {
            return nil
        }
        return decodeImage(from: response.data, maxPixelSize: maxPixelSize)
    }

    /// Applies thumbnail decoding when a pixel-size hint exists so large hero/poster assets
    /// do not always inflate to full source size in memory.
    private static func decodeImage(from data: Data, maxPixelSize: CGFloat?) -> UIImage? {
        if let maxPixelSize,
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldCache: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage)
            }
        }

        return UIImage(data: data)
    }

    private static func imageCostBytes(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private static func taskPriority(for priority: ArtworkPriority) -> TaskPriority {
        switch priority {
        case .low:
            return .utility
        case .normal:
            return .userInitiated
        case .high, .immediate:
            return .high
        }
    }
}
