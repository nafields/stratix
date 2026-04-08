// StreamCompactStatsHUD.swift
// Defines stream compact stats hud for the Streaming / Diagnostics surface.
//

import SwiftUI
import StratixModels
import StreamingCore

/// Shows compact runtime, network, and renderer stats over the active stream.
struct StreamCompactStatsHUD: View {
    let session: any StreamingSessionFacade
    let surfaceModel: StreamSurfaceModel
    let showStatsHUD: Bool
    let statsHUDPosition: String
    let overlayVisible: Bool
    let runtimeProbeValue: String
    let showRuntimeStatusProbe: Bool

    /// Renders the HUD only when stream state or diagnostics require it.
    var body: some View {
        if shouldShowHUD {
            let position = forcedLLSRHUDActive ? .topLeft : (HUDPosition(rawValue: statsHUDPosition) ?? .topRight)
            VStack {
                if position.isTop {
                    hudStrip
                    Spacer()
                } else {
                    Spacer()
                    hudStrip
                }
            }
            .frame(maxWidth: .infinity, alignment: position.isLeft ? .leading : .trailing)
            .padding(20)
            .allowsHitTesting(false)
        }
    }

    /// Determines whether the compact HUD should be visible for the current stream state.
    private var shouldShowHUD: Bool {
        !overlayVisible && ((showStatsHUD && session.lifecycle == .connected) || forcedLLSRHUDActive || showRuntimeStatusProbe)
    }

    /// Forces HUD visibility when the renderer enters an LLSR or diagnostic-heavy mode.
    private var forcedLLSRHUDActive: Bool {
        surfaceModel.activeRendererMode.contains("llsr")
            || surfaceModel.activeRendererMode.contains("llfi")
            || surfaceModel.processingStatus != nil
            || surfaceModel.framesFailed != nil
            || surfaceModel.lastError != nil
    }

    /// Builds the compact multi-row stats strip shown in the HUD.
    private var hudStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            hudRow([
                ("Frame Rate", session.stats.framesPerSecond.map { String(format: "%.0f fps", $0) } ?? "—"),
                ("Bitrate", session.stats.bitrateKbps.map { "\($0 / 1000) Mbps" } ?? "—"),
                ("RTT", session.stats.roundTripTimeMs.map { String(format: "%.0f ms", $0) } ?? "—"),
                ("Packet Loss", session.stats.packetsLost.map(String.init) ?? "—")
            ])
            hudRow([
                ("Input", rendererInputResolutionText),
                ("Output", rendererOutputResolutionText),
                ("Upscaler", surfaceModel.activeRendererMode),
                ("Render Delay", surfaceModel.renderLatencyMs.map { String(format: "%.1f ms", $0) } ?? "—")
            ])
            if !rendererDiagnosticsItems.isEmpty {
                hudRow(rendererDiagnosticsItems)
            }
            if let rungSummary = rendererRungSummaryText {
                Text(rungSummary)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let lastError = surfaceModel.lastError {
                Text("Last renderer error: \(shortenedError(lastError))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showRuntimeStatusProbe {
                Text(runtimeProbeValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityValue(runtimeProbeValue)
                    .accessibilityIdentifier("stream_runtime_probe")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Color.white)
    }

    /// Renders one row of key/value diagnostics cells.
    private func hudRow(_ items: [(String, String)]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                hudItem(item.0, item.1)
            }
        }
    }

    /// Renders a single HUD metric cell.
    private func hudItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 10, weight: .semibold, design: .rounded)).opacity(0.8)
        }
    }

    /// Collects additional renderer diagnostics when the current stream exposes them.
    private var rendererDiagnosticsItems: [(String, String)] {
        var items: [(String, String)] = []
        if let status = surfaceModel.processingStatus {
            items.append(("Status", status))
        }
        if let inputRate = session.stats.inputFlushHz {
            items.append(("Input Rate", String(format: "%.0f Hz", inputRate)))
        }
        if let dropped = surfaceModel.framesDroppedByCoalescing {
            items.append(("Video Drops", "\(dropped)"))
        }
        if let failed = surfaceModel.framesFailed {
            items.append(("Failures", "\(failed)"))
        }
        if let framesLost = session.stats.framesLost {
            items.append(("Frame Loss", "\(framesLost)"))
        }
        return items
    }

    /// Formats the current input resolution for diagnostics display.
    private var rendererInputResolutionText: String {
        if let width = surfaceModel.processingInputWidth,
           let height = surfaceModel.processingInputHeight {
            return "\(width)x\(height)"
        }
        if let width = session.stats.negotiatedWidth,
           let height = session.stats.negotiatedHeight {
            return "\(width)x\(height)"
        }
        if let width = session.stats.controlPreferredWidth,
           let height = session.stats.controlPreferredHeight {
            return "\(width)x\(height)"
        }
        return "—"
    }

    /// Formats the current output resolution for diagnostics display.
    private var rendererOutputResolutionText: String {
        if let width = surfaceModel.processingOutputWidth,
           let height = surfaceModel.processingOutputHeight {
            return "\(width)x\(height)"
        }
        if let width = session.stats.messagePreferredWidth,
           let height = session.stats.messagePreferredHeight {
            return "\(width)x\(height)"
        }
        return rendererInputResolutionText
    }

    /// Summarizes the active and failed renderer rungs when the diagnostics are populated.
    private var rendererRungSummaryText: String? {
        var segments: [String] = []
        if !surfaceModel.eligibleRungs.isEmpty {
            segments.append("Available: \(surfaceModel.eligibleRungs.joined(separator: " -> "))")
        }
        if !surfaceModel.deadRungs.isEmpty {
            segments.append("Failed this session: \(surfaceModel.deadRungs.joined(separator: ", "))")
        }
        return segments.isEmpty ? nil : segments.joined(separator: "  ")
    }

    /// Truncates long renderer errors so the compact HUD remains readable.
    private func shortenedError(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: "\n", with: " ")
        if compact.count <= 36 {
            return compact
        }
        return String(compact.prefix(33)) + "..."
    }
}
