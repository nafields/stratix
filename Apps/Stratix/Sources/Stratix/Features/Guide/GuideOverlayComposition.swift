// GuideOverlayComposition.swift
// Defines guide overlay composition for the Features / Guide surface.
//

import SwiftUI
import StratixCore
import StratixModels

extension StreamGuideOverlayView {
    /// Builds the full guide panel shell around the sidebar and detail panes.
    var panel: some View {
        GlassCard(
            cornerRadius: 34,
            fill: Color.black.opacity(max(0.15, min(0.92, settingsStore.shell.guideTranslucency))),
            stroke: Color.white.opacity(0.12),
            shadowOpacity: 0.34
        ) {
            HStack(spacing: 0) {
                leftRail

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                rightPane
            }
            .frame(maxWidth: 1510)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.clear,
                            StratixTheme.Colors.focusTint.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .padding(.leading, 34)
        .padding(.vertical, 26)
    }

    /// Builds the left-side navigation rail for app and guide destinations.
    var leftRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [StratixTheme.Colors.focusTint, StratixTheme.Colors.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 6, height: 48)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Cloud Gaming Guide")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textPrimary)

                    Text("A Select • B/Menu Back • Play/Pause Guide")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textSecondary)
                }
            }

            sidebarProfileCard

            VStack(alignment: .leading, spacing: 12) {
                Text("App")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textMuted)
                    .textCase(.uppercase)

                ForEach(AppShellSection.allCases) { section in
                    GuideSidebarButton(
                        title: section.title,
                        subtitle: destinationDetail(for: section),
                        systemImage: section.systemImage,
                        isSelected: selectedSection == section
                    ) {
                        selectedSection = section
                        close()
                    }
                    .focused($sidebarFocus, equals: .destination(section))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Guide")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textMuted)
                    .textCase(.uppercase)

                ForEach(visiblePanes) { pane in
                    GuideSidebarButton(
                        title: pane.title,
                        subtitle: nil,
                        systemImage: pane.systemImage,
                        isSelected: selectedPane == pane
                    ) {
                        selectedPane = pane
                        if settingsStore.shell.rememberLastSection {
                            lastPaneRawValue = pane.rawValue
                        }
                    }
                    .focused($sidebarFocus, equals: .pane(pane))
                }
            }

            Spacer(minLength: 0)

            Button(action: toggleSettingsMode) {
                FocusAwareView { isFocused in
                    HStack(spacing: 10) {
                        Image(systemName: settingsMode == .basic ? "slider.horizontal.3" : "sparkles")
                            .font(.system(size: 17, weight: .bold))
                        Text(settingsMode == .basic ? "Switch to Advanced" : "Switch to Basic")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Spacer(minLength: 8)
                        Text(settingsMode.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(isFocused ? Color.black.opacity(0.62) : StratixTheme.Colors.textMuted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(isFocused ? Color.black.opacity(0.10) : Color.white.opacity(0.06)))
                    }
                    .foregroundStyle(isFocused ? Color.black : StratixTheme.Colors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .background(Capsule().fill(isFocused ? StratixTheme.Colors.focusTint : Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(isFocused ? 0.14 : 0.10), lineWidth: 1))
                    .guideControlFocusRing(isFocused: isFocused, cornerRadius: 26)
                }
            }
            .buttonStyle(CloudLibraryTVButtonStyle())
            .gamePassDisableSystemFocusEffect()
            .focused($sidebarFocus, equals: .settingsMode)

            Button(action: close) {
                FocusAwareView { isFocused in
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 19, weight: .bold))
                        Text("Close Guide")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                        Spacer(minLength: 8)
                        Text("B")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(isFocused ? Color.black.opacity(0.6) : StratixTheme.Colors.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(isFocused ? Color.black.opacity(0.08) : Color.white.opacity(0.05)))
                    }
                    .foregroundStyle(isFocused ? Color.black : StratixTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background(Capsule().fill(isFocused ? StratixTheme.Colors.focusTint : Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(isFocused ? 0.14 : 0.10), lineWidth: 1))
                    .guideControlFocusRing(isFocused: isFocused, cornerRadius: 28)
                }
            }
            .buttonStyle(CloudLibraryTVButtonStyle())
            .gamePassDisableSystemFocusEffect()
            .focused($sidebarFocus, equals: .closeGuide)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(width: 408, alignment: .topLeading)
    }

    /// Builds the detail pane that renders the selected guide page content.
    var rightPane: some View {
        VStack(spacing: 0) {
            paneHeader
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 16)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let lastSettingChangeMessage, !lastSettingChangeMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(StratixTheme.Colors.focusTint)
                            Text(lastSettingChangeMessage)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(StratixTheme.Colors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.04)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    }

                    paneBody
                }
                .padding(28)
            }
            .scrollIndicators(.hidden)
            .onMoveCommand { direction in
                if direction == .left {
                    focusSidebar()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Renders the header for the currently selected guide pane.
    var paneHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: selectedPane.systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(StratixTheme.Colors.focusTint)
                Text(selectedPane.title)
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)
                if let paneSettingSummaryText {
                    Text(paneSettingSummaryText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                }
                Spacer(minLength: 0)
                Text("Left or B returns to menu")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(StratixTheme.Colors.textMuted)
            }

            Text(selectedPane.subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(StratixTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    /// Renders the body content for the currently selected guide pane.
    var paneBody: some View {
        switch selectedPane {
        case .overview:
            overviewPane
        case .stream:
            streamSettings
        case .controller:
            controllerSettings
        case .videoAudio:
            videoAudioSettings
        case .interface:
            interfaceSettings
        case .diagnostics:
            diagnosticsSettings
        }
    }

    func handleAppear() {
        assertGuideWiringCoverage()
        normalizeGuideState()
        selectedPane = StreamGuideOverlayState.resolvedSelectedPane(
            requestedPaneRawValue: requestedPaneRawValue,
            lastPaneRawValue: lastPaneRawValue,
            rememberLastSection: settingsStore.shell.rememberLastSection,
            settingsMode: settingsMode
        )

        pendingFocusTask?.cancel()
        pendingFocusTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            sidebarFocus = .destination(selectedSection)
        }
    }

    func toggleSettingsMode() {
        settingsMode = StreamGuideOverlayState.toggledSettingsMode(from: settingsMode)
        selectedPane = StreamGuideOverlayState.resolvedSelectedPane(
            requestedPaneRawValue: selectedPane.rawValue,
            lastPaneRawValue: lastPaneRawValue,
            rememberLastSection: settingsStore.shell.rememberLastSection,
            settingsMode: settingsMode
        )
    }

    func noteSettingChanged(_ title: String, value: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            lastSettingChangeMessage = "\(title) updated to \(value)"
        }
    }

    func handleGuideBack() {
        if sidebarFocus == nil {
            focusSidebar()
        } else {
            close()
        }
    }

    func focusSidebar() {
        withAnimation(.easeOut(duration: 0.14)) {
            sidebarFocus = .destination(selectedSection)
        }
    }

    func recordFocusChange(target: GuideSidebarFocusTarget?) {
        guard let target else {
            NavigationPerformanceTracker.recordFocusLoss(surface: "guide_overlay")
            return
        }

        let targetID: String
        switch target {
        case .destination(let section):
            targetID = "destination:\(section.rawValue)"
        case .pane(let pane):
            targetID = "pane:\(pane.rawValue)"
        case .settingsMode:
            targetID = "settings_mode"
        case .closeGuide:
            targetID = "close_guide"
        }

        NavigationPerformanceTracker.recordFocusTarget(surface: "guide_overlay", target: targetID)
        if !hasRecordedInitialFocusSettlement {
            NavigationPerformanceTracker.recordOverlaySettled(name: "guide", focusTarget: targetID)
            hasRecordedInitialFocusSettlement = true
        }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
