// StreamGuideOverlayStateTests.swift
// Exercises stream guide overlay state behavior.
//

import Testing
@testable import Stratix
@testable import StratixCore

@MainActor
@Suite
struct StreamGuideOverlayStateTests {
    @Test
    func basicModeOnlyShowsOverviewStreamAndInterfacePanes() {
        #expect(
            StreamGuideOverlayState.visiblePanes(for: .basic) == [.overview, .stream, .interface]
        )
        #expect(
            StreamGuideOverlayState.visiblePanes(for: .advanced) == GuideOverlayPane.allCases
        )
    }

    @Test
    func resolvedSelectedPanePrefersRequestedPaneAndClampsToVisiblePanes() {
        #expect(
            StreamGuideOverlayState.resolvedSelectedPane(
                requestedPaneRawValue: GuideOverlayPane.diagnostics.rawValue,
                lastPaneRawValue: GuideOverlayPane.controller.rawValue,
                rememberLastSection: true,
                settingsMode: .basic
            ) == .overview
        )
        #expect(
            StreamGuideOverlayState.resolvedSelectedPane(
                requestedPaneRawValue: nil,
                lastPaneRawValue: GuideOverlayPane.controller.rawValue,
                rememberLastSection: true,
                settingsMode: .advanced
            ) == .controller
        )
    }

    @Test
    func paneSettingSummaryTextReflectsAppliedGuideAndSavedCounts() {
        let summary = StreamGuideOverlayState.paneSettingSummaryText(
            selectedPane: .stream,
            definitionsByScope: GuideSettingCatalog.guideSettingDefinitionsByScope
        )

        #expect(summary == "10 applied now • 1 saved only")
    }

    @Test
    func streamPresentationNormalizesPresetProfileAndBitrateSource() {
        var stream = SettingsStore.StreamSettings()
        stream.qualityPreset = "High"
        stream.preferredResolution = "1080p"
        stream.bitrateCapMbps = 18
        stream.clientProfileOSName = "  "

        let presentation = StreamGuideOverlayState.streamPresentation(streamSettings: stream)

        #expect(presentation.normalizedQualityPreset == "High Quality")
        #expect(presentation.effectiveStreamProfileLabel == "1440p60 High Quality")
        #expect(presentation.effectiveClientProfileOSName == "tizen")
        #expect(presentation.streamConfigConflictWarning == "High Quality enforces a 1440p profile; manual resolution applies only in Balanced.")
        #expect(presentation.effectiveVideoBitrateCapKbps == 20_000)
        #expect(presentation.bitrateCapSourceLabel == "preset")
    }

    @Test
    func visibleGuideSettingsMarkUnwiredControlsAsSavedOrGuideOnly() {
        let packetLossProtection = GuideSettingCatalog.guideSettingDefinitionsByID["stream_packet_loss_protection"]
        let chatChannel = GuideSettingCatalog.guideSettingDefinitionsByID["audio_chat_channel"]
        let rememberLastSection = GuideSettingCatalog.guideSettingDefinitionsByID["interface_remember_last_section"]
        let regionOverride = GuideSettingCatalog.guideSettingDefinitionsByID["diagnostics_region_override"]

        #expect(packetLossProtection?.wiringState == .savedOnly)
        #expect(chatChannel?.wiringState == .savedOnly)
        #expect(rememberLastSection?.wiringState == .guideOnly)
        #expect(regionOverride?.wiringState == .appliedNow)
    }
}
