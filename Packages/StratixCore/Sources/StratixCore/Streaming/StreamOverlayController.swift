// StreamOverlayController.swift
// Defines the stream overlay controller that coordinates the Streaming surface.
//

import Foundation

@MainActor
final class StreamOverlayController {
    private var commandContinuation: AsyncStream<StreamUICommand>.Continuation?
    private var pendingCommands: [StreamUICommand] = []

    func makeCommandStream() -> AsyncStream<StreamUICommand> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { [weak self] continuation in
            guard let self else { return }
            commandContinuation = continuation
            let buffered = pendingCommands
            pendingCommands.removeAll(keepingCapacity: true)
            for command in buffered {
                continuation.yield(command)
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.commandContinuation = nil
                }
            }
        }
    }

    func requestOverlayToggle() {
        enqueue(.toggleOverlay)
    }

    func requestDisconnect() {
        enqueue(.disconnect)
    }

    func toggleStatsHUD() {
        enqueue(.toggleStatsHUD)
    }

    func reset() {
        commandContinuation = nil
        pendingCommands.removeAll(keepingCapacity: true)
    }

    private func enqueue(_ command: StreamUICommand) {
        if let commandContinuation {
            commandContinuation.yield(command)
            return
        }

        pendingCommands.append(command)
        if pendingCommands.count > 16 {
            pendingCommands.removeFirst(pendingCommands.count - 16)
        }
    }
}
