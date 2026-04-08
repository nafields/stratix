// StratixBranding.swift
// Defines stratix branding for the Shared / Components surface.
//

import SwiftUI

struct StratixWordmark: View {
    var color: Color = .black

    var body: some View {
        VStack(spacing: 10) {
            Text("STRATIX")
                .font(.system(size: 84, weight: .black, design: .rounded))
                .italic()
                .tracking(3)
                .foregroundStyle(color)

            HStack(spacing: 16) {
                ForEach(wordmarkBarWidths, id: \.self) { width in
                    Capsule()
                        .fill(color)
                        .frame(width: width, height: 14)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var wordmarkBarWidths: [CGFloat] {
        [180, 260, 130]
    }
}

struct StratixAppIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(StratixTheme.Colors.focusTint)
            .overlay(
                StratixWordmark(color: .black)
                    .scaleEffect(0.24)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.2), lineWidth: 2)
            )
            .aspectRatio(1, contentMode: .fit)
    }
}

#if DEBUG
#Preview("StratixBranding", traits: .fixedLayout(width: 1920, height: 1080)) {
    ZStack {
        Color.black
        VStack(spacing: 28) {
            StratixWordmark(color: .white)
            StratixAppIcon()
                .frame(width: 220, height: 220)
        }
    }
}
#endif
