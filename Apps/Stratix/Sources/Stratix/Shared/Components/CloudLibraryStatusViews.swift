// CloudLibraryStatusViews.swift
// Defines cloud library status views for the Shared / Components surface.
//

import SwiftUI

/// Full-screen loading overlay used while the detail route is hydrating enough state to render.
struct DetailRouteLoadingView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            DetailRouteSpinnerView()
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("detail_route_loading")
    }
}

/// Small branded spinner used by detail-route loading and other lightweight shell loading states.
struct DetailRouteSpinnerView: View {
    @State private var rotationDegrees: Double = 0
    @State private var pulseScale: CGFloat = 0.96

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.78)
            .stroke(
                AngularGradient(
                    colors: [
                        StratixTheme.Colors.focusTint.opacity(0.84),
                        StratixTheme.Colors.focusTint,
                        StratixTheme.Colors.focusTint.opacity(0.80)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 34, height: 34)
            .rotationEffect(.degrees(rotationDegrees))
            .scaleEffect(pulseScale)
            .shadow(color: StratixTheme.Colors.focusTint.opacity(0.28), radius: 6, x: 0, y: 1)
            .onAppear(perform: startAnimations)
    }

    /// Starts the continuous spin and pulse pair once the spinner becomes visible.
    private func startAnimations() {
        rotationDegrees = 0
        pulseScale = 0.96
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            rotationDegrees = 360
        }
        withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
            pulseScale = 1.02
        }
    }
}
#if DEBUG
#Preview("CloudLibraryStatusViews", traits: .fixedLayout(width: 1920, height: 1080)) {
    ZStack {
        Color.black
        VStack(alignment: .leading, spacing: 18) {
            DetailRouteSpinnerView()
                .padding(.top, 10)
        }
        .padding(40)
    }
}
#endif
