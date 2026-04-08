// InputChannel.swift
// Defines input channel.
//

import Foundation
import os
import StratixModels
import InputBridge

// MARK: - Input Channel
//
// Mirrors channel/input.ts — binary input data channel.
// Protocol label: "1.0", ordered: true.
//
// Responsibilities:
//  - On open: send ClientMetadata packet (maxTouchPoints = 1)
//  - On open: start high-frequency polling loop to flush InputQueue and send gamepad frames
//  - On message: handle inbound Vibration (128) and ServerMetadata (16) reports

private struct InputChannelState: Sendable {
    weak var bridge: (any WebRTCBridge)?
    var onVibration: InputChannel.VibrationHandler?
    var onServerMetadata: InputChannel.ServerMetadataHandler?
    var onFlushTelemetry: InputChannel.FlushTelemetryHandler?
    var shouldLogRawInboundMetadata: InputChannel.RawInboundMetadataLogger?

    var lifecycleGeneration: UInt64 = 0
    var didStart = false
    var isRunning = false
    var loopTask: Task<Void, Never>?

    var didLogFirstPacketQueued = false
    var didCaptureLoopExecutionContext = false
    var loopExecutionLabel = "unresolved"
    var lastLoopWakeTimestampMs: Double?
    var lastLoopGapWarningTimestampMs: Double = 0
    var sendInFlight = false
    var sendInFlightStartMs: Double?
    var pendingOutboundPacket: Data?
    var serverVideoWidth: UInt32 = 1920
    var serverVideoHeight: UInt32 = 1080
    var lastEnqueuedPacketTimestampMs: Double?
    var lastSendCompletedTimestampMs: Double?
    var sendIntervalsMs: [Double] = []
    var lastTelemetryEmitTimestampMs: Double = 0
    var lastSendGapWarningTimestampMs: Double = 0
    var lastSlowSendWarningTimestampMs: Double = 0
    var lastSendCompletionDelayWarningTimestampMs: Double = 0
    var consecutiveFastSendIntervals = 0
    var coalescedPacketCountThisSecond = 0
    var blockedSendTickCountThisSecond = 0
    var maxSendInFlightMsThisSecond: Double = 0
    var lastSendHealthLogTimestampMs: Double = 0
}

public final class InputChannel: Sendable {

    public static let label = "input"
    public static let protocolName = "1.0"
    public typealias VibrationHandler = @Sendable (VibrationReport) -> Void
    public typealias ServerMetadataHandler = @Sendable (UInt32, UInt32) -> Void
    public typealias FlushTelemetryHandler = @Sendable (Double, Double) -> Void
    public typealias RawInboundMetadataLogger = @Sendable () -> Bool

    private let queue: InputQueue
    private let state: OSAllocatedUnfairLock<InputChannelState>
    private let instanceID = String(UUID().uuidString.prefix(6)).lowercased()
    /// Set `debug.input.verbose_logs=true` in UserDefaults to re-enable routine input channel diagnostics.
    private let verboseLogsEnabled = UserDefaults.standard.bool(forKey: "debug.input.verbose_logs")
    /// Set `debug.input.warning_logs=true` in UserDefaults to re-enable cadence/scheduler warnings.
    private let warningLogsEnabled = UserDefaults.standard.bool(forKey: "debug.input.warning_logs")

    /// Loop cadence. 125 Hz is enough for controller sampling and reduces scheduler pressure.
    private let loopInterval: Duration = .milliseconds(8)
    private let schedulerStallWarningThresholdMs: Double = 100
    private let activeInputSendGapWarningThresholdMs: Double = 25
    private let activeInputWindowMaxIntervalMs: Double = 750
    private let slowSendWarningThresholdMs: Double = 25
    private let sendCompletionDispatchDelayWarningThresholdMs: Double = 10

    public init(bridge: any WebRTCBridge, queue: InputQueue) {
        self.queue = queue
        self.state = OSAllocatedUnfairLock(initialState: InputChannelState(bridge: bridge))
    }

