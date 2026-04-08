// CloudLibrarySettingsComponents.swift
// Defines cloud library settings components for the CloudLibrary / Settings surface.
//

import SwiftUI

struct CloudLibraryPageSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        GlassCard(
            cornerRadius: StratixTheme.Radius.xl,
            fill: Color.white.opacity(0.04),
            stroke: Color.white.opacity(0.10),
            shadowOpacity: 0.14
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(StratixTheme.Colors.textPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(StratixTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content
            }
            .padding(22)
        }
    }
}

struct CloudLibrarySidebarButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            FocusAwareView { isFocused in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconBackground(isFocused: isFocused))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: systemImage)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.82) : StratixTheme.Colors.textSecondary)
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
                                .lineLimit(2)
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
                    RoundedRectangle(cornerRadius: 18)
                        .fill(backgroundFill(isFocused: isFocused))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(borderColor(isFocused: isFocused), lineWidth: 1)
                )
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 18)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
        .accessibilityValue(Text(isSelected ? "selected" : "not_selected"))
    }

    private func iconBackground(isFocused: Bool) -> Color {
        if isSelected {
            return Color.black.opacity(0.08)
        }
        return Color.white.opacity(isFocused ? 0.10 : 0.04)
    }

    private func backgroundFill(isFocused: Bool) -> Color {
        if isSelected {
            return StratixTheme.Colors.focusTint
        }
        return isFocused ? Color.white.opacity(0.10) : Color.white.opacity(0.05)
    }

    private func borderColor(isFocused: Bool) -> Color {
        if isSelected {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(isFocused ? 0.16 : 0.10)
    }
}

struct CloudLibrarySettingsActionButton: View {
    let title: String
    let systemImage: String
    var destructive = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            FocusAwareView { isFocused in
                Label(title, systemImage: systemImage)
                    .font(StratixTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(foreground(isFocused: isFocused))
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(Capsule().fill(backgroundFill(isFocused: isFocused)))
                    .overlay(Capsule().stroke(borderColor(isFocused: isFocused), lineWidth: 1))
                    .gamePassFocusRing(isFocused: isFocused, cornerRadius: 24)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func foreground(isFocused: Bool) -> Color {
        if isFocused {
            return .black
        }
        return destructive ? Color.red.opacity(0.92) : StratixTheme.Colors.textPrimary
    }

    private func backgroundFill(isFocused: Bool) -> Color {
        isFocused ? StratixTheme.Colors.focusTint : Color.white.opacity(0.06)
    }

    private func borderColor(isFocused: Bool) -> Color {
        Color.white.opacity(isFocused ? 0.16 : 0.10)
    }
}

struct CloudLibraryStatPill: View {
    let icon: String
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Label(text, systemImage: icon)
            .font(StratixTypography.rounded(13, weight: .bold, dynamicTypeSize: dynamicTypeSize))
            .foregroundStyle(StratixTheme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct CloudLibraryStatLine: View {
    let icon: String
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

struct CloudLibraryToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(StratixTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)

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
            RoundedRectangle(cornerRadius: 17)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct CloudLibrarySliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatter: (Double) -> String
    var step: Double? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var resolvedStep: Double {
        let fallback = (range.upperBound - range.lowerBound) / 20
        return max(step ?? fallback, 0.01)
    }

    private var normalized: Double {
        guard range.upperBound > range.lowerBound else { return 1 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(StratixTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)

                Spacer()

                Text(formatter(value))
                    .font(StratixTypography.rounded(14, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(StratixTheme.Colors.focusTint)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                CloudLibraryNudgeButton(systemImage: "minus") {
                    value = max(range.lowerBound, value - resolvedStep)
                }

                ProgressView(value: max(0, min(1, normalized)))
                    .tint(StratixTheme.Colors.accent)
                    .scaleEffect(x: 1, y: 1.2, anchor: .center)
                    .frame(maxWidth: .infinity)

                CloudLibraryNudgeButton(systemImage: "plus") {
                    value = min(range.upperBound, value + resolvedStep)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 88)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct CloudLibraryPickerRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(StratixTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(StratixTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(StratixTheme.Colors.focusTint)
            .frame(width: 320, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 76)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct CloudLibrarySettingTag: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

private struct CloudLibraryNudgeButton: View {
    let systemImage: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            FocusAwareView { isFocused in
                Image(systemName: systemImage)
                    .font(StratixTypography.system(18, weight: .heavy, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(StratixTheme.Colors.textPrimary)
                    .frame(width: 52, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(isFocused ? 0.16 : 0.11), lineWidth: 1))
                    .gamePassFocusRing(isFocused: isFocused, cornerRadius: 12)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }
}
