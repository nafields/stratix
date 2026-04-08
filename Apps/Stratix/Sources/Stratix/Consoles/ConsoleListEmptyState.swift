// ConsoleListEmptyState.swift
// Defines the console list empty state.
//

import SwiftUI

extension ConsoleListView {
    var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GlassCard(
                    cornerRadius: 24,
                    fill: Color.black.opacity(0.34),
                    stroke: Color.white.opacity(0.10),
                    shadowOpacity: 0.16
                ) {
                    HStack(alignment: .top, spacing: 22) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Image(systemName: "xbox.logo")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(StratixTheme.Colors.focusTint)
                        }
                        .frame(width: 110, height: 110)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("No Consoles Found")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(StratixTheme.Colors.textPrimary)

                            Text("We couldn’t find any Xbox consoles ready for remote play on this account.")
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(StratixTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Turn on your console, enable remote features, and confirm it has internet access before refreshing.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(StratixTheme.Colors.textMuted)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                consoleInfoPill(icon: "tv.fill", text: "Console on")
                                consoleInfoPill(icon: "gearshape.fill", text: "Remote features enabled")
                                consoleInfoPill(icon: "wifi", text: "Network reachable")
                            }
                            .padding(.top, 2)

                            Button {
                                Task { await refreshConsoles() }
                            } label: {
                                FocusAwareView { isFocused in
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 18, weight: .bold))
                                        Text("Refresh Consoles")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(isFocused ? Color.black : StratixTheme.Colors.textPrimary)
                                    .padding(.horizontal, 18)
                                    .frame(minWidth: 250, minHeight: 58, alignment: .leading)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(isFocused ? StratixTheme.Colors.focusTint : Color.white.opacity(0.08))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(Color.white.opacity(isFocused ? 0.14 : 0.08), lineWidth: 1)
                                    )
                                    .gamePassFocusRing(isFocused: isFocused, cornerRadius: 30)
                                }
                            }
                            .buttonStyle(CloudLibraryTVButtonStyle())
                            .gamePassDisableSystemFocusEffect()
                            .focused($focusedTarget, equals: .refresh)
                            .onMoveCommand { direction in
                                guard direction == .left else { return }
                                onRequestSideRailEntry()
                            }
                            .padding(.top, 4)

                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showTroubleshootDetails.toggle()
                                }
                            } label: {
                                FocusAwareView { isFocused in
                                    HStack(spacing: 10) {
                                        Image(systemName: "wrench.and.screwdriver.fill")
                                            .font(.system(size: 16, weight: .bold))
                                        Text(showTroubleshootDetails ? "Hide Troubleshoot" : "Troubleshoot")
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(isFocused ? Color.black : StratixTheme.Colors.textPrimary)
                                    .padding(.horizontal, 18)
                                    .frame(minWidth: 220, minHeight: 52, alignment: .leading)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(isFocused ? StratixTheme.Colors.focusTint : Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(Color.white.opacity(isFocused ? 0.14 : 0.08), lineWidth: 1)
                                    )
                                    .gamePassFocusRing(isFocused: isFocused, cornerRadius: 26)
                                }
                            }
                            .buttonStyle(CloudLibraryTVButtonStyle())
                            .gamePassDisableSystemFocusEffect()
                            .focused($focusedTarget, equals: .troubleshoot)
                            .onMoveCommand { direction in
                                guard direction == .left else { return }
                                onRequestSideRailEntry()
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(24)
                }
                .frame(maxWidth: 1120, alignment: .leading)

                if showTroubleshootDetails {
                    GlassCard(
                        cornerRadius: 20,
                        fill: Color.white.opacity(0.025),
                        stroke: Color.white.opacity(0.08),
                        shadowOpacity: 0.08
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Troubleshoot Discovery")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(StratixTheme.Colors.textPrimary)

                            consoleChecklistRow(icon: "person.crop.circle.badge.checkmark", text: "Use the same Xbox account on console and this app.")
                            consoleChecklistRow(icon: "gearshape.2.fill", text: "Enable remote features and instant-on standby in console settings.")
                            consoleChecklistRow(icon: "wifi.router.fill", text: "Avoid guest/VPN networks while testing remote discovery.")
                            consoleChecklistRow(icon: "arrow.clockwise.circle.fill", text: "Refresh after each change to validate discovery.")
                        }
                        .padding(20)
                    }
                    .frame(maxWidth: 1120, alignment: .leading)
                }

                GlassCard(
                    cornerRadius: 20,
                    fill: Color.white.opacity(0.025),
                    stroke: Color.white.opacity(0.08),
                    shadowOpacity: 0.08
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Remote Play Checklist")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.textPrimary)

                        consoleChecklistRow(icon: "checkmark.shield.fill", text: "Sign in with the same Xbox account used on your console.")
                        consoleChecklistRow(icon: "antenna.radiowaves.left.and.right", text: "Enable remote features in Xbox settings.")
                        consoleChecklistRow(icon: "moon.zzz.fill", text: "Use Sleep/Instant-On if you want wake-from-idle support.")
                        consoleChecklistRow(icon: "network", text: "Make sure the console stays connected to the internet.")
                    }
                    .padding(20)
                }
                .frame(maxWidth: 1120, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }
}

private func consoleInfoPill(icon: String, text: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
        Text(text)
            .lineLimit(1)
    }
    .font(.system(size: 13, weight: .bold, design: .rounded))
    .foregroundStyle(StratixTheme.Colors.textSecondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Capsule().fill(Color.white.opacity(0.05)))
    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
}

private func consoleChecklistRow(icon: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(StratixTheme.Colors.focusTint)
            .frame(width: 18)
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(StratixTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