    public func configure(
        onVibration: VibrationHandler? = nil,
        onServerMetadata: ServerMetadataHandler? = nil,
        onFlushTelemetry: FlushTelemetryHandler? = nil,
        shouldLogRawInboundMetadata: RawInboundMetadataLogger? = nil
    ) {
        state.withLock { state in
            state.onVibration = onVibration
            state.onServerMetadata = onServerMetadata
            state.onFlushTelemetry = onFlushTelemetry
            state.shouldLogRawInboundMetadata = shouldLogRawInboundMetadata
        }
    }

    // MARK: - Called by WebRTCBridge when the channel opens

    public func onOpen() async {
        guard let openGeneration = markStartedIfNeeded() else {
            logVerbose("[InputChannel:\(instanceID)] onOpen ignored (already started)")
            return
        }

        logVerbose("[InputChannel:\(instanceID)] onOpen: sending client metadata and starting loop")
        let metadata = queue.makeInitialMetadata()
        let bridge = bridgeSnapshot()
        try? await bridge?.send(channelKind: .input, data: metadata)

        guard markRunningIfNeeded(for: openGeneration) else {
            logVerbose("[InputChannel:\(instanceID)] onOpen aborted before loop start generation=\(openGeneration)")
            return
        }
        startLoop(generation: openGeneration)
    }

    // MARK: - Loop

    private func startLoop(generation: UInt64) {
        let replacementTask = Task<Void, Never>(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runLoop(generation: generation)
        }
        let previousTask = state.withLock { state in
            let previousTask = state.loopTask
            state.loopTask = replacementTask
            return previousTask
        }
        previousTask?.cancel()
    }

    private func runLoop(generation: UInt64) async {
        await captureLoopExecutionContextIfNeeded(generation: generation)

        while !Task.isCancelled && isRunningActive(generation: generation) {
            do {
                try await Task.sleep(for: loopInterval)
            } catch {
                break
            }

            guard isRunningActive(generation: generation), !Task.isCancelled else { break }
            let wakeMs = monotonicNowMs()
            recordPollWakeTelemetry(nowMs: wakeMs, generation: generation)

            if let packet = queue.flush() {
                let shouldLogFirstPacket = state.withLock { state in
                    guard state.lifecycleGeneration == generation, state.isRunning else { return false }
                    if state.didLogFirstPacketQueued {
                        return false
                    }
                    state.didLogFirstPacketQueued = true
                    return true
                }
                if shouldLogFirstPacket {
                    logVerbose("[InputChannel:\(instanceID)] first binary input packet queued bytes=\(packet.count)")
                }
                enqueuePendingPacket(packet, nowMs: wakeMs, generation: generation)
            }

            maybeStartPendingSend(nowMs: wakeMs, generation: generation)
            maybeEmitSendHealthTelemetry(nowMs: wakeMs, generation: generation)
        }
    }

