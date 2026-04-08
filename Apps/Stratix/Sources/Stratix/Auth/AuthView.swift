// AuthView.swift
// Defines the signed-out landing screen and the first-step Microsoft sign-in call to action.
//

import SwiftUI
import StratixCore

/// Presents the signed-out shell and starts the device-code login flow.
struct AuthView: View {
    @Environment(SessionController.self) private var sessionController
    @FocusState private var isSignInFocused: Bool
    @State private var focusSettler = FocusSettleDebouncer()
    @State private var pendingFocusTask: Task<Void, Never>?

    /// Builds the signed-out landing screen, including the focused sign-in CTA and auth errors.
    var body: some View {
        ZStack {
            CloudLibraryAmbientBackground(imageURL: nil)

            LinearGradient(
                colors: [Color.black.opacity(0.7), Color(red: 0.01, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GlassCard(
                cornerRadius: StratixTheme.Radius.xl,
                fill: Color.black.opacity(0.42),
                stroke: Color.white.opacity(0.12),
                shadowOpacity: 0.34
            ) {
                VStack(spacing: 28) {
                    StratixAppIcon()
                        .frame(width: 180, height: 180)

                    Text("Welcome to STRATIX")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textPrimary)

                    Text("Sign in with your Microsoft account to sync your cloud library and jump into Xbox streaming.")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(StratixTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 920)

                    if let error = sessionController.lastAuthError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(StratixTheme.Colors.warning)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button(action: {
                        Task { await sessionController.beginSignIn() }
                    }) {
                        FocusAwareView { isFocused in
                            CloudLibraryActionButton(
                                action: .init(
                                    id: "sign-in",
                                    title: "Sign In With Microsoft",
                                    systemImage: "person.crop.circle.badge.checkmark",
                                    style: .primary
                                ),
                                isFocused: isFocused
                            )
                            .gamePassFocusRing(isFocused: isFocused, cornerRadius: 24)
                        }
                    }
                    .focused($isSignInFocused)
                    .buttonStyle(CloudLibraryTVButtonStyle())
                    .gamePassDisableSystemFocusEffect()
                    .accessibilityIdentifier("auth_sign_in_button")
                }
                .padding(.horizontal, 72)
                .padding(.vertical, 56)
                .frame(maxWidth: 1120)
            }
        }
        .accessibilityIdentifier("auth_root")
        .onAppear {
            pendingFocusTask?.cancel()
            pendingFocusTask = Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                isSignInFocused = true
            }
        }
        .onChange(of: isSignInFocused) { _, isFocused in
            focusSettler.cancel()
            if isFocused {
                NavigationPerformanceTracker.recordFocusTarget(surface: "auth", target: "sign_in")
                focusSettler.schedule(debounce: StratixConstants.Timing.focusTargetDebounceNanoseconds) {
                    NavigationPerformanceTracker.recordFocusSettled(surface: "auth", target: "sign_in")
                }
            } else {
                NavigationPerformanceTracker.recordFocusLoss(surface: "auth")
            }
        }
        .onMoveCommand { direction in
            NavigationPerformanceTracker.recordRemoteMoveStart(surface: "auth", direction: direction)
        }
        .onDisappear {
            focusSettler.cancel()
        }
    }
}

#if DEBUG
#Preview("AuthView", traits: .fixedLayout(width: 1920, height: 1080)) {
    let coordinator = AppCoordinator()
    AuthView()
        .environment(coordinator.sessionController)
}
#endif
