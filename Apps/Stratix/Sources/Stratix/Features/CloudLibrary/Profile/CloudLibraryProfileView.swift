// CloudLibraryProfileView.swift
// Defines the cloud library profile view used in the CloudLibrary / Profile surface.
//

import Foundation
import SwiftUI

struct CloudLibraryProfileView: View {
    enum Action: Hashable {
        case openConsoles
        case openSettings
        case refreshProfile
        case refreshFriends
        case signOut
    }

    let profileName: String
    let profileStatus: String
    let profileStatusDetail: String
    let profileDetail: String
    let profileImageURL: URL?
    let profileInitials: String
    let gameDisplayName: String?
    let gamertag: String?
    let gamerscore: String?
    let cloudLibraryCount: Int
    let consoleCount: Int
    let friendsCount: Int
    let friendsLastUpdatedAt: Date?
    let friendsErrorText: String?
    var onOpenConsoles: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRefreshProfileData: () -> Void = {}
    var onRefreshFriends: () -> Void = {}
    var onSignOut: () -> Void = {}
    var onRequestSideRailEntry: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedAction: Action?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                profileHeaderCard
                quickActionsCard
                statusGrid
            }
            .padding(.top, StratixTheme.Shell.contentTopPadding)
            .padding(.horizontal, StratixTheme.Layout.outerPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: 1720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("route_profile_root")
    }

    private var profileHeaderCard: some View {
        CloudLibraryPageSectionCard(title: "Profile", subtitle: "Your Xbox account and shell summary") {
            HStack(alignment: .top, spacing: 18) {
                profileAvatar
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(displayName)
                            .font(StratixTypography.rounded(32, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(StratixTheme.Colors.textPrimary)
                            .lineLimit(1)

                        Text(profileStatus)
                            .font(StratixTypography.rounded(12, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(profileStatusBadgeTextColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(profileStatusBadgeFill))
                    }

                    if let secondaryName, !secondaryName.isEmpty {
                        Text(secondaryName)
                            .font(StratixTypography.rounded(15, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(StratixTheme.Colors.textSecondary)
                    }

                    if !profileStatusDetail.isEmpty {
                        Text(profileStatusDetail)
                            .font(StratixTypography.rounded(17, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(StratixTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !profileDetail.isEmpty {
                        Text(profileDetail)
                            .font(StratixTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(StratixTheme.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .leading)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(Array(summaryPills.indices), id: \.self) { index in
                            summaryPills[index]
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var quickActionsCard: some View {
        CloudLibraryPageSectionCard(title: "Quick Actions", subtitle: "Jump to the most useful shell destinations and account tasks") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14, alignment: .leading),
                    GridItem(.flexible(), spacing: 14, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 14
            ) {
                quickActionButton(
                    title: "Consoles",
                    systemImage: "tv.fill",
                    focusTarget: .openConsoles,
                    accessibilityIdentifier: "profile_rail_consoles",
                    wantsRailEntryOnLeft: true,
                    action: onOpenConsoles
                )
                quickActionButton(
                    title: "Settings",
                    systemImage: "gearshape.fill",
                    focusTarget: .openSettings,
                    accessibilityIdentifier: "profile_rail_settings",
                    action: onOpenSettings
                )
                quickActionButton(
                    title: "Refresh Profile",
                    systemImage: "arrow.clockwise",
                    focusTarget: .refreshProfile,
                    wantsRailEntryOnLeft: true,
                    action: onRefreshProfileData
                )
                quickActionButton(
                    title: "Refresh Friends",
                    systemImage: "person.2.badge.gearshape.fill",
                    focusTarget: .refreshFriends,
                    action: onRefreshFriends
                )
                quickActionButton(
                    title: "Sign Out",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    focusTarget: .signOut,
                    accessibilityIdentifier: "profile_rail_signout",
                    wantsRailEntryOnLeft: true,
                    destructive: true,
                    action: onSignOut
                )
            }
        }
    }

    private var statusGrid: some View {
        HStack(alignment: .top, spacing: 18) {
            CloudLibraryPageSectionCard(title: "Shell Status", subtitle: "What this shell knows right now") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibraryStatLine(icon: "person.crop.circle.fill", text: "Presence: \(profileStatus)")
                    if !profileStatusDetail.isEmpty {
                        CloudLibraryStatLine(icon: "bolt.horizontal.fill", text: profileStatusDetail)
                    }
                    CloudLibraryStatLine(icon: "slider.horizontal.3", text: profileDetail)
                    CloudLibraryStatLine(icon: "cloud.fill", text: "\(cloudLibraryCount) cloud titles ready")
                    CloudLibraryStatLine(icon: "tv.fill", text: "\(consoleCount) consoles available")
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            CloudLibraryPageSectionCard(title: "Friends", subtitle: "Presence refresh and social summary") {
                VStack(alignment: .leading, spacing: 12) {
                    CloudLibraryStatLine(
                        icon: "person.2.fill",
                        text: friendsCount == 1 ? "1 friend profile loaded" : "\(friendsCount) friend profiles loaded"
                    )

                    if let friendsRefreshText, !friendsRefreshText.isEmpty {
                        CloudLibraryStatLine(icon: "clock.fill", text: friendsRefreshText)
                    }

                    if let friendsErrorText, !friendsErrorText.isEmpty {
                        CloudLibraryStatLine(icon: "exclamationmark.triangle.fill", text: friendsErrorText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var displayName: String {
        sanitized(gameDisplayName) ?? profileName
    }

    private var secondaryName: String? {
        if let gamertag = sanitized(gamertag), gamertag != displayName {
            return gamertag
        }
        if displayName != profileName {
            return profileName
        }
        return nil
    }

    private var summaryPills: [CloudLibraryStatPill] {
        var pills: [CloudLibraryStatPill] = [
            CloudLibraryStatPill(icon: "cloud.fill", text: "\(cloudLibraryCount) cloud titles"),
            CloudLibraryStatPill(icon: "tv.fill", text: "\(consoleCount) consoles"),
            CloudLibraryStatPill(icon: "person.2.fill", text: friendsCount == 1 ? "1 friend" : "\(friendsCount) friends")
        ]
        if let gamerscore = sanitized(gamerscore) {
            pills.append(CloudLibraryStatPill(icon: "star.fill", text: "\(gamerscore)G"))
        }
        return pills
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let profileImageURL {
            CachedRemoteImage(
                url: profileImageURL,
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

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [StratixTheme.Colors.focusTint, StratixTheme.Colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(profileInitials.isEmpty ? "P" : profileInitials)
                .font(StratixTypography.rounded(30, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(Color.black.opacity(0.82))
        }
        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private var friendsRefreshText: String? {
        guard let friendsLastUpdatedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Friends refreshed \(formatter.localizedString(for: friendsLastUpdatedAt, relativeTo: Date()))"
    }

    private var profileStatusBadgeFill: Color {
        let lower = profileStatus.lowercased()
        if lower.contains("offline") {
            return Color.white.opacity(0.10)
        }
        if lower.contains("busy") || lower.contains("away") {
            return Color.orange.opacity(0.22)
        }
        return StratixTheme.Colors.focusTint
    }

    private var profileStatusBadgeTextColor: Color {
        let lower = profileStatus.lowercased()
        if lower.contains("offline") || lower.contains("busy") || lower.contains("away") {
            return StratixTheme.Colors.textPrimary
        }
        return .black
    }

    private func quickActionButton(
        title: String,
        systemImage: String,
        focusTarget: Action,
        accessibilityIdentifier: String? = nil,
        wantsRailEntryOnLeft: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        CloudLibrarySettingsActionButton(
            title: title,
            systemImage: systemImage,
            destructive: destructive,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
        .focused($focusedAction, equals: focusTarget)
        .modifier(DefaultProfileFocusModifier(focusedAction: $focusedAction, focusTarget: focusTarget))
        .onMoveCommand { direction in
            guard wantsRailEntryOnLeft, direction == .left else { return }
            onRequestSideRailEntry()
        }
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct DefaultProfileFocusModifier: ViewModifier {
    let focusedAction: FocusState<CloudLibraryProfileView.Action?>.Binding
    let focusTarget: CloudLibraryProfileView.Action

    @ViewBuilder
    func body(content: Content) -> some View {
        if focusTarget == .openConsoles {
            content.defaultFocus(focusedAction, .openConsoles)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("CloudLibraryProfileView", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryProfileView(
        profileName: "stratix-preview",
        profileStatus: "Online",
        profileStatusDetail: "Playing Forza Horizon 5",
        profileDetail: "Balanced latency • H.264 • Low latency • Stats on",
        profileImageURL: nil,
        profileInitials: "S",
        gameDisplayName: "Stratix Preview",
        gamertag: "stratix-preview",
        gamerscore: "88,420",
        cloudLibraryCount: 248,
        consoleCount: 2,
        friendsCount: 44,
        friendsLastUpdatedAt: Date().addingTimeInterval(-180),
        friendsErrorText: nil
    )
}
#endif
