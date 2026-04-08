// StreamOverlay.swift
// Defines stream overlay for the Streaming / Overlay surface.
//

import SwiftUI
import StratixModels
import StreamingCore
import XCloudAPI

/// Describes the stream overlay content for the current cloud or home session.
struct StreamOverlayInfo: Sendable, Equatable {
    let title: String
    let subtitle: String
    let description: String?
    let imageURL: URL?
    let metadataPills: [String]
    let achievementSummary: TitleAchievementSummary?
    let recentAchievements: [AchievementProgressItem]
    let achievementDetail: String?

    /// Builds overlay metadata for an xHome session from the selected console.
    static func home(console: RemoteConsole) -> Self {
        let type = console.consoleType.isEmpty ? "Xbox" : console.consoleType
        let power = console.powerState.isEmpty ? "Unknown power" : console.powerState
        return Self(
            title: console.deviceName,
            subtitle: "Remote Play",
            description: "Streaming from your console. Current game metadata is not yet available for xHome sessions.",
            imageURL: nil,
            metadataPills: [type, power],
            achievementSummary: nil,
            recentAchievements: [],
            achievementDetail: "Achievements are not available for xHome streams yet."
        )
    }

    /// Builds overlay metadata for an xCloud session from the selected catalog item.
    static func cloud(
        item: CloudLibraryItem?,
        heroOverride: URL? = nil,
        achievementSnapshot: TitleAchievementSnapshot? = nil,
        achievementErrorText: String? = nil
    ) -> Self {
        guard let item else {
            return Self(
                title: "Cloud Stream",
                subtitle: "Xbox Cloud Gaming",
                description: "Game metadata is loading.",
                imageURL: nil,
                metadataPills: [],
                achievementSummary: achievementSnapshot?.summary,
                recentAchievements: achievementSnapshot?.achievements ?? [],
                achievementDetail: achievementErrorText ?? "Achievements are loading."
            )
        }

        var pills: [String] = []
        if let publisher = item.publisherName, !publisher.isEmpty {
            pills.append(publisher)
        }
        pills.append(contentsOf: item.attributes.prefix(2).map(\.localizedName))

        return Self(
            title: item.name,
            subtitle: "Xbox Cloud Gaming",
            description: item.shortDescription,
            imageURL: heroOverride ?? item.heroImageURL ?? item.posterImageURL ?? item.artURL,
            metadataPills: pills,
            achievementSummary: achievementSnapshot?.summary,
            recentAchievements: achievementSnapshot?.achievements ?? [],
            achievementDetail: achievementErrorText
        )
    }
}

#if DEBUG
private struct StreamStatusOverlayPreviewHost: View {
    @State private var session = StreamingSession(
        apiClient: XCloudAPIClient(baseHost: "example.com", gsToken: "preview"),
        bridge: MockWebRTCBridge()
    )
    @State private var surfaceModel = StreamSurfaceModel()
    @State private var showOverlay = true
    @State private var lifecycle: StreamLifecycleState = .connected

    var body: some View {
        ZStack {
            Color.black
            StreamStatusOverlay(
                overlayState: StreamOverlayState(
                    lifecycle: lifecycle,
                    overlayInfo: StreamOverlayInfo.cloud(item: nil),
                    overlayVisible: showOverlay,
                    hasSession: true
                ),
                session: session,
                surfaceModel: surfaceModel,
                onCloseOverlay: { showOverlay = false },
                onDisconnect: {}
            )
        }
    }
}

#Preview("StreamStatusOverlay", traits: .fixedLayout(width: 1920, height: 1080)) {
    StreamStatusOverlayPreviewHost()
}
#endif
