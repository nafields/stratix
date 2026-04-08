// SideRailActionList.swift
// Defines side rail action list for the Shared / Components surface.
//

import SwiftUI

extension SideRailNavigationView {
    /// Trailing action stack shown below the main nav rows once the rail is expanded.
    var actionListView: some View {
        VStack(alignment: .leading, spacing: StratixTheme.SideRail.rowSpacing) {
            ForEach(trailingActions) { action in
                SideRailActionButton(
                    action: action,
                    isSelected: action.id == "settings" && activeUtilityRoute == .settings,
                    isExpanded: isRailExpanded,
                    isFocusable: isRailExpanded,
                    onSelect: {
                        onSelectAction(action.id)
                        collapseRail()
                    },
                    onMoveToContent: moveFocusToContent
                )
                .focused($focusedTarget, equals: .action(action.id))
                .onMoveCommand { direction in
                    guard isRailExpanded else { return }
                    if direction == .up, action.id == firstActionID, let lastExpandedNavID {
                        focusedTarget = .nav(lastExpandedNavID)
                        return
                    }
                    if direction == .down, action.id == lastActionID {
                        focusedTarget = .action(action.id)
                    }
                }
            }
        }
    }
}

/// Focus-aware trailing action row used for settings and any future shell-level rail actions.
private struct SideRailActionButton: View {
    let action: SideRailActionViewState
    let isSelected: Bool
    let isExpanded: Bool
    let isFocusable: Bool
    let onSelect: () -> Void
    var onMoveToContent: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            FocusAwareView { isFocused in
                HStack(spacing: 12) {
                    Image(systemName: action.systemImage)
                        .font(
                            .system(
                                size: StratixTheme.SideRail.iconSize,
                                weight: isSelected || isFocused ? .semibold : .regular
                            )
                        )
                        .frame(width: 26, height: 26)
                        .foregroundStyle(Color.white.opacity(isSelected || isFocused ? 0.96 : 0.58))

                    if isExpanded {
                        Rectangle()
                            .fill(Color.white.opacity(isSelected ? 0.95 : 0.0))
                            .frame(width: 3, height: 22)

                        Text(action.accessibilityLabel)
                            .font(
                                StratixTypography.rounded(
                                    StratixTheme.SideRail.labelSize,
                                    weight: isSelected || isFocused ? .semibold : .regular,
                                    dynamicTypeSize: dynamicTypeSize
                                )
                            )
                            .lineLimit(1)
                            .foregroundStyle(Color.white.opacity(isSelected || isFocused ? 0.96 : 0.62))
                            .transition(.opacity)

                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: StratixTheme.SideRail.rowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isSelected
                                ? StratixTheme.Colors.focusTint.opacity(isFocused ? 0.88 : 0.72)
                                : (isFocused ? Color.white.opacity(0.10) : Color.clear)
                        )
                )
                .scaleEffect(isFocused ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.13), value: isFocused)
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 14)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
        .disabled(!isFocusable)
        .accessibilityIdentifier("side_rail_action_\(action.id)")
        .accessibilityLabel(Text(action.accessibilityLabel))
        .accessibilityValue(Text(isSelected ? "selected" : "not_selected"))
        .onMoveCommand { direction in
            guard direction == .right else { return }
            onMoveToContent?()
        }
    }
}
