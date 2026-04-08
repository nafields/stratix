// CloudLibraryViewState.swift
// Defines the cloud library view state.
//

import Foundation
import StratixModels

/// Identifies the primary side-rail destinations that map onto browse routes.
enum SideRailNavID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case library
    case search
    case consoles

    var id: String { rawValue }
}

/// Identifies the utility overlays that can sit above the browse shell.
enum ShellUtilityRoute: String, Identifiable, Hashable, Sendable {
    case profile
    case settings

    var id: String { rawValue }
}

/// Enumerates the settings panes available from the shell-side settings utility.
enum CloudLibrarySettingsPane: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case stream
    case controller
    case videoAudio
    case interface
    case diagnostics

    var id: String { rawValue }

    /// Provides the pane title used by settings navigation surfaces.
    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .stream:
            return "Cloud Stream Settings"
        case .controller:
            return "Controller"
        case .videoAudio:
            return "Video / Audio"
        case .interface:
            return "Interface / Accessibility"
        case .diagnostics:
            return "Diagnostics / Advanced"
        }
    }

    /// Provides the supporting copy shown alongside the pane title in settings navigation surfaces.
    var subtitle: String {
        switch self {
        case .overview:
            return "Profile, quick actions, and shell status"
        case .stream:
            return "Quality, codec, bitrate, latency, and stream overlay settings"
        case .controller:
            return "Input feel, mappings, deadzone, and sensitivity tuning"
        case .videoAudio:
            return "Display and audio preferences modeled after the web client"
        case .interface:
            return "TV comfort and shell accessibility controls"
        case .diagnostics:
            return "Advanced diagnostics and debug toggles"
        }
    }

    /// Maps each settings pane to the SF Symbol used in shell and settings navigation.
    var systemImage: String {
        switch self {
        case .overview:
            return "square.grid.2x2.fill"
        case .stream:
            return "cloud.fill"
        case .controller:
            return "gamecontroller.fill"
        case .videoAudio:
            return "display"
        case .interface:
            return "figure.wave"
        case .diagnostics:
            return "wrench.and.screwdriver.fill"
        }
    }

    /// Filters the pane list for the simplified settings mode.
    static func visibleCases(isAdvanced: Bool) -> [CloudLibrarySettingsPane] {
        if isAdvanced {
            return allCases
        }
        return [.overview, .stream, .interface]
    }
}

/// Describes one side-rail navigation destination including its title, symbol, and optional badge.
struct SideRailNavItemViewState: Identifiable, Hashable, Sendable {
    let id: SideRailNavID
    let title: String
    let systemImage: String
    var badgeText: String?

    init(id: SideRailNavID, title: String, systemImage: String, badgeText: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.badgeText = badgeText
    }
}

/// Describes one trailing side-rail action button.
struct SideRailActionViewState: Identifiable, Hashable, Sendable {
    let id: String
    let systemImage: String
    let accessibilityLabel: String
}

/// Captures the complete side-rail presentation payload rendered by the shell.
struct SideRailNavigationViewState: Hashable, Sendable {
    let accountName: String
    let accountStatus: String
    let accountDetail: String?
    let profileImageURL: URL?
    let profileInitials: String
    let navItems: [SideRailNavItemViewState]
    let trailingActions: [SideRailActionViewState]
}

/// Controls the visual treatment for shell and detail action buttons.
enum CloudLibraryActionStyle: String, Hashable, Sendable {
    case primary
    case secondary
    case ghost
}

/// Describes a shell-facing action button or menu action.
struct CloudLibraryActionViewState: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String?
    let style: CloudLibraryActionStyle

    init(id: String, title: String, systemImage: String? = nil, style: CloudLibraryActionStyle = .secondary) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.style = style
    }
}

/// Controls the visual treatment for lightweight filter and metadata chips.
enum ChipStyle: String, Hashable, Sendable {
    case neutral
    case accent
}

/// Describes a selectable chip rendered in browse and settings surfaces.
struct ChipViewState: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let systemImage: String?
    let style: ChipStyle
    let isSelected: Bool

    init(id: String, label: String, systemImage: String? = nil, style: ChipStyle = .neutral, isSelected: Bool = false) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.style = style
        self.isSelected = isSelected
    }
}

/// Describes the artwork aspect ratio expected for a media tile.
enum MediaTileAspect: String, Hashable, Sendable {
    case portrait
    case landscape
}

/// Preserves media-tile presentation variants where the same model is rendered in different shells.
enum MediaTilePresentation: String, Hashable, Sendable {
    case standard
    case artworkOnly
}

/// Represents the shared media-tile payload used across home, library, and search.
struct MediaTileViewState: Identifiable, Hashable, Sendable {
    let id: String
    let titleID: TitleID
    let title: String
    let subtitle: String?
    let caption: String?
    let artworkURL: URL?
    let badgeText: String?
    let aspect: MediaTileAspect

