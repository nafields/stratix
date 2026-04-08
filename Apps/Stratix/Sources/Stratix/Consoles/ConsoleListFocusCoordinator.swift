// ConsoleListFocusCoordinator.swift
// Defines the console-route focus targets and the restore rules used by the console shell.
//

import SwiftUI
import StratixCore

/// Enumerates the focusable console-route targets that participate in restore behavior.
enum ConsoleFocusTarget: Hashable {
    case refresh
    case troubleshoot
    case console(String)
}

/// Resolves primary-focus choices for the console inventory route.
enum ConsoleListFocusCoordinator {
    /// Chooses the best focus target after refresh or shell restore.
    static func preferredTarget(
        isLoading: Bool,
        consoleIDs: [String],
        lastFocusedConsoleID: String?
    ) -> ConsoleFocusTarget? {
        guard !isLoading else { return nil }
        if let lastFocusedConsoleID, consoleIDs.contains(lastFocusedConsoleID) {
            return .console(lastFocusedConsoleID)
        }
        if let firstConsoleID = consoleIDs.first {
            return .console(firstConsoleID)
        }
        return .refresh
    }

    /// Converts a focus target into the diagnostics identifier used by navigation tracking.
    static func focusTargetID(_ target: ConsoleFocusTarget) -> String {
        switch target {
        case .refresh:
            return "refresh"
        case .troubleshoot:
            return "troubleshoot"
        case .console(let consoleID):
            return consoleID
        }
    }
}

extension ConsoleListView {
    /// Updates navigation diagnostics and last-focused-console tracking when focus changes.
    func handleFocusedTargetChange(_ target: ConsoleFocusTarget?) {
        focusSettler.cancel()
        guard let target else {
            NavigationPerformanceTracker.recordFocusLoss(surface: "consoles")
            return
        }

        let targetID = ConsoleListFocusCoordinator.focusTargetID(target)
        if case .console(let consoleID) = target {
            lastFocusedConsoleID = consoleID
        }
        NavigationPerformanceTracker.recordFocusTarget(surface: "consoles", target: targetID)
        focusSettler.schedule(debounce: StratixConstants.Timing.focusTargetDebounceNanoseconds) {
            NavigationPerformanceTracker.recordFocusSettled(surface: "consoles", target: targetID)
        }
    }

    /// Clears stale focus state and re-requests primary focus when the console set changes.
    func handleConsoleIDsChange(_ consoleIDs: [String]) {
        if let lastFocusedConsoleID, !consoleIDs.contains(lastFocusedConsoleID) {
            self.lastFocusedConsoleID = nil
        }
        guard shouldRequestDeferredFocus, !consoleController.isLoading else { return }
        shouldRequestDeferredFocus = false
        requestPrimaryFocus()
    }

    /// Schedules the best available focus target once the console route is ready to accept focus.
    func requestPrimaryFocus() {
        guard let preferredTarget = ConsoleListFocusCoordinator.preferredTarget(
            isLoading: consoleController.isLoading,
            consoleIDs: consoleIDs,
            lastFocusedConsoleID: lastFocusedConsoleID
        ) else {
            shouldRequestDeferredFocus = true
            return
        }

        shouldRequestDeferredFocus = false
        pendingFocusTask?.cancel()
        pendingFocusTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedTarget = preferredTarget
        }
    }
}
