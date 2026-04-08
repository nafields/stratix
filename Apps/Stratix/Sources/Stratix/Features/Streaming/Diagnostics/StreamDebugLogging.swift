// StreamDebugLogging.swift
// Defines stream debug logging for the Streaming / Diagnostics surface.
//

import StratixCore

// MARK: - Stream Debug Logging Helpers
//
// Shared by StreamView and WebRTCVideoSurfaceView.
// Single definition here; both files import it from the same module.

func streamDebugLogsEnabled() -> Bool {
    SettingsStore.snapshotDiagnostics().verboseLogs
}

func streamLog(_ message: @autoclosure () -> String, force: Bool = false) {
    guard force || streamDebugLogsEnabled() else { return }
    print(message())
}