    private func sendPacket(_ packet: Data) async -> String? {
        do {
            try await bridgeSnapshot()?.send(channelKind: .input, data: packet)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func recordSendDurationTelemetry(
        elapsedMs: Double,
        errorDescription: String?,
        sendQueueLabel: String,
        generation: UInt64
    ) {
        let nowMs = monotonicNowMs()

        if let errorDescription {
            print("[InputChannel:\(instanceID)] warning kind=sendError queue=\(sendQueueLabel) elapsedMs=\(String(format: "%.1f", elapsedMs)) error=\(errorDescription)")
            return
        }

        let shouldWarn = state.withLock { state in
            guard state.lifecycleGeneration == generation else { return false }
            guard elapsedMs > slowSendWarningThresholdMs,
                  (warningLogsEnabled || verboseLogsEnabled),
                  (nowMs - state.lastSlowSendWarningTimestampMs) > 2_000 else {
                return false
            }
            state.lastSlowSendWarningTimestampMs = nowMs
            return true
        }
        guard shouldWarn else { return }

        print("[InputChannel:\(instanceID)] warning kind=sendDuration gapMs=\(String(format: "%.1f", elapsedMs)) thresholdMs=\(String(format: "%.1f", slowSendWarningThresholdMs)) queue=\(sendQueueLabel)")
    }

    private func recordSendCompletionDispatchTelemetry(
        delayMs: Double,
        sendQueueLabel: String,
        generation: UInt64
    ) {
        let nowMs = monotonicNowMs()
        let shouldWarn = state.withLock { state in
            guard state.lifecycleGeneration == generation else { return false }
            guard delayMs > sendCompletionDispatchDelayWarningThresholdMs,
                  (warningLogsEnabled || verboseLogsEnabled),
                  (nowMs - state.lastSendCompletionDelayWarningTimestampMs) > 2_000 else {
                return false
            }
            state.lastSendCompletionDelayWarningTimestampMs = nowMs
            return true
        }
        guard shouldWarn else { return }

        print("[InputChannel:\(instanceID)] warning kind=sendCompletionDispatch gapMs=\(String(format: "%.1f", delayMs)) thresholdMs=\(String(format: "%.1f", sendCompletionDispatchDelayWarningThresholdMs)) queue=\(sendQueueLabel)")
    }

    // MARK: - Inbound messages from server

    public func onMessage(data: Data) {
        guard !data.isEmpty else { return }
        let generation = currentGeneration()
        let reportType = data[0]

        switch reportType {
        case 128:  // ReportType.vibration
            if let report = InputPacket.parseVibration(from: data) {
                logVerbose(
                    "[InputChannel:\(instanceID)] inbound vibration bytes=\(data.count) index=\(report.gamepadIndex) left=\(String(format: "%.2f", report.leftMotorPercent)) right=\(String(format: "%.2f", report.rightMotorPercent)) lt=\(String(format: "%.2f", report.leftTriggerMotorPercent)) rt=\(String(format: "%.2f", report.rightTriggerMotorPercent)) durationMs=\(report.durationMs) delayMs=\(report.delayMs) repeat=\(report.repeatCount)"
                )
                vibrationHandler(for: generation)?(report)
            } else {
                logVerbose("[InputChannel:\(instanceID)] inbound vibration parse failed bytes=\(data.count)")
            }
        case 16:   // ReportType.serverMetadata
            if shouldLogRawInboundMetadata(for: generation) {
                let bytes = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("[InputChannel:\(instanceID)][RawInbound] serverMetadata bytes=\(bytes)")
            }
            if let (width, height) = InputPacket.parseServerMetadata(from: data) {
                let metadataHandler = state.withLock { state -> ServerMetadataHandler? in
                    guard state.lifecycleGeneration == generation, state.didStart else { return nil }
                    state.serverVideoWidth = width
                    state.serverVideoHeight = height
                    return state.onServerMetadata
                }
                metadataHandler?(width, height)
            }
        default:
            break
        }
    }

    // MARK: - Cleanup

    public func destroy() {
        let loopTask = state.withLock { state -> Task<Void, Never>? in
            let loopTask = state.loopTask
            state.lifecycleGeneration &+= 1
            state.didStart = false
            state.isRunning = false
            state.loopTask = nil
            state.onVibration = nil
            state.onServerMetadata = nil
            state.onFlushTelemetry = nil
            state.shouldLogRawInboundMetadata = nil
            state.didLogFirstPacketQueued = false
            state.didCaptureLoopExecutionContext = false
            state.loopExecutionLabel = "unresolved"
            state.lastLoopWakeTimestampMs = nil
            state.lastLoopGapWarningTimestampMs = 0
            state.sendInFlight = false
            state.sendInFlightStartMs = nil
            state.pendingOutboundPacket = nil
            state.lastEnqueuedPacketTimestampMs = nil
            state.lastSendCompletedTimestampMs = nil
            state.sendIntervalsMs.removeAll(keepingCapacity: true)
            state.lastTelemetryEmitTimestampMs = 0
            state.lastSendGapWarningTimestampMs = 0
            state.lastSlowSendWarningTimestampMs = 0
            state.lastSendCompletionDelayWarningTimestampMs = 0
            state.consecutiveFastSendIntervals = 0
            state.coalescedPacketCountThisSecond = 0
            state.blockedSendTickCountThisSecond = 0
            state.maxSendInFlightMsThisSecond = 0
            state.lastSendHealthLogTimestampMs = 0
            return loopTask
        }
        loopTask?.cancel()
        logVerbose("[InputChannel:\(self.instanceID)] destroy completed structured loop")
    }

    // MARK: - Internal helpers

    private func markStartedIfNeeded() -> UInt64? {
        state.withLock { state in
            guard !state.didStart else { return nil }
            state.didStart = true
            return state.lifecycleGeneration
        }
    }

    private func markRunningIfNeeded(for generation: UInt64) -> Bool {
        state.withLock { state in
            guard state.lifecycleGeneration == generation, state.didStart, !state.isRunning else { return false }
            state.isRunning = true
            return true
        }
    }

    private func isRunningActive(generation: UInt64) -> Bool {
        state.withLock { state in
            state.lifecycleGeneration == generation && state.isRunning
        }
    }

    private func currentGeneration() -> UInt64 {
        state.withLock { $0.lifecycleGeneration }
    }

    private func bridgeSnapshot() -> (any WebRTCBridge)? {
        state.withLock { $0.bridge }
    }

    private func vibrationHandler(for generation: UInt64) -> VibrationHandler? {
        state.withLock { state in
            guard state.lifecycleGeneration == generation, state.didStart else { return nil }
            return state.onVibration
        }
    }

    private func shouldLogRawInboundMetadata(for generation: UInt64) -> Bool {
        let logger = state.withLock { state -> RawInboundMetadataLogger? in
            guard state.lifecycleGeneration == generation, state.didStart else { return nil }
            return state.shouldLogRawInboundMetadata
        }
        return logger?() == true
    }

    private func wallClockNowMs() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private func monotonicNowMs() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000.0
    }

    private func captureLoopExecutionContextIfNeeded(
        generation: UInt64,
        file: StaticString = #fileID,
        line: UInt = #line
    ) async {
        let didCapture = state.withLock { state -> Bool in
            guard state.lifecycleGeneration == generation, !state.didCaptureLoopExecutionContext else { return false }
            state.didCaptureLoopExecutionContext = true
            state.loopExecutionLabel = "structured-loop"
            return true
        }
        guard didCapture else { return }

        let isMainThread = await MainActor.run { Thread.isMainThread }
        let loopExecutionLabel = state.withLock { $0.loopExecutionLabel }
        let message = "[InputChannel:\(instanceID)] loop context captured main=\(isMainThread) queue=\(loopExecutionLabel) tsMs=\(wallClockNowMs()) callsite=\(String(describing: file)):\(line)"
        logVerbose(message)
    }

    private func logGapWarning(
        kind: String,
        gapMs: Double,
        thresholdMs: Double,
        queueLabel: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        guard warningLogsEnabled || verboseLogsEnabled else { return }
        let message = "[InputChannel:\(instanceID)] warning kind=\(kind) gapMs=\(String(format: "%.1f", gapMs)) thresholdMs=\(String(format: "%.1f", thresholdMs)) main=\(Thread.isMainThread) queue=\(queueLabel) tsMs=\(wallClockNowMs()) callsite=\(String(describing: file)):\(line)"
        print(message)
    }

    private func recordPollWakeTelemetry(nowMs: Double, generation: UInt64) {
        let telemetry = state.withLock { state -> (gapMs: Double?, shouldWarn: Bool, queueLabel: String) in
            guard state.lifecycleGeneration == generation else {
                return (nil, false, state.loopExecutionLabel)
            }
            let gapMs = state.lastLoopWakeTimestampMs.map { max(0, nowMs - $0) }
            state.lastLoopWakeTimestampMs = nowMs
            guard let gapMs,
                  gapMs > schedulerStallWarningThresholdMs,
                  (nowMs - state.lastLoopGapWarningTimestampMs) > 2_000 else {
                return (gapMs, false, state.loopExecutionLabel)
            }
            state.lastLoopGapWarningTimestampMs = nowMs
            return (gapMs, true, state.loopExecutionLabel)
        }
        guard let gapMs = telemetry.gapMs, telemetry.shouldWarn else { return }
        logGapWarning(
            kind: "loopWake",
            gapMs: gapMs,
            thresholdMs: schedulerStallWarningThresholdMs,
            queueLabel: telemetry.queueLabel
        )
    }

    private func recordPacketEnqueueTelemetry(nowMs: Double, generation: UInt64) {
        state.withLock { state in
            guard state.lifecycleGeneration == generation else { return }
            state.lastEnqueuedPacketTimestampMs = nowMs
        }
    }

    private func enqueuePendingPacket(_ packet: Data, nowMs: Double, generation: UInt64) {
        recordPacketEnqueueTelemetry(nowMs: nowMs, generation: generation)
        state.withLock { state in
            guard state.lifecycleGeneration == generation else { return }
            if state.sendInFlight {
                state.blockedSendTickCountThisSecond += 1
            }
            if state.sendInFlight || state.pendingOutboundPacket != nil {
                state.coalescedPacketCountThisSecond += 1
            }
            state.pendingOutboundPacket = packet
        }
    }

    private func maybeStartPendingSend(nowMs: Double, generation: UInt64) {
        let nextSend = state.withLock { state -> (packet: Data, startMs: Double)? in
            guard state.lifecycleGeneration == generation,
                  state.isRunning,
                  !state.sendInFlight,
                  let pendingOutboundPacket = state.pendingOutboundPacket else {
                return nil
            }
            state.pendingOutboundPacket = nil
            state.sendInFlight = true
            state.sendInFlightStartMs = nowMs
            return (pendingOutboundPacket, nowMs)
        }
        guard let nextSend else { return }

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let errorDescription = await self.sendPacket(nextSend.packet)
            let completionNowMs = self.monotonicNowMs()
            self.finishSend(
                startedAtMs: nextSend.startMs,
                completedAtMs: completionNowMs,
                errorDescription: errorDescription,
                generation: generation
            )
        }
    }