    init(
        id: String,
        titleID: TitleID,
        title: String,
        subtitle: String? = nil,
        caption: String? = nil,
        artworkURL: URL? = nil,
        badgeText: String? = nil,
        aspect: MediaTileAspect = .portrait
    ) {
        self.id = id
        self.titleID = titleID
        self.title = title
        self.subtitle = subtitle
        self.caption = caption
        self.artworkURL = artworkURL
        self.badgeText = badgeText
        self.aspect = aspect
    }
}

/// Describes the action attached to a home rail title tile.
enum CloudLibraryHomeTitleAction: Hashable, Sendable {
    case openDetail
    case launchStream(source: String)
}

/// Couples a home rail tile with the action that should run when it is selected.
struct CloudLibraryHomeTitleRailItemViewState: Identifiable, Hashable, Sendable {
    let id: String
    let tile: MediaTileViewState
    let action: CloudLibraryHomeTitleAction
}

/// Describes the “show all” card appended to expandable home rail sections.
struct CloudLibraryHomeShowAllCardViewState: Identifiable, Hashable, Sendable {
    let id: String
    let alias: String
    let label: String
    let totalCount: Int
}

/// Wraps the two item kinds that can appear in a home rail section.
enum CloudLibraryHomeRailItemViewState: Identifiable, Hashable, Sendable {
    case title(CloudLibraryHomeTitleRailItemViewState)
    case showAll(CloudLibraryHomeShowAllCardViewState)

    var id: String {
        switch self {
        case .title(let item):
            return item.id
        case .showAll(let card):
            return card.id
        }
    }
}

/// Describes one home rail section including its optional category alias and rendered items.
struct CloudLibraryRailSectionViewState: Identifiable, Hashable, Sendable {
    let id: String
    let alias: String?
    let title: String
    let subtitle: String?
    let items: [CloudLibraryHomeRailItemViewState]
}

/// Describes one featured hero item in the home carousel.
struct CloudLibraryHomeCarouselItemViewState: Identifiable, Hashable, Sendable {
    let id: String
    let titleID: TitleID
    let title: String
    let subtitle: String?
    let categoryLabel: String?
    let ratingBadgeText: String?
    let description: String?
    let heroBackgroundURL: URL?
    let artworkURL: URL?
}

/// Captures the complete home-screen presentation payload.
struct CloudLibraryHomeViewState: Hashable, Sendable {
    let heroBackgroundURL: URL?
    let carouselItems: [CloudLibraryHomeCarouselItemViewState]
    let sections: [CloudLibraryRailSectionViewState]
}

struct CloudLibraryLibraryTabViewState: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
}

enum CloudLibraryLibraryDisplayMode: String, Hashable, Sendable {
    case grid
    case rails
}

struct CloudLibraryLibraryViewState: Hashable, Sendable {
    let heroBackdropURL: URL?
    let tabs: [CloudLibraryLibraryTabViewState]
    let selectedTabID: String
    let filters: [ChipViewState]
    let sortLabel: String
    let displayMode: CloudLibraryLibraryDisplayMode
    let gridItems: [MediaTileViewState]
    var resultSummaryText: String? = nil
    var activeFilterLabels: [String] = []
    var categoryCalloutTitle: String? = nil
}

struct OverlayPanelViewState: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
}

enum CloudLibraryGalleryMediaKind: String, Hashable, Sendable {
    case image
    case video
}

struct CloudLibraryGalleryItemViewState: Identifiable, Hashable, Sendable {
    let id: String
    let kind: CloudLibraryGalleryMediaKind
    let mediaURL: URL
    let thumbnailURL: URL?
    let title: String?

    init(
        id: String? = nil,
        kind: CloudLibraryGalleryMediaKind,
        mediaURL: URL,
        thumbnailURL: URL? = nil,
        title: String? = nil
    ) {
        self.id = id ?? "\(kind.rawValue):\(mediaURL.absoluteString)"
        self.kind = kind
        self.mediaURL = mediaURL
        self.thumbnailURL = thumbnailURL
        self.title = title
    }
}

struct CloudLibraryTitleDetailViewState: Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let heroImageURL: URL?
    let posterImageURL: URL?
    let ratingText: String?
    let legalText: String?
    let descriptionText: String?
    let primaryAction: CloudLibraryActionViewState
    let secondaryActions: [CloudLibraryActionViewState]
    let capabilityChips: [ChipViewState]
    let gallery: [CloudLibraryGalleryItemViewState]
    let achievementSummary: TitleAchievementSummary?
    let achievementItems: [AchievementProgressItem]
    let achievementErrorText: String?
    let detailPanels: [OverlayPanelViewState]
    var contextLabel: String? = nil
    var isHydrating: Bool = false
    var titleID: TitleID = TitleID("")
    var productID: ProductID = ProductID("")
}

enum CloudLibraryStatusKind: String, Hashable, Sendable {
    case loading
    case error
    case empty
}

struct CloudLibraryStatusViewState: Hashable, Sendable {
    let kind: CloudLibraryStatusKind
    let title: String
    let message: String
    let primaryActionTitle: String?
}
