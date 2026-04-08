// StreamOverlayState.swift
// Defines the stream overlay state.
//

import StratixModels
import StreamingCore

/// Captures the state needed to decide which stream overlay controls should be visible.
struct StreamOverlayState: Equatable {
    enum FocusTarget: Hashable {
        case disconnect
    }

    let lifecycle: StreamLifecycleState
    let overlayInfo: StreamOverlayInfo
    let overlayVisible: Bool
    let hasSession: Bool

    /// Indicates whether the connection-status overlay should be visible.
    var showsConnectionOverlay: Bool {
        lifecycle.isAwaitingOverlayConnection
    }

    /// Indicates whether the active session has enough state to show the details panel.
    var showsDetailsPanel: Bool {
        overlayVisible && hasSession
    }

    /// Exposes a test-only focus target for the disconnect affordance when the overlay is visible.
    var focusTarget: FocusTarget? {
        guard showsDetailsPanel, StratixLaunchMode.isStreamDisconnectUITestModeEnabled else {
            return nil
        }
        return .disconnect
    }
}
