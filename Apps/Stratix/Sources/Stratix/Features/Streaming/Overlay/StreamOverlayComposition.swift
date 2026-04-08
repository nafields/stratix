// StreamOverlayComposition.swift
// Defines stream overlay composition for the Streaming / Overlay surface.
//

import SwiftUI
import StratixModels
import StreamingCore

/// Renders the backdrop artwork and motion treatment behind the streaming overlay.
struct StreamLaunchArtworkView: View {
    let imageURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driftForward = false

    /// Renders the animated artwork layer and its darkening gradient overlay.
    var body: some View {
        ZStack {
            artwork
                .scaleEffect(reduceMotion ? 1.02 : (driftForward ? 1.08 : 1.03))
                .offset(
                    x: reduceMotion ? 0 : (driftForward ? -34 : 26),
                    y: reduceMotion ? 0 : (driftForward ? -18 : 20)
                )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .clipped()
        .accessibilityIdentifier("stream_launch_artwork")
        .task(id: animationIdentity) {
            guard !reduceMotion else {
                driftForward = false
                return
            }
            driftForward = false
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                driftForward = true
            }
        }
    }

    /// Keeps the subtle drift animation in sync with image selection and motion preferences.
    private var animationIdentity: String {
        "\(imageURL?.absoluteString ?? "none")|\(reduceMotion)"
    }

    @ViewBuilder
    /// Chooses the remote artwork when available and falls back to a gradient.
    private var artwork: some View {
        if let imageURL {
            CachedRemoteImage(url: imageURL, kind: .hero, priority: .high, maxPixelSize: 1_920) {
                backgroundFallback
            }
        } else {
            backgroundFallback
        }
    }

    /// Fallback artwork treatment used when no image URL is available.
    private var backgroundFallback: some View {
        LinearGradient(
            colors: [
                StratixTheme.Colors.focusTint.opacity(0.88),
                StratixTheme.Colors.accent.opacity(0.72),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Displays the temporary overlay shown while a stream session is being prepared.
struct StreamPreparingOverlay: View {
    let overlayInfo: StreamOverlayInfo
    let onCancel: () -> Void

    /// Renders the pre-session preparation message and cancel affordance.
    var body: some View {
        VStack(spacing: 18) {
            Text("Preparing Stream")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)

            ProgressView(value: 0.08, total: 1.0)
                .tint(.white)
                .frame(width: 360)

            Text("Loading stream details and reserving a session.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.84))
                .multilineTextAlignment(.center)

            Text("\(overlayInfo.subtitle) • \(overlayInfo.title)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Button("Cancel", action: onCancel)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())
                .padding(.top, 6)
        }
        .padding(.horizontal, 28)
    }
}

/// Composes the runtime overlay around connection status, lifecycle badge, and details panel.
struct StreamStatusOverlay: View {
    let overlayState: StreamOverlayState
    let session: (any StreamingSessionFacade)?
    let surfaceModel: StreamSurfaceModel
    let onCloseOverlay: () -> Void
    let onDisconnect: () -> Void

    /// Renders the connection overlay or details panel based on the current stream state.
    var body: some View {
        ZStack {
            if overlayState.showsConnectionOverlay {
                connectingOverlay
                    .transition(.opacity)
            } else {
                VStack {
                    HStack {
                        Spacer()
                        StreamLifecycleBadge(lifecycle: overlayState.lifecycle)
                            .padding(20)
                    }
                    Spacer()
                }
            }

            if overlayState.showsDetailsPanel, let session {
                StreamOverlayDetailsPanel(
                    session: session,
                    surfaceModel: surfaceModel,
                    overlayState: overlayState,
                    onCloseOverlay: onCloseOverlay,
                    onDisconnect: onDisconnect
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: overlayState.overlayVisible)
    }

    /// Renders the full-screen connection overlay shown before the stream is ready.
    private var connectingOverlay: some View {
        ZStack {
            StreamLaunchArtworkView(imageURL: overlayState.overlayInfo.imageURL)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(overlayState.lifecycle.overlayStateLabel)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)

                ProgressView(value: overlayState.lifecycle.overlayConnectionProgress, total: 1.0)
                    .tint(.white)
                    .frame(width: 360)

                Text(overlayState.lifecycle.overlayConnectionSummary)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .multilineTextAlignment(.center)

                if case .waitingForResources(let secs) = overlayState.lifecycle, let secs, secs > 0 {
                    Text("Estimated wait: ~\(secs) seconds")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                }

                Text("\(overlayState.overlayInfo.subtitle) • \(overlayState.overlayInfo.title)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .multilineTextAlignment(.center)

                Button("Cancel", action: onDisconnect)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
        }
    }
}

/// Compact lifecycle badge shown above the stream when the overlay is not open.
private struct StreamLifecycleBadge: View {
    let lifecycle: StreamLifecycleState

    /// Renders the small colored lifecycle badge.
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(lifecycle.overlayStateColor)
                .frame(width: 10, height: 10)
            Text(lifecycle.overlayStateLabel)
                .font(.caption)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }
}

extension StreamLifecycleState {
    /// Maps lifecycle state into the overlay's traffic-light badge color.
    var overlayStateColor: Color {
        switch self {
        case .connected: return .green
        case .failed: return .red
        case .disconnected: return .gray
        default: return .yellow
        }
    }

    /// Maps lifecycle state into the short overlay label shown in the badge and details panel.
    var overlayStateLabel: String {
        switch self {
        case .idle: return "Idle"
        case .startingSession: return "Starting..."
        case .provisioning: return "Provisioning..."
        case .waitingForResources(let secs):
            if let secs, secs > 0 { return "Queue: ~\(secs)s" }
            return "Waiting for server..."
        case .readyToConnect: return "Connecting..."
        case .connectingWebRTC: return "WebRTC..."
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .disconnected: return "Disconnected"
        case .failed(let error): return "Error: \(error.code.rawValue)"
        }
    }

    /// Converts lifecycle state into a normalized connection progress fraction.
    var overlayConnectionProgress: Double {
        switch self {
        case .idle:
            return 0.0
        case .startingSession:
            return 0.08
        case .provisioning:
            return 0.24
        case .waitingForResources:
            return 0.42
        case .readyToConnect:
            return 0.64
        case .connectingWebRTC:
            return 0.84
        case .connected:
            return 1.0
        case .disconnecting:
            return 0.96
        case .disconnected, .failed:
            return 1.0
        }
    }

    /// Builds the line of copy used below the connection progress bar.
    var overlayConnectionSummary: String {
        switch self {
        case .idle:
            return "Waiting to begin."
        case .startingSession:
            return "Step 1 of 5: Creating the stream session."
        case .provisioning:
            return "Step 2 of 5: Reserving server resources."
        case .waitingForResources:
            return "Step 3 of 5: Waiting for a server slot."
        case .readyToConnect:
            return "Step 4 of 5: Finalizing the transport."
        case .connectingWebRTC:
            return "Step 5 of 5: Negotiating WebRTC and media channels."
        case .connected:
            return "Stream connected."
        case .disconnecting:
            return "Ending the stream."
        case .disconnected:
            return "Stream disconnected."
        case .failed(let error):
            return error.description
        }
    }

    /// Returns true while the stream is still progressing toward an interactive overlay.
    var isAwaitingOverlayConnection: Bool {
        switch self {
        case .connected, .disconnecting, .disconnected, .failed:
            return false
        default:
            return true
        }
    }
}