    private func finishSend(
        startedAtMs: Double,
        completedAtMs: Double,
        errorDescription: String?,
        generation: UInt64
    ) {
        let sendQueueLabel = state.withLock { state -> String? in
            guard state.lifecycleGeneration == generation else { return nil }
            if verboseLogsEnabled {
                state.maxSendInFlightMsThisSecond = max(
                    state.maxSendInFlightMsThisSecond,
                    max(0, completedAtMs - startedAtMs)
                )
            }
            state.sendInFlight = false
            state.sendInFlightStartMs = nil
            return state.loopExecutionLabel
        }
        guard let sendQueueLabel else { return }

        recordSendDurationTelemetry(
            elapsedMs: completedAtMs - startedAtMs,
            errorDescription: errorDescription,
            sendQueueLabel: sendQueueLabel,
            generation: generation
        )
        recordSendCompletionDispatchTelemetry(
            delayMs: 0,
            sendQueueLabel: sendQueueLabel,
            generation: generation
        )
        recordSendSpacingTelemetry(nowMs: completedAtMs, generation: generation)

        maybeStartPendingSend(nowMs: completedAtMs, generation: generation)
        maybeEmitSendHealthTelemetry(nowMs: completedAtMs, generation: generation)
    }

    private func recordSendSpacingTelemetry(nowMs: Double, generation: UInt64) {
        enum TelemetryDecision {
            case none
            case warn(intervalMs: Double, queueLabel: String)
            case emit(hz: Double, jitterMs: Double, handler: FlushTelemetryHandler)
        }

        let decision = state.withLock { state -> TelemetryDecision in
            guard state.lifecycleGeneration == generation else { return .none }

            let previousCompletionMs = state.lastSendCompletedTimestampMs
            state.lastSendCompletedTimestampMs = nowMs
            guard let previousCompletionMs else { return .none }

            let intervalMs = max(0, nowMs - previousCompletionMs)

            guard intervalMs <= activeInputWindowMaxIntervalMs else {
                state.sendIntervalsMs.removeAll(keepingCapacity: true)
                state.consecutiveFastSendIntervals = 0
                return .none
            }

            state.sendIntervalsMs.append(intervalMs)
            if state.sendIntervalsMs.count > 256 {
                state.sendIntervalsMs.removeFirst(state.sendIntervalsMs.count - 256)
            }

            if intervalMs <= activeInputSendGapWarningThresholdMs {
                state.consecutiveFastSendIntervals += 1
                return .none
            }

            let hadRecentFastCadence = state.consecutiveFastSendIntervals >= 5
            state.consecutiveFastSendIntervals = 0
            if hadRecentFastCadence, (nowMs - state.lastSendGapWarningTimestampMs) > 2_000 {
                state.lastSendGapWarningTimestampMs = nowMs
                return .warn(intervalMs: intervalMs, queueLabel: state.loopExecutionLabel)
            }

            guard (nowMs - state.lastTelemetryEmitTimestampMs) >= 1_000,
                  !state.sendIntervalsMs.isEmpty else {
                return .none
            }
            guard let lastEnqueuedPacketTimestampMs = state.lastEnqueuedPacketTimestampMs,
                  (nowMs - lastEnqueuedPacketTimestampMs) <= activeInputWindowMaxIntervalMs else {
                state.sendIntervalsMs.removeAll(keepingCapacity: true)
                state.consecutiveFastSendIntervals = 0
                return .none
            }

            let meanMs = state.sendIntervalsMs.reduce(0, +) / Double(state.sendIntervalsMs.count)
            let variance = state.sendIntervalsMs.reduce(0) { partial, value in
                let delta = value - meanMs
                return partial + (delta * delta)
            } / Double(state.sendIntervalsMs.count)
            state.lastTelemetryEmitTimestampMs = nowMs

            guard let handler = state.onFlushTelemetry else { return .none }
            let hz = meanMs > 0 ? (1_000.0 / meanMs) : 0
            let jitterMs = sqrt(max(variance, 0))
            return .emit(hz: hz, jitterMs: jitterMs, handler: handler)
        }

        switch decision {
        case .none:
            break
        case let .warn(intervalMs, queueLabel):
            logGapWarning(
                kind: "activeInputSendCadence",
                gapMs: intervalMs,
                thresholdMs: activeInputSendGapWarningThresholdMs,
                queueLabel: queueLabel
            )
        case let .emit(hz, jitterMs, handler):
            guard currentGeneration() == generation else { return }
            handler(hz, jitterMs)
        }
    }

