// PreviewExportService.swift
// Defines preview export service.
//

import Foundation
import StratixModels
import XCloudAPI

// MARK: - PreviewExportSource

/// Data contract for preview fixture export.
@MainActor
protocol PreviewExportSource: AnyObject {
    var previewExportAuthStateDescription: String { get }
    var previewExportCurrentTokens: StreamTokens? { get }
    var previewExportProfile: XboxCurrentUserProfile? { get }
    var previewExportPresence: XboxCurrentUserPresence? { get }
    var previewExportSocialPeople: [XboxSocialPerson] { get }
    var previewExportSocialPeopleTotalCount: Int { get }
    var previewExportCloudLibrarySections: [CloudLibrarySection] { get }
    var previewExportConsoles: [RemoteConsole] { get }
    var previewExportSettingsStore: SettingsStore { get }
    var previewExportLastAuthError: String? { get }
    var previewExportLastCloudLibraryError: String? { get }
    var previewExportLastPresenceReadError: String? { get }
    var previewExportLastPresenceWriteError: String? { get }
    var previewExportLastSocialError: String? { get }
    var previewExportIsLoadingCloudLibrary: Bool { get }
    var previewExportIsLoadingConsoles: Bool { get }
    var previewExportIsStreaming: Bool { get }
    var previewExportCloudLibraryNeedsReauth: Bool { get }

    func refreshPreviewExportData() async
}

// MARK: - PreviewExportService

/// Assembles and writes a one-shot JSON snapshot of live user/game data for building preview fixtures.
/// `PreviewExportController` delegates export work here via `PreviewExportSource`.
@MainActor
public final class PreviewExportService {
    public init() {}

    /// Export a preview dump from the given source.
    /// Returns the URL of the written file.
    @discardableResult
    func exportPreviewDump(
        source: any PreviewExportSource,
        refreshBeforeExport: Bool
    ) async throws -> URL {
        if refreshBeforeExport {
            await source.refreshPreviewExportData()
        }

        let snapshot = makePreviewDataDumpSnapshot(source: source)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        return try writePreviewDump(data: data)
    }

    /// Write raw preview data to the PreviewDumps directory and return the output URL.
    public func writePreviewDump(data: Data) throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dumpsDirectory = baseDirectory.appendingPathComponent("PreviewDumps", isDirectory: true)
        try fileManager.createDirectory(at: dumpsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let timestamp = formatter.string(from: Date())
        let outputURL = dumpsDirectory.appendingPathComponent("GreenlightPreviewDump-\(timestamp).json")
        try data.write(to: outputURL, options: [.atomic])

        let latestURL = dumpsDirectory.appendingPathComponent("GreenlightPreviewDump-latest.json")
        try? data.write(to: latestURL, options: [.atomic])
        return outputURL
    }

    // MARK: - Snapshot assembly

