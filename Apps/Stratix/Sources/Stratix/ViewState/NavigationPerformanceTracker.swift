// NavigationPerformanceTracker.swift
// Defines navigation performance tracker for the ViewState surface.
//

import AsyncAlgorithms
import Foundation
import OSLog
import SwiftUI

/// Captures shell navigation timing and focus telemetry without exposing mutable tracking state to the UI layer.
struct NavigationPerformanceTracker {
    private struct Flow: Sendable {
        let sequence: UInt64
        let signpostID: OSSignpostID
        let startedAt: CFAbsoluteTime
    }

    private enum Event: Sendable {
        case remoteMoveStart(surface: String, direction: String)
        case focusTarget(surface: String, target: String)
        case focusSettled(surface: String, target: String)
        case focusLoss(surface: String)
        case railEntryRequested(surface: String, selectedNavID: String)
        case railSelectedRowFocused(surface: String, target: String)
        case overlayTrigger(name: String, action: String)
        case overlaySettled(name: String, focusTarget: String)
        case routeRestoreStart(surface: String, target: String?)
        case routeRestoreSettled(surface: String, target: String)
        case routeChange(from: String, to: String, reason: String)
        case unexpectedRouteJump(from: String, to: String)
    }

    /// Couples an async stream with its continuation so events can be fed from static entry points.
    private struct EventChannel {
        let stream: AsyncStream<Event>
        let continuation: AsyncStream<Event>.Continuation

        init(
            bufferingPolicy: AsyncStream<Event>.Continuation.BufferingPolicy = .unbounded
        ) {
            var continuation: AsyncStream<Event>.Continuation?
            self.stream = AsyncStream(bufferingPolicy: bufferingPolicy) {
                continuation = $0
            }
            self.continuation = continuation!
        }
    }

    // MARK: - Actor-isolated mutable state

    private actor Core {
        var sequence: UInt64 = 0
        var directionalFlows: [String: Flow] = [:]
        var railEntryFlows: [String: Flow] = [:]
        var overlayFlows: [String: Flow] = [:]
        var routeRestoreFlows: [String: Flow] = [:]
        var lastFocusedTargetBySurface: [String: String] = [:]

        func makeFlow() -> Flow {
            sequence &+= 1
            return Flow(
                sequence: sequence,
                signpostID: OSSignpostID(log: signpostLog),
                startedAt: CFAbsoluteTimeGetCurrent()
            )
        }

        func beginDirectional(surface: String) -> Flow {
            let flow = makeFlow()
            directionalFlows[surface] = flow
            return flow
        }

        func recordFocusTarget(surface: String, target: String) -> (flow: Flow?, previousTarget: String?) {
            let previous = lastFocusedTargetBySurface[surface]
            lastFocusedTargetBySurface[surface] = target
            return (directionalFlows[surface], previous)
        }

        func settleDirectional(surface: String, target: String) -> Flow? {
            lastFocusedTargetBySurface[surface] = target
            return directionalFlows.removeValue(forKey: surface)
        }

        func lastFocusTarget(surface: String) -> String {
            lastFocusedTargetBySurface[surface] ?? "none"
        }

        func beginRailEntry(surface: String) -> Flow {
            let flow = makeFlow()
            railEntryFlows[surface] = flow
            return flow
        }

        func settleRailEntry(surface: String) -> Flow? {
            railEntryFlows.removeValue(forKey: surface)
        }

        func beginOverlay(name: String) -> Flow {
            let flow = makeFlow()
            overlayFlows[name] = flow
            return flow
        }

        func settleOverlay(name: String) -> Flow? {
            overlayFlows.removeValue(forKey: name)
        }

        func beginRouteRestore(surface: String) -> Flow {
            let flow = makeFlow()
            routeRestoreFlows[surface] = flow
            return flow
        }

        func settleRouteRestore(surface: String) -> Flow? {
            routeRestoreFlows.removeValue(forKey: surface)
        }
    }

    private static let core = Core()

    private static let logger = Logger(subsystem: "com.stratix.app", category: "CloudLibraryPerf")
    private static let signpostLog = OSLog(subsystem: "com.stratix.app", category: "CloudLibraryPerf")
    private static let focusEventChannel = EventChannel()
    private static let immediateEventChannel = EventChannel()
    private static let eventDrainTask = startEventDrainTask()
    private static let focusDebounceClock = ContinuousClock()

    static let isEnabled = ProcessInfo.processInfo.environment["STRATIX_DISABLE_NAV_PERF"] != "1"

    // MARK: - Public API (unchanged signatures)

    /// Marks the start of a remote-driven navigation gesture.
    static func recordRemoteMoveStart(surface: String, direction: MoveCommandDirection) {
        enqueue(.remoteMoveStart(surface: surface, direction: direction.perfValue))
    }

    /// Records the latest focused target during directional navigation.
    static func recordFocusTarget(surface: String, target: String) {
        enqueue(.focusTarget(surface: surface, target: target))
    }

