// XboxComProductDetailsParsingSupport.swift
// Provides shared support for xbox com product details parsing.
//

import Foundation

extension XboxComProductDetailsClient {
    static func dictionaryArray(from raw: Any?) -> [[String: Any]] {
        guard let raw else { return [] }
        if let dict = raw as? [String: Any] {
            let nestedDictionaries = dict.values.flatMap(extractNestedDictionaries)
            if !nestedDictionaries.isEmpty { return nestedDictionaries }
            return [dict]
        }
        if let array = raw as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    static func firstURL(keys: [String], in dictionaries: [[String: Any]]) -> URL? {
        for dict in dictionaries {
            for key in keys {
                guard let raw = value(forKey: key, in: dict), let string = asTrimmedString(raw) else { continue }
                if let url = normalizedURL(from: string) {
                    return url
                }
            }
        }
        return nil
    }

    static func videoPriority(for key: String) -> Int {
        let lower = key.lowercased()
        if lower.contains("launch") { return 0 }
        if lower.contains("trailer") { return 1 }
        if lower.contains("video") { return 2 }
        return 3
    }

    static func collectStringValues(
        from dictionaries: [[String: Any]],
        containerKeyFragments: [String],
        labelKeys: [String]
    ) -> [String] {
        var values: [String] = []

        for dict in dictionaries {
            for (key, value) in dict where keyContains(key, fragments: containerKeyFragments) {
                values.append(contentsOf: parseLabeledValues(value, labelKeys: labelKeys))
            }
        }

        return deduplicatedStrings(values)
    }

    static func parseLabeledValues(_ value: Any, labelKeys: [String]) -> [String] {
        if let string = asTrimmedString(value) {
            return [string]
        }

        if let array = value as? [Any] {
            return deduplicatedStrings(array.flatMap { parseLabeledValues($0, labelKeys: labelKeys) })
        }

        if let dict = value as? [String: Any] {
            if let label = firstString(keys: labelKeys, in: [dict]) {
                return [label]
            }
            let nested = dict.values.flatMap { parseLabeledValues($0, labelKeys: labelKeys) }
            return deduplicatedStrings(nested)
        }

        return []
    }

    static func firstString(keys: [String], in dictionaries: [[String: Any]]) -> String? {
        for dict in dictionaries {
            for key in keys {
                guard let raw = value(forKey: key, in: dict), let string = asTrimmedString(raw) else { continue }
                return string
            }
        }
        return nil
    }

    static func value(forKey key: String, in dict: [String: Any]) -> Any? {
        if let exact = dict[key] {
            return exact
        }
        return dict.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
    }

    static func asTrimmedString(_ raw: Any?) -> String? {
        switch raw {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    static func allDictionaries(in root: Any) -> [[String: Any]] {
        var dictionaries: [[String: Any]] = []
        func walk(_ value: Any, depth: Int) {
            guard depth <= 40 else { return }
            if let dict = value as? [String: Any] {
                dictionaries.append(dict)
                for nested in dict.values {
                    walk(nested, depth: depth + 1)
                }
                return
            }
            if let array = value as? [Any] {
                for nested in array {
                    walk(nested, depth: depth + 1)
                }
            }
        }
        walk(root, depth: 0)
        return dictionaries
    }

    static func urlFields(in dict: [String: Any]) -> [(key: String, url: URL)] {
        var urlFields: [(String, URL)] = []
        for (key, value) in dict {
            guard let string = asTrimmedString(value), let url = normalizedURL(from: string) else { continue }
            urlFields.append((key, url))
        }
        return urlFields
    }

    static func normalizedURL(from raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return URL(string: value)
        }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        return nil
    }

    static func shouldTreatAsVideo(key: String, url: URL) -> Bool {
        isVideoURL(url)
            || keyContains(key, fragments: ["video", "trailer", "movie", "clip", "stream", "playback", "manifest", "mp4"])
    }

    static func shouldTreatAsImage(key: String, url: URL, purpose: String?) -> Bool {
        if shouldTreatAsVideo(key: key, url: url) { return false }
        if keyContains(key, fragments: ["logo", "icon", "wordmark", "brand"]) {
            return false
        }
        if let purpose, keyContains(purpose, fragments: ["logo", "icon", "wordmark", "brand"]) {
            return false
        }
        if isImageURL(url) { return true }
        if keyContains(key, fragments: ["image", "screenshot", "poster", "hero", "tile", "thumbnail", "background", "art"]) {
            return true
        }
        if let purpose, keyContains(purpose, fragments: ["image", "screenshot", "poster", "hero", "tile", "thumbnail", "background", "art"]) {
            return true
        }
        return false
    }

    static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return true }
        let value = url.absoluteString.lowercased()
        if value.contains(".jpg")
            || value.contains(".jpeg")
            || value.contains(".png")
            || value.contains(".webp") {
            return true
        }
        if let host = url.host?.lowercased(),
           host.contains("store-images.s-microsoft.com"),
           url.path.lowercased().hasPrefix("/image/") {
            return true
        }
        return false
    }