    private func makePreviewDataDumpSnapshot(source: any PreviewExportSource) -> PreviewDataDumpSnapshot {
        let tokens = source.previewExportCurrentTokens
        let profile = source.previewExportProfile
        let presence = source.previewExportPresence

        return PreviewDataDumpSnapshot(
            generatedAt: Date(),
            app: PreviewDumpAppSnapshot(
                authState: source.previewExportAuthStateDescription,
                xhomeHost: tokens?.xhomeHost ?? "",
                xcloudHost: tokens?.xcloudHost,
                isLoadingCloudLibrary: source.previewExportIsLoadingCloudLibrary,
                isLoadingConsoles: source.previewExportIsLoadingConsoles,
                isStreaming: source.previewExportIsStreaming,
                cloudLibraryNeedsReauth: source.previewExportCloudLibraryNeedsReauth
            ),
            profile: profile.map {
                PreviewDumpProfileSnapshot(
                    xuid: $0.xuid,
                    gamertag: $0.gamertag,
                    gameDisplayName: $0.gameDisplayName,
                    gameDisplayPicRaw: $0.gameDisplayPicRaw?.absoluteString,
                    gamerscore: $0.gamerscore
                )
            },
            presence: presence.map {
                PreviewDumpPresenceSnapshot(
                    xuid: $0.xuid,
                    state: $0.state,
                    activeTitleName: $0.activeTitleName,
                    lastSeen: $0.lastSeen.map {
                        PreviewDumpPresenceLastSeenSnapshot(
                            titleId: $0.titleId,
                            titleName: $0.titleName,
                            deviceType: $0.deviceType,
                            timestamp: $0.timestamp
                        )
                    },
                    devices: $0.devices.map { device in
                        PreviewDumpPresenceDeviceSnapshot(
                            type: device.type,
                            titles: device.titles.map { title in
                                PreviewDumpPresenceTitleSnapshot(
                                    id: title.id,
                                    name: title.name,
                                    placement: title.placement,
                                    state: title.state
                                )
                            }
                        )
                    }
                )
            },
            social: PreviewDumpSocialSnapshot(
                totalCount: source.previewExportSocialPeopleTotalCount,
                people: source.previewExportSocialPeople.map { person in
                    PreviewDumpSocialPersonSnapshot(
                        xuid: person.xuid,
                        preferredName: person.preferredName,
                        gamertag: person.gamertag,
                        displayName: person.displayName,
                        realName: person.realName,
                        displayPicRaw: person.displayPicRaw?.absoluteString,
                        gamerScore: person.gamerScore,
                        presenceState: person.presenceState,
                        presenceText: person.presenceText,
                        isFavorite: person.isFavorite,
                        isFollowingCaller: person.isFollowingCaller,
                        isFollowedByCaller: person.isFollowedByCaller
                    )
                }
            ),
            cloudLibrary: source.previewExportCloudLibrarySections.map { section in
                PreviewDumpCloudSectionSnapshot(
                    id: section.id,
                    name: section.name,
                    items: section.items.map { item in
                        PreviewDumpCloudItemSnapshot(
                            titleId: item.titleId,
                            productId: item.productId,
                            name: item.name,
                            shortDescription: item.shortDescription,
                            artURL: item.artURL?.absoluteString,
                            posterImageURL: item.posterImageURL?.absoluteString,
                            heroImageURL: item.heroImageURL?.absoluteString,
                            publisherName: item.publisherName,
                            supportedInputTypes: item.supportedInputTypes,
                            isInMRU: item.isInMRU,
                            attributes: item.attributes.map {
                                PreviewDumpCloudAttributeSnapshot(
                                    name: $0.name,
                                    localizedName: $0.localizedName
                                )
                            }
                        )
                    }
                )
            },
            consoles: source.previewExportConsoles.map {
                PreviewDumpConsoleSnapshot(
                    deviceName: $0.deviceName,
                    serverId: $0.serverId,
                    powerState: $0.powerState,
                    consoleType: $0.consoleType,
                    playPath: $0.playPath,
                    outOfHomeWarning: $0.outOfHomeWarning,
                    wirelessWarning: $0.wirelessWarning,
                    isDevKit: $0.isDevKit
                )
            },
            guideSettings: PreviewDumpGuideSettingsSnapshot(
                streamQuality: source.previewExportSettingsStore.stream.qualityPreset,
                codecPreference: source.previewExportSettingsStore.stream.codecPreference,
                clientProfileOSName: source.previewExportSettingsStore.stream.clientProfileOSName,
                preferredResolution: source.previewExportSettingsStore.stream.preferredResolution,
                preferredFPS: source.previewExportSettingsStore.stream.preferredFPS,
                bitrateCapMbps: source.previewExportSettingsStore.stream.bitrateCapMbps,
                hdrEnabled: source.previewExportSettingsStore.stream.hdrEnabled,
                lowLatencyMode: source.previewExportSettingsStore.stream.lowLatencyMode,
                showStreamStats: source.previewExportSettingsStore.stream.showStreamStats,
                reduceMotion: source.previewExportSettingsStore.accessibility.reduceMotion,
                largeText: source.previewExportSettingsStore.accessibility.largeText,
                autoReconnect: source.previewExportSettingsStore.stream.autoReconnect,
                packetLossProtection: source.previewExportSettingsStore.stream.packetLossProtection
            ),
            errors: PreviewDumpErrorSnapshot(
                auth: source.previewExportLastAuthError,
                cloudLibrary: source.previewExportLastCloudLibraryError,
                presenceRead: source.previewExportLastPresenceReadError,
                presenceWrite: source.previewExportLastPresenceWriteError,
                social: source.previewExportLastSocialError
            )
        )
    }
}

