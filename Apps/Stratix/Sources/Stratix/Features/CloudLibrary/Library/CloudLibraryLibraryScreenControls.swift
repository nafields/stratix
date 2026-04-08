// CloudLibraryLibraryScreenControls.swift
// Defines cloud library library screen controls for the CloudLibrary / Library surface.
//

import SwiftUI

struct LibraryFilterChipButton: View {
    let chip: ChipViewState
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            FocusAwareView { isFocused in
                HStack(spacing: 8) {
                    if let image = chip.systemImage {
                        Image(systemName: image)
                    }
                    Text(chip.label)
                        .lineLimit(1)
                }
                .font(StratixTypography.rounded(22, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(chip.isSelected || chip.style == .accent ? Color.black : StratixTheme.Colors.textPrimary)
                .padding(.horizontal, StratixTheme.Library.chipHorizontalPadding + 8)
                .padding(.vertical, StratixTheme.Library.chipVerticalPadding + 4)
                .background(
                    Capsule(style: .continuous).fill(
                        chip.isSelected || chip.style == .accent
                        ? StratixTheme.Colors.focusTint
                        : Color.white.opacity(isFocused ? 0.14 : 0.07)
                    )
                )
                .overlay(Capsule().stroke(Color.white.opacity((chip.isSelected || chip.style == .accent) ? 0 : 0.12), lineWidth: 1))
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 18)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }
}

struct LibraryTabButton: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            FocusAwareView { isFocused in
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(
                            StratixTypography.rounded(
                                50,
                                weight: isSelected || isFocused ? .bold : .medium,
                                dynamicTypeSize: dynamicTypeSize
                            )
                        )
                        .foregroundStyle(Color.white.opacity(isSelected || isFocused ? 0.96 : 0.78))
                        .lineLimit(1)
                    Capsule(style: .continuous)
                        .fill(isSelected ? StratixTheme.Colors.focusTint : Color.white.opacity(isFocused ? 0.34 : 0.12))
                        .frame(width: isSelected ? 120 : 54, height: 5)
                }
                .animation(.easeOut(duration: 0.14), value: isFocused)
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 22)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }
}

struct SortButton: View {
    let title: String
    var icon: String = "arrow.up.arrow.down"
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            FocusAwareView { isFocused in
                HStack(spacing: 10) {
                    Image(systemName: icon)
                    Text(title)
                        .lineLimit(1)
                }
                .font(StratixTypography.rounded(22, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(StratixTheme.Colors.textPrimary)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(isFocused ? 0.14 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 14)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }
}
