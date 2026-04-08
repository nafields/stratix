// GuideSettingCatalog.swift
// Defines guide setting catalog for the Features / Guide surface.
//

import SwiftUI
import StratixCore
import StratixModels

/// Central catalog of guide-visible settings, their wiring state, and scope groupings.
enum GuideSettingCatalog {
    /// Canonical guide settings metadata used to drive the guide panel and validation checks.
    static let guideSettingDefinitions: [GuideSettingDefinition] = [
        .init(id: "stream_quality", title: "Quality Preset", wiringState: .appliedNow, scope: .stream, defaultValue: "Balanced", description: "Preferred stream quality profile."),
        .init(id: "stream_codec", title: "Codec Preference", wiringState: .appliedNow, scope: .stream, defaultValue: "Auto", description: "Preferred video codec ordering."),
        .init(id: "stream_profile", title: "Client Profile", wiringState: .appliedNow, scope: .stream, defaultValue: "Auto", description: "Spoofed osName sent to xCloud stream APIs."),
        .init(id: "stream_resolution", title: "Resolution", wiringState: .appliedNow, scope: .stream, defaultValue: "1080p", description: "Primary resolution preference."),
        .init(id: "stream_fps", title: "Frame Rate", wiringState: .appliedNow, scope: .stream, defaultValue: "60", description: "Preferred output frame rate."),
        .init(id: "stream_bitrate_cap", title: "Bitrate Cap", wiringState: .appliedNow, scope: .stream, defaultValue: "15 Mbps", description: "SDP video bitrate cap."),
        .init(id: "stream_low_latency", title: "Low Latency Mode", wiringState: .appliedNow, scope: .stream, defaultValue: "On", description: "Latency-first transport tuning."),
        .init(id: "stream_upscaling", title: "Upscaling", wiringState: .appliedNow, scope: .stream, defaultValue: "On", description: "Start on sample buffer, then promote after runtime validation."),
        .init(id: "stream_packet_loss_protection", title: "Packet Loss Protection", wiringState: .savedOnly, scope: .stream, defaultValue: "On", description: "Saved preference; runtime wiring not active."),
        .init(id: "stream_auto_reconnect", title: "Auto Reconnect", wiringState: .appliedNow, scope: .stream, defaultValue: "On", description: "Reconnect stream after transport drop."),
        .init(id: "stream_stats", title: "Show Stream Stats", wiringState: .appliedNow, scope: .stream, defaultValue: "Off", description: "Display live bitrate and RTT."),
        .init(id: "controller_vibration", title: "Vibration / Rumble", wiringState: .appliedNow, scope: .controller, defaultValue: "On", description: "Controller haptics routing."),
        .init(id: "controller_swap_ab", title: "Swap A / B Buttons", wiringState: .appliedNow, scope: .controller, defaultValue: "Off", description: "Alternative confirm/cancel layout."),
        .init(id: "controller_invert_y", title: "Invert Y Axis", wiringState: .appliedNow, scope: .controller, defaultValue: "Off", description: "Invert vertical look input."),
        .init(id: "controller_deadzone", title: "Stick Deadzone", wiringState: .appliedNow, scope: .controller, defaultValue: "0.10", description: "Controller stick deadzone radius."),
        .init(id: "controller_trigger_sensitivity", title: "Trigger Sensitivity", wiringState: .appliedNow, scope: .controller, defaultValue: "0.50", description: "Trigger curve scaling."),
        .init(id: "controller_trigger_mode", title: "Trigger Interpretation", wiringState: .appliedNow, scope: .controller, defaultValue: "Auto", description: "Auto-detect analog vs compatibility fallback for triggers."),
        .init(id: "controller_sensitivity_boost", title: "Sensitivity Boost", wiringState: .savedOnly, scope: .controller, defaultValue: "0.00", description: "Saved preference; runtime wiring not active."),
        .init(id: "video_hdr", title: "HDR Preferred", wiringState: .appliedNow, scope: .videoAudio, defaultValue: "On", description: "Enable HDR metadata path when available."),
        .init(id: "video_color_range", title: "Color Range", wiringState: .appliedNow, scope: .videoAudio, defaultValue: "Auto", description: "Color range hint for stream startup."),
        .init(id: "audio_boost", title: "Audio Boost", wiringState: .appliedNow, scope: .videoAudio, defaultValue: "+3 dB", description: "Remote track gain adjustment."),
        .init(id: "video_safe_area", title: "Safe Area", wiringState: .appliedNow, scope: .videoAudio, defaultValue: "100%", description: "Video surface safe-area inset."),
        .init(id: "audio_stereo", title: "Stereo Audio", wiringState: .appliedNow, scope: .videoAudio, defaultValue: "Off", description: "WebRTC output channel count preference."),
        .init(id: "audio_chat_channel", title: "Chat Channel", wiringState: .savedOnly, scope: .videoAudio, defaultValue: "Off", description: "Saved preference; runtime wiring not active."),
        .init(id: "audio_closed_captions", title: "Closed Captions", wiringState: .savedOnly, scope: .videoAudio, defaultValue: "Off", description: "Saved preference; runtime wiring not active."),
        .init(id: "interface_reduce_motion", title: "Reduce Motion", wiringState: .appliedNow, scope: .interface, defaultValue: "Off", description: "Minimize shell transition animation."),
        .init(id: "interface_large_text", title: "Large Text", wiringState: .appliedNow, scope: .interface, defaultValue: "Off", description: "Increase shell text sizing."),
        .init(id: "interface_quick_resume_tile", title: "Quick Resume Badges", wiringState: .appliedNow, scope: .interface, defaultValue: "On", description: "Show continue badges on recent cloud titles across home, library, and search."),
        .init(id: "interface_remember_last_section", title: "Remember Last Guide Page", wiringState: .guideOnly, scope: .interface, defaultValue: "On", description: "Guide navigation restore behavior."),
        .init(id: "interface_high_visibility_focus", title: "High Visibility Focus", wiringState: .appliedNow, scope: .interface, defaultValue: "Off", description: "Accessibility-focused focus ring styling."),
        .init(id: "interface_focus_glow_intensity", title: "Focus Glow Intensity", wiringState: .savedOnly, scope: .interface, defaultValue: "85%", description: "Saved preference; runtime wiring not active."),
        .init(id: "interface_guide_translucency", title: "Guide Panel Opacity", wiringState: .guideOnly, scope: .interface, defaultValue: "82%", description: "Guide panel translucency."),
        .init(id: "diagnostics_region_override", title: "Region Override", wiringState: .appliedNow, scope: .diagnostics, defaultValue: "Auto", description: "Preferred xCloud region selection."),
        .init(id: "diagnostics_debug_host_info", title: "Show Host / Region Info", wiringState: .savedOnly, scope: .diagnostics, defaultValue: "On", description: "Saved preference; runtime wiring not active."),
        .init(id: "diagnostics_log_network_events", title: "Log Network Events", wiringState: .savedOnly, scope: .diagnostics, defaultValue: "Off", description: "Saved preference; runtime wiring not active."),
        .init(id: "diagnostics_upscaling_floor", title: "Upscaling Floor", wiringState: .appliedNow, scope: .diagnostics, defaultValue: "Sample Floor", description: "Choose whether the ladder floors out on sample buffer or Metal passthrough."),
        .init(id: "diagnostics_profile_mirror", title: "Mirror Profile Name to Guide", wiringState: .guideOnly, scope: .diagnostics, defaultValue: "On", description: "Local profile-name mirroring for guide UI.")
    ]