// MARK: - Snapshot types

private struct PreviewDataDumpSnapshot: Codable {
    let generatedAt: Date
    let app: PreviewDumpAppSnapshot
    let profile: PreviewDumpProfileSnapshot?
    let presence: PreviewDumpPresenceSnapshot?
    let social: PreviewDumpSocialSnapshot
    let cloudLibrary: [PreviewDumpCloudSectionSnapshot]
    let consoles: [PreviewDumpConsoleSnapshot]
    let guideSettings: PreviewDumpGuideSettingsSnapshot
    let errors: PreviewDumpErrorSnapshot
}

private struct PreviewDumpAppSnapshot: Codable {
    let authState: String
    let xhomeHost: String
    let xcloudHost: String?
    let isLoadingCloudLibrary: Bool
    let isLoadingConsoles: Bool
    let isStreaming: Bool
    let cloudLibraryNeedsReauth: Bool
}

private struct PreviewDumpProfileSnapshot: Codable {
    let xuid: String?
    let gamertag: String?
    let gameDisplayName: String?
    let gameDisplayPicRaw: String?
    let gamerscore: String?
}

private struct PreviewDumpPresenceSnapshot: Codable {
    let xuid: String?
    let state: String
    let activeTitleName: String?
    let lastSeen: PreviewDumpPresenceLastSeenSnapshot?
    let devices: [PreviewDumpPresenceDeviceSnapshot]
}

private struct PreviewDumpPresenceLastSeenSnapshot: Codable {
    let titleId: String?
    let titleName: String?
    let deviceType: String?
    let timestamp: Date?
}

private struct PreviewDumpPresenceDeviceSnapshot: Codable {
    let type: String?
    let titles: [PreviewDumpPresenceTitleSnapshot]
}

private struct PreviewDumpPresenceTitleSnapshot: Codable {
    let id: String?
    let name: String?
    let placement: String?
    let state: String?
}

private struct PreviewDumpSocialSnapshot: Codable {
    let totalCount: Int
    let people: [PreviewDumpSocialPersonSnapshot]
}

private struct PreviewDumpSocialPersonSnapshot: Codable {
    let xuid: String
    let preferredName: String
    let gamertag: String?
    let displayName: String?
    let realName: String?
    let displayPicRaw: String?
    let gamerScore: String?
    let presenceState: String?
    let presenceText: String?
    let isFavorite: Bool
    let isFollowingCaller: Bool
    let isFollowedByCaller: Bool
}

private struct PreviewDumpCloudSectionSnapshot: Codable {
    let id: String
    let name: String
    let items: [PreviewDumpCloudItemSnapshot]
}

private struct PreviewDumpCloudItemSnapshot: Codable {
    let titleId: String
    let productId: String
    let name: String
    let shortDescription: String?
    let artURL: String?
    let posterImageURL: String?
    let heroImageURL: String?
    let publisherName: String?
    let supportedInputTypes: [String]
    let isInMRU: Bool
    let attributes: [PreviewDumpCloudAttributeSnapshot]
}

private struct PreviewDumpCloudAttributeSnapshot: Codable {
    let name: String
    let localizedName: String
}

private struct PreviewDumpConsoleSnapshot: Codable {
    let deviceName: String
    let serverId: String
    let powerState: String
    let consoleType: String
    let playPath: String
    let outOfHomeWarning: Bool
    let wirelessWarning: Bool
    let isDevKit: Bool
}

private struct PreviewDumpGuideSettingsSnapshot: Codable {
    let streamQuality: String
    let codecPreference: String
    let clientProfileOSName: String
    let preferredResolution: String
    let preferredFPS: String
    let bitrateCapMbps: Double
    let hdrEnabled: Bool
    let lowLatencyMode: Bool
    let showStreamStats: Bool
    let reduceMotion: Bool
    let largeText: Bool
    let autoReconnect: Bool
    let packetLossProtection: Bool
}

private struct PreviewDumpErrorSnapshot: Codable {
    let auth: String?
    let cloudLibrary: String?
    let presenceRead: String?
    let presenceWrite: String?
    let social: String?
}
