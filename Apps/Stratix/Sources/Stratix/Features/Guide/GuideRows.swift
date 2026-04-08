// GuideRows.swift
// Defines guide rows for the Features / Guide surface.
//

import SwiftUI
import StratixCore

/// Shared card shell used to group guide rows into visible sections.
struct GuideSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    /// Renders a consistent guide section container with title, subtitle, and content.
    var body: some View {
        GlassCard(cornerRadius: 24, fill: Color.white.opacity(0.035), stroke: Color.white.opacity(0.10), shadowOpacity: 0.09) {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [StratixTheme.Colors.focusTint, Color.white.opacity(0.65)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 84, height: 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(StratixTypography.rounded(22, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(StratixTheme.Colors.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(StratixTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(StratixTheme.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .padding(20)
        }
    }
}

/// Sidebar navigation button used for app and guide destinations.
struct GuideSidebarButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders a focus-aware sidebar row with icon, title, and optional subtitle.
    var body: some View {
        Button(action: action) {
            FocusAwareView { isFocused in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.black.opacity(0.08) : Color.white.opacity(isFocused ? 0.10 : 0.04))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: systemImage)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.85) : StratixTheme.Colors.textSecondary)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(StratixTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(isSelected ? Color.black : StratixTheme.Colors.textPrimary)
                            .lineLimit(1)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(StratixTypography.rounded(12, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.72) : StratixTheme.Colors.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.75))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 58 : 70, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? StratixTheme.Colors.focusTint : (isFocused ? Color.white.opacity(0.10) : Color.white.opacity(0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.06 : (isFocused ? 0.16 : 0.10)), lineWidth: 1)
                )
                .guideControlFocusRing(isFocused: isFocused, cornerRadius: 18)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }
}

/// Button row used for guide actions such as refresh, export, and sign-out.
struct GuideActionButton: View {
    let title: String
    let systemImage: String
    var destructive = false
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders a focus-aware action row that can optionally style itself as destructive.
    var body: some View {
        Button(action: action) {
            FocusAwareView { isFocused in
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .font(StratixTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(isFocused ? Color.black : (destructive ? Color.red.opacity(0.92) : StratixTheme.Colors.textPrimary))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(Capsule().fill(isFocused ? StratixTheme.Colors.focusTint : Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(Color.white.opacity(isFocused ? 0.16 : 0.10), lineWidth: 1))
                .guideControlFocusRing(isFocused: isFocused, cornerRadius: 24)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }
}

/// Small status pill used to summarize guide-scoped numeric values.
struct GuideStatPill: View {
    let icon: String
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders a compact stat badge with title and value.
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(StratixTypography.rounded(13, weight: .bold, dynamicTypeSize: dynamicTypeSize))
        .foregroundStyle(StratixTheme.Colors.textSecondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Simple label/value line used in overview summaries.
struct GuideStatLine: View {
    let icon: String
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders a single stat line with the guide's compact layout.
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(StratixTheme.Colors.focusTint)
                .frame(width: 20)
            Text(text)
                .font(StratixTypography.rounded(15, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(StratixTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Toggle row used for guide settings that are backed by a Boolean value.
struct GuideToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    var wiringTag: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders a settings toggle with the guide's tagging and layout conventions.
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(StratixTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(StratixTheme.Colors.textPrimary)
                    if let wiringTag, !wiringTag.isEmpty {
                        GuideSettingTag(text: wiringTag)
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(StratixTypography.rounded(13, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(StratixTheme.Colors.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 76)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Slider row used for guide settings that are backed by a numeric range.
struct GuideSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatter: (Double) -> String
    var step: Double? = nil
    var wiringTag: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var resolvedStep: Double {
        let fallback = (range.upperBound - range.lowerBound) / 20
        return max(step ?? fallback, 0.01)
    }

    private var normalized: Double {
        guard range.upperBound > range.lowerBound else { return 1 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    /// Renders a bounded slider with +/- nudges and the guide's dense settings layout.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Text(title)
                        .font(StratixTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(StratixTheme.Colors.textPrimary)
                    if let wiringTag, !wiringTag.isEmpty {
                        GuideSettingTag(text: wiringTag)
                    }
                }
                Spacer()
                Text(formatter(value))
                    .font(StratixTypography.rounded(14, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(StratixTheme.Colors.focusTint)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                GuideNudgeButton(systemImage: "minus") {
                    value = max(range.lowerBound, value - resolvedStep)
                }

                ProgressView(value: max(0, min(1, normalized)))
                    .tint(StratixTheme.Colors.accent)
                    .scaleEffect(x: 1, y: 1.2, anchor: .center)
                    .frame(maxWidth: .infinity)

                GuideNudgeButton(systemImage: "plus") {
                    value = min(range.upperBound, value + resolvedStep)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 88)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Small increment/decrement button used by the guide slider row.
struct GuideNudgeButton: View {
    let systemImage: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders the nudge control with the shared focus ring treatment.
    var body: some View {
        Button(action: action) {
            FocusAwareView { isFocused in
                Image(systemName: systemImage)
                    .font(StratixTypography.system(18, weight: .heavy, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)
                    .frame(width: 52, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(isFocused ? 0.16 : 0.11), lineWidth: 1))
                    .guideControlFocusRing(isFocused: isFocused, cornerRadius: 12)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }
}

/// Picker row used for settings that select from a finite set of values.
struct GuidePickerRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var wiringTag: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders a picker row with the guide's label, tag, and selection treatment.
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(StratixTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)
                if let wiringTag, !wiringTag.isEmpty {
                    GuideSettingTag(text: wiringTag)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(StratixTheme.Colors.focusTint)
            .frame(width: 340, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 76)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Static tag row used to summarize guide metadata or non-editable state.
struct GuideSettingTag: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Renders a compact tag row for read-only guide information.
    var body: some View {
        Text(text)
            .font(StratixTypography.rounded(10, weight: .bold, dynamicTypeSize: dynamicTypeSize))
            .foregroundStyle(StratixTheme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

private struct GuideCompactFocusModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    @Environment(SettingsStore.self) private var settingsStore

    func body(content: Content) -> some View {
        let highVisibilityFocus = settingsStore.accessibility.highVisibilityFocus
        let reduceMotion = settingsStore.accessibility.reduceMotion
        let thinStroke = highVisibilityFocus ? 1.8 : 1.0
        let darkStroke = highVisibilityFocus ? 4.2 : 2.8
        let brightStroke = highVisibilityFocus ? 2.2 : 1.4
        let paddingInset = highVisibilityFocus ? -3.0 : -2.2
        let focusScale: CGFloat = reduceMotion ? 1.0 : (highVisibilityFocus ? 1.028 : 1.02)

        content
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(isFocused ? Color.white.opacity(0.30) : Color.clear, lineWidth: isFocused ? thinStroke : 0)

                    RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                        .stroke(isFocused ? Color.black.opacity(0.70) : Color.clear, lineWidth: isFocused ? darkStroke : 0)
                        .padding(isFocused ? paddingInset : 0)

                    RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                        .stroke(isFocused ? Color.white.opacity(0.95) : Color.clear, lineWidth: isFocused ? brightStroke : 0)
                        .padding(isFocused ? paddingInset : 0)
                }
                .shadow(color: Color.white.opacity(isFocused ? (highVisibilityFocus ? 0.22 : 0.14) : 0), radius: highVisibilityFocus ? 12 : 8)
            )
            .scaleEffect(isFocused ? focusScale : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.34 : 0.10), radius: isFocused ? 16 : 6, y: isFocused ? 8 : 3)
            .zIndex(isFocused ? 10 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
    }
}

extension View {
    func guideControlFocusRing(isFocused: Bool, cornerRadius: CGFloat) -> some View {
        modifier(GuideCompactFocusModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
