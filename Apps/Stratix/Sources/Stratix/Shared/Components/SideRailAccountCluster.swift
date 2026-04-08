// SideRailAccountCluster.swift
// Defines side rail account cluster for the Shared / Components surface.
//

import SwiftUI

extension SideRailNavigationView {
    /// Top account/profile entry point for the side rail, sharing the same collapse-to-content behavior as the rest of the rail.
    var accountClusterView: some View {
        Button {
            onSelectAction("profile-menu")
            collapseRail()
        } label: {
            FocusAwareView { isFocused in
                profileAvatar
                    .frame(width: 40, height: 40)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(
                        Circle()
                            .fill(
                                activeUtilityRoute == .profile
                                    ? StratixTheme.Colors.focusTint.opacity(isFocused ? 0.88 : 0.72)
                                    : (isFocused ? Color.white.opacity(0.14) : Color.clear)
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                activeUtilityRoute == .profile
                                    ? Color.white.opacity(isFocused ? 0.28 : 0.18)
                                    : Color.white.opacity(isFocused ? 0.22 : 0.10),
                                lineWidth: 1
                            )
                    )
                    .gamePassFocusRing(isFocused: isFocused, cornerRadius: 26)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
        .focused($focusedTarget, equals: .account)
        .disabled(!isRailExpanded)
        .accessibilityIdentifier("side_rail_action_profile_menu")
        .accessibilityLabel(Text("\(state.accountName), \(state.accountStatus)"))
        .accessibilityHint(Text("Open profile menu"))
        .accessibilityValue(Text(activeUtilityRoute == .profile ? "selected" : "not_selected"))
        .onMoveCommand { direction in
            if direction == .right {
                moveFocusToContent()
                return
            }
            guard direction == .down else { return }
            if let firstExpandedNavID {
                focusedTarget = .nav(firstExpandedNavID)
            } else if let firstActionID {
                focusedTarget = .action(firstActionID)
            }
        }
    }

    /// Resolves the remote avatar when available and falls back to initials when profile art is missing.
    @ViewBuilder
    var profileAvatar: some View {
        if let imageURL = state.profileImageURL {
            CachedRemoteImage(
                url: imageURL,
                kind: .avatar,
                priority: .normal,
                maxPixelSize: 256,
                contentMode: .fill
            ) {
                avatarFallback
            }
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    /// Gradient initials fallback used while profile artwork is unavailable.
    var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [StratixTheme.Colors.focusTint, StratixTheme.Colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(state.profileInitials.isEmpty ? "P" : state.profileInitials)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}