    /// Quick lookup table from setting identifier to its metadata definition.
    static let guideSettingDefinitionsByID = Dictionary(
        uniqueKeysWithValues: guideSettingDefinitions.map { ($0.id, $0) }
    )

    /// Groups guide settings by scope for section rendering and summary text.
    static let guideSettingDefinitionsByScope = Dictionary(
        grouping: guideSettingDefinitions,
        by: \.scope
    )

    /// The subset of settings that should appear in the live guide UI.
    static let visibleGuideSettingIDs: Set<String> = [
        "stream_quality", "stream_codec", "stream_profile", "stream_resolution", "stream_fps",
        "stream_bitrate_cap", "stream_low_latency", "stream_upscaling", "stream_packet_loss_protection",
        "stream_auto_reconnect", "stream_stats",
        "controller_vibration", "controller_swap_ab", "controller_invert_y",
        "controller_deadzone", "controller_trigger_sensitivity", "controller_trigger_mode", "controller_sensitivity_boost",
        "video_hdr", "video_color_range",
        "audio_boost", "video_safe_area", "audio_stereo", "audio_chat_channel",
        "audio_closed_captions",
        "interface_reduce_motion", "interface_large_text", "interface_quick_resume_tile",
        "interface_remember_last_section", "interface_high_visibility_focus",
        "interface_focus_glow_intensity", "interface_guide_translucency",
        "diagnostics_region_override", "diagnostics_debug_host_info",
        "diagnostics_log_network_events", "diagnostics_upscaling_floor",
        "diagnostics_profile_mirror"
    ]
}

extension StreamGuideOverlayView {
    /// Returns the guide panes that are currently visible for the active settings mode.
    var visiblePanes: [GuideOverlayPane] {
        StreamGuideOverlayState.visiblePanes(for: settingsMode)
    }

    /// Maps the selected guide pane to its settings scope when one exists.
    var selectedPaneScope: GuideSettingDefinition.Scope? {
        switch selectedPane {
        case .overview:
            return nil
        case .stream:
            return .stream
        case .controller:
            return .controller
        case .videoAudio:
            return .videoAudio
        case .interface:
            return .interface
        case .diagnostics:
            return .diagnostics
        }
    }

    /// Builds the short summary tag shown in the pane header for the active scope.
    var paneSettingSummaryText: String? {
        StreamGuideOverlayState.paneSettingSummaryText(
            selectedPane: selectedPane,
            definitionsByScope: GuideSettingCatalog.guideSettingDefinitionsByScope
        )
    }

    /// Returns the wiring label for a visible guide setting identifier.
    func wiringTag(for id: String) -> String {
        GuideSettingCatalog.guideSettingDefinitionsByID[id]?.wiringState.label ?? GuideSettingDefinition.WiringState.savedOnly.label
    }

    /// Debug assertion that the visible guide settings remain fully catalogued.
    func assertGuideWiringCoverage() {
        #if DEBUG
        let missing = GuideSettingCatalog.visibleGuideSettingIDs.subtracting(GuideSettingCatalog.guideSettingDefinitionsByID.keys)
        assert(
            missing.isEmpty,
            "Guide wiring definitions are missing IDs: \(missing.sorted().joined(separator: ", "))"
        )
        #endif
    }
}
