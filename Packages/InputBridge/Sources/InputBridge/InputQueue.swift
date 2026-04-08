// InputQueue.swift
// Defines input queue.
//

import Foundation
import os
import StratixModels

// MARK: - Input Queue
// Accumulates input frames between flush intervals (matching inputqueue in JS source).

/// Coalesces polled controller state into the next packet payload for the streaming input channel.
public final class InputQueue: Sendable {

    private struct State: Sendable {
        var sequence: UInt32 = 0
        var pendingInjectedGamepadFrames: [GamepadInputFrame] = []
        var pendingGamepadFrames: [GamepadInputFrame] = []
        var pendingTimingFrames: [FrameTimingMetadata] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    // MARK: - Enqueue

    /// Stores the most recent polled frame for each controller until the next flush.
    public func enqueueGamepadFrame(_ frame: GamepadInputFrame) {
        state.withLock { state in
            if let existingIndex = state.pendingGamepadFrames.lastIndex(where: { $0.gamepadIndex == frame.gamepadIndex }) {
                // Mirror the JS client poll model: keep the latest state per gamepad for the next flush.
                state.pendingGamepadFrames[existingIndex] = frame
            } else {
                state.pendingGamepadFrames.append(frame)
            }
        }
    }

    /// Appends a synthetic/input-management gamepad frame without coalescing.
    /// Used for one-shot button taps (for example, pause when opening the overlay).
    public func enqueueInjectedGamepadFrame(_ frame: GamepadInputFrame) {
        state.withLock { $0.pendingInjectedGamepadFrames.append(frame) }
    }

    /// Queues renderer timing metadata to piggyback on the next outbound input packet.
    public func enqueueTimingFrame(_ frame: FrameTimingMetadata) {
        state.withLock { $0.pendingTimingFrames.append(frame) }
    }

    // MARK: - Flush

    /// Builds and returns a binary packet containing all queued frames, then clears the queue.
    /// Returns nil if there's nothing to send.
    public func flush() -> Data? {
        let (sequence, injectedGamepadFrames, gamepadFrames, timingFrames) = state.withLock { state in
            let sequence = nextSequenceLocked(state: &state)
            let injectedGamepadFrames = state.pendingInjectedGamepadFrames
            let gamepadFrames = state.pendingGamepadFrames
            let timingFrames = state.pendingTimingFrames
            state.pendingInjectedGamepadFrames.removeAll(keepingCapacity: true)
            state.pendingGamepadFrames.removeAll(keepingCapacity: true)
            state.pendingTimingFrames.removeAll(keepingCapacity: true)
            return (sequence, injectedGamepadFrames, gamepadFrames, timingFrames)
        }

        let queuedGamepadFrames = injectedGamepadFrames + gamepadFrames

        guard !queuedGamepadFrames.isEmpty || !timingFrames.isEmpty else { return nil }

        return InputPacket.gamepadPacket(
            sequence: sequence,
            frames: queuedGamepadFrames,
            timingFrames: timingFrames
        )
    }

    /// Returns the initial ClientMetadata packet that must be sent when the input channel opens.
    public func makeInitialMetadata() -> Data {
        let seq = state.withLock { state in
            nextSequenceLocked(state: &state)
        }
        return InputPacket.clientMetadata(sequence: seq, maxTouchPoints: 1)
    }

    /// Advances the monotonically increasing sequence number embedded in outbound packets.
    private func nextSequenceLocked(state: inout State) -> UInt32 {
        let seq = state.sequence
        state.sequence &+= 1
        return seq
    }
}
