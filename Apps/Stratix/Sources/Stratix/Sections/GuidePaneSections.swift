// GuidePaneSections.swift
// Defines guide pane sections for the Sections surface.
//

import SwiftUI
import StratixCore
import StratixModels

extension StreamGuideOverlayView {
    /// Renders the compact profile card used at the top of the guide sidebar.
    var sidebarProfileCard: some View {
        GlassCard(cornerRadius: 22, fill: Color.white.opacity(0.03), stroke: Color.white.opacity(0.10), shadowOpacity: 0.10) {
            HStack(spacing: 14) {
                avatar
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(profileName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(profilePresenceColor)
                            .frame(width: 8, height: 8)
                        Text(profileStatusText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    Text("\(effectiveStreamProfileLabel) • \(settingsStore.stream.hdrEnabled ? "HDR" : "SDR")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    /// Composes the overview pane from the profile summary, quick actions, and guide controls.
    var overviewPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            profileCard

            HStack(alignment: .top, spacing: 16) {
                quickActions
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                guideControlsCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Explains the controller-driven navigation behavior that applies across the guide.
    var guideControlsCard: some View {
        GuideSectionCard(title: "Guide Controls", subtitle: "Controller-focused navigation behavior") {
            VStack(alignment: .leading, spacing: 8) {
                GuideStatLine(icon: "arrow.left.circle.fill", text: "Left or B/Menu jumps out of settings controls back to the guide rail")
                GuideStatLine(icon: "a.circle.fill", text: "A / Enter activates the focused item")
                GuideStatLine(icon: "playpause.circle.fill", text: "Play/Pause closes the guide from anywhere")
                GuideStatLine(icon: "house.circle.fill", text: "B/Menu from My Consoles or Settings returns to Game Pass at the app shell")
            }
        }
    }

    /// Renders the full-width profile summary card shown in the overview pane.
    var profileCard: some View {
        GlassCard(cornerRadius: 24, fill: Color.white.opacity(0.03), stroke: Color.white.opacity(0.10), shadowOpacity: 0.10) {
            HStack(alignment: .top, spacing: 18) {
                avatar
                    .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(profileName)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.textPrimary)
                        Text(profileStatusText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(profilePresenceUsesDarkBadgeText ? .black : StratixTheme.Colors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(profilePresenceBadgeFill))
                    }

                    Text("Current app section: \(selectedSection.title)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textSecondary)

                    Text(profileSummaryText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    if let profileStatusDetail, !profileStatusDetail.isEmpty {
                        Text(profileStatusDetail)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.textMuted)
                            .lineLimit(2)
                    }

                    HStack(spacing: 10) {
                        GuideStatPill(icon: "cloud.fill", text: "\(cloudLibraryCount) cloud titles")
                        GuideStatPill(icon: "tv.fill", text: "\(consoleCount) consoles")
                        GuideStatPill(icon: "gearshape.fill", text: normalizedQualityPreset)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    var avatar: some View {
        Group {
            if let profileImageURL {
                AsyncImage(url: profileImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            StratixTheme.Colors.focusTint,
                            Color.cyan.opacity(0.85),
                            Color.white.opacity(0.92),
                            StratixTheme.Colors.focusTint
                        ],
                        center: .center
                    )
                )
            Text(profileInitials.isEmpty ? "P" : profileInitials)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))
        }
    }

    var profileSummaryText: String {
        let loadingText = isLoadingCloudLibrary ? "Library syncing in background." : "Library ready."
        let runtimeText = "\(effectiveStreamProfileLabel) • \(settingsStore.stream.codecPreference) • \(settingsStore.stream.hdrEnabled ? "HDR" : "SDR")"
        return "\(runtimeText)  \(loadingText)"
    }

    var quickActions: some View {
        GuideSectionCard(title: "Quick Actions", subtitle: "Fast actions without digging through settings") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12, alignment: .leading),
                    GridItem(.flexible(), spacing: 12, alignment: .leading),
                    GridItem(.flexible(), spacing: 12, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                GuideActionButton(title: "Refresh Game Pass", systemImage: "arrow.clockwise") {
                    onRefreshCloudLibrary()
                }
                GuideActionButton(title: "Refresh Consoles", systemImage: "tv.badge.wifi") {
                    onRefreshConsoles()
                }
                GuideActionButton(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right", destructive: true) {
                    onSignOut()
                    close()
                }
            }
        }
    }

    var streamSettings: some View {
        GuideSectionCard(title: "Cloud Stream Settings", subtitle: "Persisted locally; some runtime wiring is still partial") {
            VStack(alignment: .leading, spacing: 12) {
                GuidePickerRow(title: "Quality Preset", selection: streamBinding(\.qualityPreset), options: ["Low Data", "Balanced", "High Quality", "Competitive"], wiringTag: wiringTag(for: "stream_quality"))
                GuidePickerRow(title: "Codec Preference", selection: streamBinding(\.codecPreference), options: ["Auto", "H.264", "VP9"], wiringTag: wiringTag(for: "stream_codec"))
                GuidePickerRow(title: "Client Profile", selection: streamBinding(\.clientProfileOSName), options: ["Auto", "Android", "Windows", "Tizen"], wiringTag: wiringTag(for: "stream_profile"))
                GuidePickerRow(title: "Resolution", selection: streamBinding(\.preferredResolution), options: ["720p", "1080p", "1440p"], wiringTag: wiringTag(for: "stream_resolution"))
                GuidePickerRow(title: "Frame Rate", selection: streamBinding(\.preferredFPS), options: ["30", "60"], wiringTag: wiringTag(for: "stream_fps"))
                GuideSliderRow(title: "Bitrate Cap", value: streamBinding(\.bitrateCapMbps), range: 4...100, formatter: { String(format: "%.0f Mbps", $0) }, wiringTag: wiringTag(for: "stream_bitrate_cap"))
                GuideToggleRow(title: "Low Latency Mode", subtitle: "Prioritize responsiveness", isOn: streamBinding(\.lowLatencyMode), wiringTag: wiringTag(for: "stream_low_latency"))
                GuideToggleRow(title: "Upscaling", subtitle: "Start safe on sample buffer, then promote after validation", isOn: streamBinding(\.upscalingEnabled), wiringTag: wiringTag(for: "stream_upscaling"))
                GuideToggleRow(title: "Packet Loss Protection", subtitle: "Smoother playback on unstable networks", isOn: streamBinding(\.packetLossProtection), wiringTag: wiringTag(for: "stream_packet_loss_protection"))
                GuideToggleRow(title: "Auto Reconnect", subtitle: "Try reconnecting when the stream drops", isOn: streamBinding(\.autoReconnect), wiringTag: wiringTag(for: "stream_auto_reconnect"))
                GuideToggleRow(title: "Show Stream Stats", subtitle: "FPS / bitrate / RTT overlay", isOn: streamBinding(\.showStreamStats), wiringTag: wiringTag(for: "stream_stats"))
                GuideStatLine(icon: "checkmark.seal.fill", text: "Effective profile: \(effectiveStreamProfileLabel)")
                GuideStatLine(icon: "desktopcomputer", text: "Effective client osName: \(effectiveClientProfileOSName)")
                GuideStatLine(icon: "speedometer", text: "Effective video cap: \(effectiveVideoBitrateCapKbps.map { "\($0) kbps" } ?? "unlimited") (source: \(bitrateCapSourceLabel))")
                if let streamConfigConflictWarning {
                    GuideStatLine(icon: "exclamationmark.triangle.fill", text: streamConfigConflictWarning)
                }
            }
        }
    }

    var controllerSettings: some View {
        GuideSectionCard(title: "Controller", subtitle: "Mappings and feel") {
            VStack(alignment: .leading, spacing: 12) {
                GuideToggleRow(title: "Vibration / Rumble", subtitle: "Enable controller haptics", isOn: controllerBinding(\.vibrationEnabled), wiringTag: wiringTag(for: "controller_vibration"))
                GuideToggleRow(title: "Swap A / B Buttons", subtitle: "Alternative confirm/cancel layout", isOn: controllerBinding(\.swapABButtons), wiringTag: wiringTag(for: "controller_swap_ab"))
                GuideToggleRow(title: "Invert Y Axis", subtitle: "Camera look inversion", isOn: controllerBinding(\.invertYAxis), wiringTag: wiringTag(for: "controller_invert_y"))
                GuideSliderRow(title: "Stick Deadzone", value: controllerBinding(\.deadzone), range: 0...0.4, formatter: { String(format: "%.2f", $0) }, wiringTag: wiringTag(for: "controller_deadzone"))
                GuideSliderRow(title: "Trigger Sensitivity", value: controllerBinding(\.triggerSensitivity), range: 0...1, formatter: { String(format: "%.2f", $0) }, wiringTag: wiringTag(for: "controller_trigger_sensitivity"))
                GuidePickerRow(title: "Trigger Interpretation", selection: triggerModeBinding, options: ["Auto", "Compatibility", "Analog"], wiringTag: wiringTag(for: "controller_trigger_mode"))
                GuideSliderRow(title: "Sensitivity Boost", value: controllerBinding(\.sensitivityBoost), range: 0...1, formatter: { String(format: "%.2f", $0) }, wiringTag: wiringTag(for: "controller_sensitivity_boost"))
            }
        }
    }

    var videoAudioSettings: some View {
        GuideSectionCard(title: "Video / Audio", subtitle: "Display and audio tuning") {
            VStack(alignment: .leading, spacing: 12) {
                GuideToggleRow(title: "HDR Preferred", subtitle: "Use HDR when supported", isOn: streamBinding(\.hdrEnabled), wiringTag: wiringTag(for: "video_hdr"))
                GuidePickerRow(title: "Color Range", selection: streamBinding(\.colorRange), options: ["Auto", "Limited", "Full"], wiringTag: wiringTag(for: "video_color_range"))
                GuideSliderRow(title: "Audio Boost", value: streamBinding(\.audioBoost), range: 0...12, formatter: { String(format: "+%.0f dB", $0) }, wiringTag: wiringTag(for: "audio_boost"))
                GuideSliderRow(title: "Safe Area", value: streamBinding(\.safeAreaPercent), range: 85...100, formatter: { String(format: "%.0f%%", $0) }, wiringTag: wiringTag(for: "video_safe_area"))
                GuideToggleRow(title: "Stereo Audio", subtitle: "Prefer stereo output", isOn: streamBinding(\.stereoAudio), wiringTag: wiringTag(for: "audio_stereo"))
                GuideToggleRow(title: "Chat Channel", subtitle: "Reserve channel for future voice features", isOn: streamBinding(\.chatChannelEnabled), wiringTag: wiringTag(for: "audio_chat_channel"))
                GuideToggleRow(title: "Closed Captions", subtitle: "Show captions when titles support them", isOn: accessibilityBinding(\.closedCaptions), wiringTag: wiringTag(for: "audio_closed_captions"))
            }
        }
    }

    var interfaceSettings: some View {
        GuideSectionCard(title: "Interface / Accessibility", subtitle: "TV comfort and readability") {
            VStack(alignment: .leading, spacing: 12) {
                GuideToggleRow(title: "Reduce Motion", subtitle: "Minimize focus and transition animation", isOn: accessibilityBinding(\.reduceMotion), wiringTag: wiringTag(for: "interface_reduce_motion"))
                GuideToggleRow(title: "Large Text", subtitle: "Increase shell overlay label readability", isOn: accessibilityBinding(\.largeText), wiringTag: wiringTag(for: "interface_large_text"))
                GuideToggleRow(title: "Quick Resume Badges", subtitle: "Show continue labels on recent titles", isOn: shellBinding(\.quickResumeTile), wiringTag: wiringTag(for: "interface_quick_resume_tile"))
                GuideToggleRow(title: "Remember Last Guide Page", subtitle: "Restore guide page on next open", isOn: shellBinding(\.rememberLastSection), wiringTag: wiringTag(for: "interface_remember_last_section"))
                GuideToggleRow(title: "High Visibility Focus", subtitle: "Thicker focus ring and simpler focus glow", isOn: accessibilityBinding(\.highVisibilityFocus), wiringTag: wiringTag(for: "interface_high_visibility_focus"))
                GuideSliderRow(title: "Focus Glow Intensity", value: shellBinding(\.focusGlowIntensity), range: 0.2...1.4, formatter: { String(format: "%.0f%%", $0 * 100) }, wiringTag: wiringTag(for: "interface_focus_glow_intensity"))
                GuideSliderRow(title: "Guide Panel Opacity", value: shellBinding(\.guideTranslucency), range: 0.55...0.95, formatter: { String(format: "%.0f%%", $0 * 100) }, wiringTag: wiringTag(for: "interface_guide_translucency"))
            }
        }
    }

    var diagnosticsSettings: some View {
        GuideSectionCard(title: "Diagnostics / Advanced", subtitle: "Power-user and debugging options") {
            VStack(alignment: .leading, spacing: 12) {
                GuidePickerRow(title: "Region Override", selection: streamBinding(\.regionOverride), options: ["Auto", "US East", "US West", "Europe", "UK"], wiringTag: wiringTag(for: "diagnostics_region_override"))
                if let regionOverrideDiagnostics, !regionOverrideDiagnostics.isEmpty {
                    GuideStatLine(icon: "exclamationmark.triangle.fill", text: regionOverrideDiagnostics)
                }
                GuideToggleRow(title: "Show Host / Region Info", subtitle: "Expose endpoint details in the UI", isOn: diagnosticsBinding(\.debugHostInfo), wiringTag: wiringTag(for: "diagnostics_debug_host_info"))
                GuideToggleRow(title: "Log Network Events", subtitle: "Verbose diagnostics for troubleshooting", isOn: diagnosticsBinding(\.logNetworkEvents), wiringTag: wiringTag(for: "diagnostics_log_network_events"))
                GuidePickerRow(title: "Upscaling Floor", selection: diagnosticsFloorBehaviorBinding, options: UpscalingFloorBehavior.allCases.map(\.label), wiringTag: wiringTag(for: "diagnostics_upscaling_floor"))
                GuideToggleRow(title: "Mirror Profile Name to Guide", subtitle: "Store display name in local preferences", isOn: profileMirrorBinding, wiringTag: wiringTag(for: "diagnostics_profile_mirror"))
                GuideActionButton(title: isExportingPreviewDump ? "Exporting Preview Dump…" : "Export Preview Dump", systemImage: "square.and.arrow.down.on.square") {
                    exportPreviewDump()
                }

                if let previewDumpStatusMessage, !previewDumpStatusMessage.isEmpty {
                    Text(previewDumpStatusMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                        .transition(.opacity)
                }
            }
        }
    }

    func exportPreviewDump() {
        guard !isExportingPreviewDump else { return }
        isExportingPreviewDump = true

        Task {
            let message = await onExportPreviewDump()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.15)) {
                    previewDumpStatusMessage = message
                    isExportingPreviewDump = false
                }
            }
        }
    }
}
