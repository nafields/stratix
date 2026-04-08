// ShellContracts.swift
// Defines shell contracts.
//

import Foundation
import StratixModels

// MARK: - Shell Section

public enum AppShellSection: String, CaseIterable, Identifiable, Sendable {
    case gamePass
    case consoles

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gamePass: return "Game Pass"
        case .consoles: return "My Consoles"
        }
    }

    public var systemImage: String {
        switch self {
        case .gamePass: return "cloud.fill"
        case .consoles: return "tv.fill"
        }
    }
}

// MARK: - Shell Overlay Route

public enum OverlayRoute: Equatable, Sendable {
    case none
    case guide
    case profile
}

// MARK: - Back Action

public enum MainShellBackAction: Equatable, Sendable {
    case closeOverlay
    case returnToPreviousSection
    case none
}

public struct BackActionResolver {
    public init() {}

    public static func resolveMainShellBackAction(
        overlayRoute: OverlayRoute,
        selectedSection: AppShellSection,
        previousSection: AppShellSection
    ) -> MainShellBackAction {
        if overlayRoute != .none {
            return .closeOverlay
        }
        if selectedSection != .gamePass, selectedSection != previousSection {
            return .returnToPreviousSection
        }
        return .none
    }
}

// MARK: - UX Analytics (debug-only event tracker)

@MainActor
public final class UXAnalyticsTracker {
    public static let shared = UXAnalyticsTracker()

    private let sessionStart = Date()
    private var hasLoggedFirstPlay = false
    public private(set) var focusMoveCount = 0

    public init() {}

    public func track(event: String, metadata: [String: String] = [:]) {
        #if DEBUG
        let metadataText = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("[UX] \(event) \(metadataText)")
        #endif
    }

    public func trackFocusMove() {
        focusMoveCount += 1
    }

    public func trackFirstPlayIfNeeded() {
        guard !hasLoggedFirstPlay else { return }
        hasLoggedFirstPlay = true
        let latency = Date().timeIntervalSince(sessionStart)
        track(event: "first_play", metadata: ["seconds": String(format: "%.1f", latency)])
    }
}
