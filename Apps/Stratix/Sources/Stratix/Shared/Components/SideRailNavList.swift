// SideRailNavList.swift
// Defines side rail nav list for the Shared / Components surface.
//

import SwiftUI

extension SideRailNavigationView {
    /// Main nav stack for the side rail, including the collapsed-mode re-entry behavior on the selected row.
    var navListView: some View {
        VStack(alignment: .leading, spacing: StratixTheme.SideRail.rowSpacing) {
            ForEach(orderedNavItems) { item in
                let isRowFocusable =
                    isRailExpanded || (collapsedSelectedNavFocusable && item.id == selectedNavID)
                SideRailNavButton(
                    item: item,
                    isSelected: item.id == selectedNavID,
                    isExpanded: isRailExpanded,
                    isFocusable: isRowFocusable,
                    onSelect: {
                        onSelectNav(item.id)
                        collapseRail()
                    },
                    onRequestExpandWhenCollapsed: {
                        guard item.id == selectedNavID else { return }
                        expandRailAndFocusPreferredTarget()
                    },
                    onMoveToContent: moveFocusToContent
                )
                .focused($focusedTarget, equals: .nav(item.id))
                .onMoveCommand { direction in
                    guard isRailExpanded else { return }
                    if direction == .up, item.id == firstExpandedNavID {
                        focusedTarget = .account
                        return
                    }
                    if direction == .down, item.id == lastExpandedNavID, let firstActionID {
                        focusedTarget = .action(firstActionID)
                    }
                }
            }
        }
    }
}

/// Focus-aware side rail nav row that supports both collapsed-icon mode and expanded text mode.
private struct SideRailNavButton: View {
    let item: SideRailNavItemViewState
    let isSelected: Bool
    let isExpanded: Bool
    let isFocusable: Bool
    let onSelect: () -> Void
    var onRequestExpandWhenCollapsed: (() -> Void)? = nil
    var onMoveToContent: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            FocusAwareView { isFocused in
                HStack(spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: StratixTheme.SideRail.iconSize, weight: isSelected || isFocused ? .semibold : .regular))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(Color.white.opacity(isSelected || isFocused ? 0.97 : 0.76))

                    Rectangle()
                        .fill(Color.white.opacity(isSelected ? 0.95 : 0.0))
                        .frame(width: 3, height: 22)

                    if isExpanded {
                        Text(item.title)
                            .font(
                                StratixTypography.rounded(
                                    StratixTheme.SideRail.labelSize,
                                    weight: isSelected || isFocused ? .semibold : .regular,
                                    dynamicTypeSize: dynamicTypeSize
                                )
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(Color.white.opacity(isSelected || isFocused ? 0.98 : 0.82))
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: StratixTheme.SideRail.rowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.clear)
                )
                .scaleEffect(isFocused ? 1.01 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isFocused)
                .gamePassFocusRing(isFocused: isExpanded && isFocused, cornerRadius: 14)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
        .disabled(!isFocusable)
        .accessibilityIdentifier(sideRailNavAccessibilityIdentifier)
        .accessibilityValue(Text(isSelected ? "selected" : "not_selected"))
        .onMoveCommand { direction in
            guard direction == .right || direction == .left else { return }
            if direction == .right {
                onMoveToContent?()
                return
            }
            guard isSelected, !isExpanded else { return }
            onRequestExpandWhenCollapsed?()
        }
    }

    /// Uses stable accessibility IDs so shell UI tests can target each primary route directly.
    private var sideRailNavAccessibilityIdentifier: String {
        switch item.id {
        case .home:
            return "side_rail_nav_home"
        case .library:
            return "side_rail_nav_library"
        case .search:
            return "side_rail_nav_search"
        case .consoles:
            return "side_rail_nav_consoles"
        }
    }
}