    /// Records the target that ultimately settled after a navigation gesture.
    static func recordFocusSettled(surface: String, target: String) {
        enqueue(.focusSettled(surface: surface, target: target))
    }

    /// Records focus loss so route/focus regressions can be correlated later in the log stream.
    static func recordFocusLoss(surface: String) {
        enqueue(.focusLoss(surface: surface))
    }

    /// Marks the start of a side-rail re-entry flow from content back into shell navigation.
    static func recordRailEntryRequested(surface: String, selectedNavID: String) {
        enqueue(.railEntryRequested(surface: surface, selectedNavID: selectedNavID))
    }

    /// Records which rail row ultimately claimed focus during a re-entry flow.
    static func recordRailSelectedRowFocused(surface: String, target: String) {
        enqueue(.railSelectedRowFocused(surface: surface, target: target))
    }

    /// Marks the start of an overlay transition such as opening settings or profile.
    static func recordOverlayTrigger(name: String, action: String) {
        enqueue(.overlayTrigger(name: name, action: action))
    }

    /// Marks the focused target that settled after an overlay transition completed.
    static func recordOverlaySettled(name: String, focusTarget: String) {
        enqueue(.overlaySettled(name: name, focusTarget: focusTarget))
    }

    /// Marks the start of a route-restore flow, including an optional target hint.
    static func recordRouteRestoreStart(surface: String, target: String?) {
        enqueue(.routeRestoreStart(surface: surface, target: target))
    }

    /// Marks the end of a route-restore flow once the final target has settled.
    static func recordRouteRestoreSettled(surface: String, target: String) {
        enqueue(.routeRestoreSettled(surface: surface, target: target))
    }

    /// Records high-level route transitions for shell diagnostics and timeline correlation.
    static func recordRouteChange(from: String, to: String, reason: String) {
        enqueue(.routeChange(from: from, to: to, reason: reason))
    }

    /// Emits an explicit anomaly event when the shell jumps between routes unexpectedly.
    static func recordUnexpectedRouteJump(from: String, to: String) {
        enqueue(.unexpectedRouteJump(from: from, to: to))
    }

    /// Routes focus events through a debounced channel and everything else through the immediate channel.
    private static func enqueue(_ event: Event) {
        guard isEnabled else { return }
        _ = eventDrainTask
        switch event {
        case .focusTarget:
            focusEventChannel.continuation.yield(event)
        default:
            immediateEventChannel.continuation.yield(event)
        }
    }

    /// Starts the background drain task that merges the debounced focus stream with immediate events.
    private static func startEventDrainTask() -> Task<Void, Never> {
        Task(priority: .utility) {
            let debouncedFocusEvents = focusEventChannel.stream.debounce(
                for: .milliseconds(16),
                clock: focusDebounceClock
            )
            for await event in merge(
                debouncedFocusEvents,
                immediateEventChannel.stream
            ) {
                await process(event)
            }
        }
    }

