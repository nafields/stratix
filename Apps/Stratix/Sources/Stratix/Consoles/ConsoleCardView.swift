// ConsoleCardView.swift
// Defines the console card view used in the Consoles surface.
//

import SwiftUI
import XCloudAPI

struct ConsoleCardView: View {
    let console: RemoteConsole
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            FocusAwareView { isFocused in
                GlassCard(
                    cornerRadius: 22,
                    fill: isFocused ? Color.white.opacity(0.12) : Color.black.opacity(0.34),
                    stroke: Color.white.opacity(isFocused ? 0.16 : 0.10),
                    shadowOpacity: isFocused ? 0.28 : 0.16
                ) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center, spacing: 18) {
                            consoleArtwork

                            VStack(alignment: .leading, spacing: 6) {
                                Text(console.deviceName)
                                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                                    .foregroundStyle(StratixTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                Text(console.consoleType)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(StratixTheme.Colors.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 12)

                            statusBadge
                        }

                        HStack(spacing: 10) {
                            consolePill(icon: "play.fill", text: "Remote Play")
                            if console.outOfHomeWarning {
                                consolePill(icon: "house.slash.fill", text: "Out-of-home limits", style: .warning)
                            }
                            if console.wirelessWarning {
                                consolePill(icon: "wifi.exclamationmark", text: "Wireless warning", style: .warning)
                            }
                            if console.isDevKit {
                                consolePill(icon: "hammer.fill", text: "DevKit", style: .neutral)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(StratixTheme.Colors.focusTint)
                            Text("Start remote play")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(StratixTheme.Colors.textPrimary)
                            Spacer(minLength: 10)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.white.opacity(isFocused ? 0.95 : 0.45))
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(isFocused ? 0.10 : 0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(isFocused ? 0.14 : 0.08), lineWidth: 1)
                        )
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, minHeight: 248, alignment: .topLeading)
                }
                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 22)
                .zIndex(isFocused ? 10 : 0)
            }
        }
        .buttonStyle(CloudLibraryTVButtonStyle())
        .gamePassDisableSystemFocusEffect()
    }

    private var consoleArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [powerColor.opacity(0.28), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: consoleIcon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(powerColor)
        }
        .frame(width: 86, height: 86)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var consoleIcon: String {
        let type = console.consoleType.lowercased()
        if type.contains("series") {
            return "xbox.logo"
        }
        if type.contains("one") {
            return "tv.fill"
        }
        return "gamecontroller.fill"
    }

    private var powerColor: Color {
        switch console.powerState.lowercased() {
        case "on":
            return Color(red: 0.0, green: 0.78, blue: 0.12)
        case "standby":
            return Color.orange
        default:
            return Color.white.opacity(0.55)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(powerColor)
                .frame(width: 10, height: 10)
            Text(console.powerState.capitalized)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(StratixTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private enum ConsolePillStyle {
        case neutral
        case warning
    }

    private func consolePill(icon: String, text: String, style: ConsolePillStyle = .neutral) -> some View {
        let foreground: Color = style == .warning ? Color.orange : StratixTheme.Colors.textSecondary
        return HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
