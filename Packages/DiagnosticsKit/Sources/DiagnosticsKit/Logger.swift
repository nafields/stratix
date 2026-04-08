// Logger.swift
// Defines logger.
//

import Foundation
import os

/// Categorizes repo-wide logs so auth, streaming, and UI events stay filterable in Console.
public enum LogCategory: String, Sendable {
    case auth = "Auth"
    case api = "API"
    case streaming = "Streaming"
    case webrtc = "WebRTC"
    case input = "Input"
    case video = "Video"
    case audio = "Audio"
    case ui = "UI"
}

/// Centralizes the command-line and environment switches that enable verbose repo logging.
public enum AppLogConfiguration {
    public static let enableArgument = "-stratix-app-logs"
    public static let enableEnvironmentKey = "STRATIX_APP_LOGS"

    /// Resolves whether verbose app logging should be enabled for the current process.
    public static var isEnabled: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains(enableArgument) {
            return true
        }
        let normalized = processInfo.environment[enableEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

private struct LoggerStoreState: Sendable {
    var blockedRequestCount = 0
    var isLoggingEnabled = AppLogConfiguration.isEnabled
}

/// Holds mutable logging flags that need to be shared safely across package boundaries.
public final class LoggerStore: Sendable {
    public static let shared = LoggerStore()
    private let state = OSAllocatedUnfairLock(initialState: LoggerStoreState())

    private init() {}

    /// Counts test-time requests blocked by the URLProtocol harness.
    public var blockedRequestCount: Int {
        state.withLock(\.blockedRequestCount)
    }

    /// Records that one additional request was intercepted by the blocking test protocol.
    public func incrementBlockedRequestCount() {
        state.withLock { $0.blockedRequestCount += 1 }
    }

    /// Exposes the mutable runtime logging flag shared across the repo.
    public var isLoggingEnabled: Bool {
        state.withLock(\.isLoggingEnabled)
    }

    /// Overrides the current process-wide logging flag without changing launch arguments.
    public func setLoggingEnabled(_ isEnabled: Bool) {
        state.withLock { $0.isLoggingEnabled = isEnabled }
    }
}

/// Thin OSLog wrapper that respects the repo's runtime logging toggle.
public struct GLogger: Sendable {
    private static let subsystem = "com.stratix.app"
    private let logger: os.Logger

    /// Global toggle used by all GLogger instances in the current process.
    public static var isEnabled: Bool {
        get { LoggerStore.shared.isLoggingEnabled }
        set { LoggerStore.shared.setLoggingEnabled(newValue) }
    }

    /// Creates a logger bound to one of the repo's shared log categories.
    public init(category: LogCategory) {
        self.logger = os.Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    public func debug(_ message: String) {
        guard Self.isEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        guard Self.isEnabled else { return }
        logger.info("\(message, privacy: .public)")
    }

    public func warning(_ message: String) {
        guard Self.isEnabled else { return }
        logger.warning("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        guard Self.isEnabled else { return }
        logger.error("\(message, privacy: .public)")
    }

    public func fault(_ message: String) {
        guard Self.isEnabled else { return }
        logger.fault("\(message, privacy: .public)")
    }
}