    /// Applies one event to the actor-owned tracking state and emits the corresponding logs/signposts.
    private static func process(_ event: Event) async {
        switch event {
        case .remoteMoveStart(let surface, let direction):
            let flow = await core.beginDirectional(surface: surface)
            logger.log("nav_move_start surface=\(surface, privacy: .public) direction=\(direction, privacy: .public) seq=\(flow.sequence)")
            os_signpost(
                .begin,
                log: signpostLog,
                name: "NavInput",
                signpostID: flow.signpostID,
                "surface=%{public}s direction=%{public}s seq=%{public}llu",
                surface,
                direction,
                flow.sequence
            )

        case .focusTarget(let surface, let target):
            let focusState = await core.recordFocusTarget(surface: surface, target: target)
            if let flow = focusState.flow {
                logger.log(
                    "nav_focus_target surface=\(surface, privacy: .public) target=\(target, privacy: .public) seq=\(flow.sequence) elapsed_ms=\(elapsedMilliseconds(since: flow.startedAt))"
                )
            } else if let previousTarget = focusState.previousTarget, previousTarget != target {
                logger.log(
                    "nav_focus_steal_suspected surface=\(surface, privacy: .public) from=\(previousTarget, privacy: .public) to=\(target, privacy: .public)"
                )
            }

        case .focusSettled(let surface, let target):
            let flow = await core.settleDirectional(surface: surface, target: target)
            if let flow {
                logger.log(
                    "nav_focus_settled surface=\(surface, privacy: .public) target=\(target, privacy: .public) seq=\(flow.sequence) elapsed_ms=\(elapsedMilliseconds(since: flow.startedAt))"
                )
                os_signpost(
                    .end,
                    log: signpostLog,
                    name: "NavInput",
                    signpostID: flow.signpostID,
                    "surface=%{public}s target=%{public}s seq=%{public}llu",
                    surface,
                    target,
                    flow.sequence
                )
            } else {
                logger.log("nav_focus_settled surface=\(surface, privacy: .public) target=\(target, privacy: .public) seq=none")
            }

        case .focusLoss(let surface):
            let previousTarget = await core.lastFocusTarget(surface: surface)
            logger.log("nav_focus_lost surface=\(surface, privacy: .public) last_target=\(previousTarget, privacy: .public)")

        case .railEntryRequested(let surface, let selectedNavID):
            let flow = await core.beginRailEntry(surface: surface)
            logger.log("nav_rail_entry_start surface=\(surface, privacy: .public) selected=\(selectedNavID, privacy: .public) seq=\(flow.sequence)")
            os_signpost(
                .begin,
                log: signpostLog,
                name: "RailEntry",
                signpostID: flow.signpostID,
                "surface=%{public}s selected=%{public}s seq=%{public}llu",
                surface,
                selectedNavID,
                flow.sequence
            )

        case .railSelectedRowFocused(let surface, let target):
            let flow = await core.settleRailEntry(surface: surface)
            if let flow {
                logger.log(
                    "nav_rail_entry_settled surface=\(surface, privacy: .public) target=\(target, privacy: .public) seq=\(flow.sequence) elapsed_ms=\(elapsedMilliseconds(since: flow.startedAt))"
                )
                os_signpost(
                    .end,
                    log: signpostLog,
                    name: "RailEntry",
                    signpostID: flow.signpostID,
                    "surface=%{public}s target=%{public}s seq=%{public}llu",
                    surface,
                    target,
                    flow.sequence
                )
            } else {
                logger.log("nav_rail_entry_settled surface=\(surface, privacy: .public) target=\(target, privacy: .public) seq=none")
            }

        case .overlayTrigger(let name, let action):
            let flow = await core.beginOverlay(name: name)
            logger.log("nav_overlay_trigger overlay=\(name, privacy: .public) action=\(action, privacy: .public) seq=\(flow.sequence)")
            os_signpost(
                .begin,
                log: signpostLog,
                name: "OverlayTransfer",
                signpostID: flow.signpostID,
                "overlay=%{public}s action=%{public}s seq=%{public}llu",
                name,
                action,
                flow.sequence
            )

        case .overlaySettled(let name, let focusTarget):
            let flow = await core.settleOverlay(name: name)
            if let flow {
                logger.log(
                    "nav_overlay_settled overlay=\(name, privacy: .public) focus=\(focusTarget, privacy: .public) seq=\(flow.sequence) elapsed_ms=\(elapsedMilliseconds(since: flow.startedAt))"
                )
                os_signpost(
                    .end,
                    log: signpostLog,
                    name: "OverlayTransfer",
                    signpostID: flow.signpostID,
                    "overlay=%{public}s focus=%{public}s seq=%{public}llu",
                    name,
                    focusTarget,
                    flow.sequence
                )
            } else {
                logger.log("nav_overlay_settled overlay=\(name, privacy: .public) focus=\(focusTarget, privacy: .public) seq=none")
            }

        case .routeRestoreStart(let surface, let target):
            let flow = await core.beginRouteRestore(surface: surface)
            logger.log("nav_route_restore_start surface=\(surface, privacy: .public) target=\(target ?? "none", privacy: .public) seq=\(flow.sequence)")
            os_signpost(
                .begin,
                log: signpostLog,
                name: "RouteRestore",
                signpostID: flow.signpostID,
                "surface=%{public}s target=%{public}s seq=%{public}llu",
                surface,
                target ?? "none",
                flow.sequence
            )

        case .routeRestoreSettled(let surface, let target):
            let flow = await core.settleRouteRestore(surface: surface)
            if let flow {
                logger.log(
                    "nav_route_restore_settled surface=\(surface, privacy: .public) target=\(target, privacy: .public) seq=\(flow.sequence) elapsed_ms=\(elapsedMilliseconds(since: flow.startedAt))"
                )
                os_signpost(
                    .end,
                    log: signpostLog,
                    name: "RouteRestore",
                    signpostID: flow.signpostID,
                    "surface=%{public}s target=%{public}s seq=%{public}llu",
                    surface,
                    target,
                    flow.sequence
                )
            } else {
                logger.log("nav_route_restore_settled surface=\(surface, privacy: .public) target=\(target, privacy: .public) seq=none")
            }

        case .routeChange(let from, let to, let reason):
            logger.log("nav_route_change from=\(from, privacy: .public) to=\(to, privacy: .public) reason=\(reason, privacy: .public)")

        case .unexpectedRouteJump(let from, let to):
            logger.log("nav_route_jump_unexpected from=\(from, privacy: .public) to=\(to, privacy: .public)")
        }
    }

    private static func elapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Int {
        Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000).rounded())
    }
}

private extension MoveCommandDirection {
    var perfValue: String {
        switch self {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        @unknown default: return "unknown"
        }
    }
}
