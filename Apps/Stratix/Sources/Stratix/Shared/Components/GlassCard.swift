// GlassCard.swift
// Defines glass card for the Shared / Components surface.
//

import SwiftUI
import StratixCore

/// Reusable elevated panel surface that prefers system glass on tvOS 26 while keeping a
/// non-glass fallback for earlier runtimes.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let fill: Color
    let stroke: Color
    let shadowOpacity: Double
    let content: Content

    init(
        cornerRadius: CGFloat = StratixTheme.Radius.lg,
        fill: Color = StratixTheme.Colors.elevatedGlass,
        stroke: Color = StratixTheme.Colors.glassStroke,
        shadowOpacity: Double = 0.24,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.fill = fill
        self.stroke = stroke
        self.shadowOpacity = shadowOpacity
        self.content = content()
    }

    var body: some View {
        content
            .background(
                glassSurface
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: 30, x: 0, y: 18)
    }

    /// Switches between system glass material and the repo's legacy filled-card fallback.
    @ViewBuilder
    private var glassSurface: some View {
        if #available(tvOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(fill), in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
        }
    }
}

/// Shared custom focus ring tuned for tvOS and accessibility settings rather than the system default effect.
struct FocusRingModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    @Environment(SettingsStore.self) private var settingsStore

    func body(content: Content) -> some View {
        let highVisibilityFocus = settingsStore.accessibility.highVisibilityFocus
        let reduceMotion = settingsStore.accessibility.reduceMotion
        let thinStroke = highVisibilityFocus ? 2.0 : 1.5
        let darkStroke = highVisibilityFocus ? 6.0 : 4.8
        let brightStroke = highVisibilityFocus ? 3.0 : 2.2
        let paddingInset = highVisibilityFocus ? -3.4 : -2.8
        let focusScale: CGFloat = reduceMotion ? 1.0 : (highVisibilityFocus ? 1.055 : 1.04)

        content
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            isFocused ? Color.white.opacity(0.42) : Color.clear,
                            lineWidth: isFocused ? thinStroke : 0
                        )

                    RoundedRectangle(cornerRadius: cornerRadius + 2.5, style: .continuous)
                        .stroke(
                            isFocused ? Color.black.opacity(0.72) : Color.clear,
                            lineWidth: isFocused ? darkStroke : 0
                        )
                        .padding(isFocused ? paddingInset : 0)

                    RoundedRectangle(cornerRadius: cornerRadius + 2.5, style: .continuous)
                        .stroke(
                            isFocused ? Color.white.opacity(0.98) : Color.clear,
                            lineWidth: isFocused ? brightStroke : 0
                        )
                        .padding(isFocused ? paddingInset : 0)
                }
                .shadow(color: .white.opacity(isFocused ? (highVisibilityFocus ? 0.28 : 0.20) : 0), radius: highVisibilityFocus ? 16 : 12)
            )
            .scaleEffect(isFocused ? focusScale : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.56 : 0.16), radius: isFocused ? 30 : 12, y: isFocused ? 18 : 6)
            .zIndex(isFocused ? 10 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
    }
}

/// Minimal press-state button style that layers on top of custom tvOS focus treatment.
struct CloudLibraryTVButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Exposes the current tvOS focus state to child builders that need to render custom focus UI.
struct FocusAwareView<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isFocused)
    }
}

extension View {
    /// Applies the repo's custom focus ring and disables the default tvOS focus effect.
    func gamePassFocusRing(isFocused: Bool, cornerRadius: CGFloat = StratixTheme.Radius.lg) -> some View {
        modifier(FocusRingModifier(isFocused: isFocused, cornerRadius: cornerRadius))
            .gamePassDisableSystemFocusEffect()
    }

    @ViewBuilder
    func gamePassDisableSystemFocusEffect() -> some View {
#if os(tvOS)
        if #available(tvOS 17.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
#else
        self
#endif
    }
}

#if DEBUG
#Preview("GlassCard", traits: .fixedLayout(width: 1920, height: 1080)) {
    ZStack {
        Color.black
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Glass Card")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Reusable elevated panel style for game surfaces.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(24)
            .frame(width: 760, alignment: .leading)
        }
    }
    .environment(SettingsStore())
}
#endif