    static func isVideoURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return true }
        let value = url.absoluteString.lowercased()
        return value.contains(".m3u8")
            || value.contains(".mp4")
            || value.contains(".webm")
            || value.contains("manifest")
    }

    static func imagePurposePriority(_ purpose: String?) -> Int {
        let value = (purpose ?? "").lowercased()
        if value.contains("screenshot") { return 0 }
        if value.contains("gallery") { return 1 }
        if value.contains("hero") || value.contains("background") { return 2 }
        if value.contains("poster") || value.contains("box") { return 3 }
        if value.contains("tile") { return 4 }
        if value.contains("thumbnail") { return 5 }
        return 6
    }

    static func keyContains(_ key: String, fragments: [String]) -> Bool {
        let lower = key.lowercased()
        return fragments.contains { fragment in
            lower.contains(fragment.lowercased())
        }
    }

    static func deduplicatedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueValues: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                uniqueValues.append(trimmed)
            }
        }
        return uniqueValues
    }

    static func isLikelyGameplayScreenshotAsset(url: URL, purpose: String?, key: String) -> Bool {
        let probe = "\(key) \(purpose ?? "") \(url.absoluteString)".lowercased()
        let includes = ["screenshot", "screen", "shot", "gallery", "still", "gameplay", "ingame"]
        let excludes = [
            "xboxgamepass", "gamepass", "esrb", "pegi", "rating",
            "logo", "wordmark", "icon", "brand", "badge",
            "cover", "poster", "tile", "hero", "keyart", "boxart",
            "capsule", "banner", "splash", "placeholder", "watermark"
        ]
        if excludes.contains(where: { probe.contains($0) }) {
            return false
        }
        if includes.contains(where: { probe.contains($0) }) {
            return true
        }
        if let purpose, keyContains(purpose, fragments: ["image", "media", "asset", "feature"]) {
            return true
        }
        if keyContains(key, fragments: ["image", "media", "asset"]) {
            return true
        }
        return false
    }

    static func isLikelyVideoThumbnailAsset(url: URL, purpose: String?, key: String) -> Bool {
        let probe = "\(key) \(purpose ?? "") \(url.absoluteString)".lowercased()
        let includes = ["thumb", "thumbnail", "poster", "preview", "still", "frame", "splash", "art", "image"]
        let excludes = ["logo", "wordmark", "icon", "brand", "badge", "watermark", "rating", "esrb", "pegi"]
        if excludes.contains(where: { probe.contains($0) }) {
            return false
        }
        if includes.contains(where: { probe.contains($0) }) {
            return true
        }
        return isImageURL(url)
    }

    static func makeCorrelationVector() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let prefix = String(raw.prefix(22))
        return "\(prefix).1"
    }

    private static func extractNestedDictionaries(from value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            return [dictionary]
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif", "bmp", "avif"
    ]

    static let videoExtensions: Set<String> = [
        "mp4", "m3u8", "webm", "mov", "m4v", "avi"
    ]
}