    private func maybeEmitSendHealthTelemetry(nowMs: Double, generation: UInt64) {
        guard verboseLogsEnabled else { return }

        let logSnapshot = state.withLock { state -> (coalesced: Int, blocked: Int, maxInFlightMs: Double, queueLabel: String)? in
            guard state.lifecycleGeneration == generation else { return nil }
            guard (nowMs - state.lastSendHealthLogTimestampMs) >= 1_000 else { return nil }
            guard let lastEnqueuedPacketTimestampMs = state.lastEnqueuedPacketTimestampMs,
                  (nowMs - lastEnqueuedPacketTimestampMs) <= activeInputWindowMaxIntervalMs else {
                state.coalescedPacketCountThisSecond = 0
                state.blockedSendTickCountThisSecond = 0
                state.maxSendInFlightMsThisSecond = 0
                return nil
            }

            state.lastSendHealthLogTimestampMs = nowMs
            let liveInFlightMs: Double
            if state.sendInFlight, let sendInFlightStartMs = state.sendInFlightStartMs {
                liveInFlightMs = max(0, nowMs - sendInFlightStartMs)
            } else {
                liveInFlightMs = 0
            }
            let maxInFlightMs = max(state.maxSendInFlightMsThisSecond, liveInFlightMs)
            let snapshot = (
                coalesced: state.coalescedPacketCountThisSecond,
                blocked: state.blockedSendTickCountThisSecond,
                maxInFlightMs: maxInFlightMs,
                queueLabel: state.loopExecutionLabel
            )
            state.coalescedPacketCountThisSecond = 0
            state.blockedSendTickCountThisSecond = 0
            state.maxSendInFlightMsThisSecond = 0
            return snapshot
        }
        guard let logSnapshot else { return }

        let runtimeStats = bridgeSnapshot()?.dataChannelRuntimeStats(channelKind: .input)
        let readyState = runtimeStats.map { String($0.readyStateRawValue) } ?? "n/a"
        let bufferedAmountBytes = runtimeStats?.bufferedAmountBytes.map(String.init) ?? "n/a"

        print(
            "[InputChannel:\(instanceID)] info kind=sendHealth inFlightMaxMs=\(String(format: "%.1f", logSnapshot.maxInFlightMs)) coalesced=\(logSnapshot.coalesced) blockedSendTick=\(logSnapshot.blocked) readyState=\(readyState) bufferedAmountBytes=\(bufferedAmountBytes) queue=\(logSnapshot.queueLabel)"
        )
    }

    private func logVerbose(_ message: @autoclosure () -> String) {
        guard verboseLogsEnabled else { return }
        print(message())
    }
}
