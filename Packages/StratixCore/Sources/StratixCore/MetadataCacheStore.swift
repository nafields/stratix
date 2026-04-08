// MetadataCacheStore.swift
// Defines the metadata cache store.
//

import Foundation

enum MetadataCacheStore {
    private static let directoryName = "stratix"
    typealias FileExists = @Sendable (String) -> Bool
    typealias CreateDirectory = @Sendable (URL) throws -> Void
    typealias MoveItem = @Sendable (URL, URL) throws -> Void
    typealias CopyItem = @Sendable (URL, URL) throws -> Void

    static func url(for filename: String) -> URL {
        let appSupport = appSupportDirectory()
        return resolvedURL(
            for: filename,
            appSupportDirectory: appSupport,
            legacyDirectory: cachesDirectory(),
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
            copyItem: { try FileManager.default.copyItem(at: $0, to: $1) }
        )
    }

    static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func legacyURL(for filename: String) -> URL {
        cachesDirectory().appendingPathComponent(filename)
    }

    private static func cachesDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static func resolvedURL(
        for filename: String,
        appSupportDirectory: URL,
        legacyDirectory: URL,
        fileExists: FileExists,
        createDirectory: CreateDirectory,
        moveItem: MoveItem,
        copyItem: CopyItem
    ) -> URL {
        let target = appSupportDirectory.appendingPathComponent(filename)
        if fileExists(target.path) {
            return target
        }

        let legacy = legacyDirectory.appendingPathComponent(filename)
        guard fileExists(legacy.path) else {
            return target
        }

        try? createDirectory(appSupportDirectory)
        do {
            try moveItem(legacy, target)
        } catch {
            guard !fileExists(target.path) else {
                return target
            }
            try? copyItem(legacy, target)
        }
        return target
    }
}
