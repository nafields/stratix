#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, assert_contains, assert_not_contains, fail, read_text

errors: list[str] = []

required_paths = [
    rel("Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSession.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSessionFacade.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSessionModel.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingRuntime.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingSessionRuntime.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingSessionBridgeDelegate.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Replay/StreamingSessionTrackReplay.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Rendering/StreamingSessionRendererTelemetry.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Metrics/StreamingSessionMetricsSupport.swift"),
    rel("Packages/DiagnosticsKit/Sources/DiagnosticsKit/StreamMetricsPipeline.swift"),
    rel("Packages/DiagnosticsKit/Sources/DiagnosticsKit/StreamMetricsSnapshot.swift"),
    rel("Packages/DiagnosticsKit/Sources/DiagnosticsKit/StreamMetricsExportWriter.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/State/StreamSurfaceModel.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/State/StreamOverlayState.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RenderSurfaceCoordinator.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RendererAttachmentCoordinator.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/WebRTCVideoSurfaceView.swift"),
]
errors.extend(require_paths(required_paths))

streaming_session = rel("Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSession.swift")
session_model = rel("Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSessionModel.swift")
session_runtime = rel("Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingSessionRuntime.swift")
session_bridge = rel("Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingSessionBridgeDelegate.swift")
session_replay = rel("Packages/StreamingCore/Sources/StreamingCore/Replay/StreamingSessionTrackReplay.swift")
session_renderer = rel("Packages/StreamingCore/Sources/StreamingCore/Rendering/StreamingSessionRendererTelemetry.swift")
session_metrics = rel("Packages/StreamingCore/Sources/StreamingCore/Metrics/StreamingSessionMetricsSupport.swift")
stream_view = rel("Apps/Stratix/Sources/Stratix/Features/Streaming/StreamView.swift")
stream_overlay = rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Overlay/StreamOverlayComposition.swift")
render_surface_coordinator = rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RenderSurfaceCoordinator.swift")
webrtc_surface = rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/WebRTCVideoSurfaceView.swift")
renderer_attachment = rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RendererAttachmentCoordinator.swift")
metrics_pipeline = rel("Packages/DiagnosticsKit/Sources/DiagnosticsKit/StreamMetricsPipeline.swift")
metrics_snapshot = rel("Packages/DiagnosticsKit/Sources/DiagnosticsKit/StreamMetricsSnapshot.swift")
metrics_export = rel("Packages/DiagnosticsKit/Sources/DiagnosticsKit/StreamMetricsExportWriter.swift")
stats_hud = rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Diagnostics/StreamCompactStatsHUD.swift")

errors.extend(assert_contains(streaming_session, [
    "public final class StreamingSession: StreamingSessionFacade",
    "@ObservationIgnored let model: StreamingSessionModel",
    "public var inputQueueRef: InputQueue { model.inputQueue }",
]))

errors.extend(assert_not_contains(streaming_session, [
    "private actor StreamingRuntime",
    "let runtime: StreamingRuntime",
    "let statsPoller: StreamingSessionStatsPoller",
    "let statsCollector: StatsCollector",
    "var rendererTelemetry = StreamingSessionRendererTelemetry()",
    "var runtimeSnapshot: StreamingRuntimeSnapshot",
    "var videoTrackReplay:",
    "var audioTrackReplay:",
]))

errors.extend(assert_contains(session_model, [
    "final class StreamingSessionModel",
    "let runtime: StreamingRuntime",
    "let bridgeDelegate: StreamingSessionBridgeDelegate",
    "let metricsSupport: StreamingSessionMetricsSupport",
    "var runtimeSnapshot: StreamingRuntimeSnapshot",
    "var rendererTelemetry = StreamingSessionRendererTelemetry()",
    "func resetForStreamStart()",
    "func resetForStreamStop()",
]))

errors.extend(assert_contains(session_runtime, [
    "struct StreamingRuntimeSnapshot: Sendable, Equatable",
    "protocol StreamingRuntimeDelegate: AnyObject, Sendable",
    "extension StreamingSession: StreamingRuntimeDelegate",
]))

errors.extend(assert_contains(session_bridge, [
    "final class StreamingSessionBridgeDelegate: WebRTCBridgeDelegate, Sendable",
    "await runtime.handleConnectionStateChange(state, generation: generation)",
    "await runtime.handleVideoTrack(token, generation: generation)",
    "await runtime.handleAudioTrack(token, generation: generation)",
]))

errors.extend(assert_contains(session_replay, [
    "func runtimeDidReceiveVideoTrack(_ track: AnyObject)",
    "func runtimeDidReceiveAudioTrack(_ track: AnyObject)",
    "func replayVideoTrackIfNeeded()",
    "func replayAudioTrackIfNeeded()",
    "StreamMetricsPipeline.shared.recordMilestone(.firstFrameReceived)",
]))

errors.extend(assert_contains(session_renderer, [
    "struct StreamingSessionRendererTelemetry: Sendable, Equatable",
    "public func setRendererMode(_ mode: String)",
    "public func setRendererTelemetry(",
    "public func reportRendererDecodeFailure(_ details: String)",
]))

errors.extend(assert_contains(session_metrics, [
    "final class StreamingSessionMetricsSupport",
    "let statsCollector = StatsCollector()",
    "private let statsPoller: StreamingSessionStatsPoller",
    "func setDiagnosticsPollingEnabled(_ enabled: Bool) -> Bool",
    "func startStatsPolling()",
    "func stopStatsPolling()",
]))

errors.extend(assert_contains(stream_view, [
    "@State private var surfaceModel = StreamSurfaceModel()",
    "@State private var renderSurfaceCoordinator = RenderSurfaceCoordinator()",
    "@State private var rendererAttachmentCoordinator = RendererAttachmentCoordinator()",
    "await startStreamIfNeeded()",
    "for await command in streamController.makeCommandStream()",
    "renderSurfaceCoordinator.handleSessionChange(",
    "renderSurfaceCoordinator.handleDisappear(",
    "renderSurfaceCoordinator.requestExit(",
    "renderSurfaceCoordinator.syncDiagnosticsPolling(",
    "callbacks: renderSurfaceCoordinator.rendererCallbacks(",
]))

errors.extend(assert_not_contains(stream_view, [
    "StreamViewBinder",
    "private let streamBinder = StreamViewBinder()",
    "session?.onVideoTrack =",
    "setDiagnosticsPollingEnabled(",
    "reportRendererDecodeFailure(",
    "RendererAttachmentCoordinator.Callbacks(",
    "switch settingsStore.diagnostics.upscalingFloorBehavior",
]))

errors.extend(assert_contains(stream_overlay, [
    "let overlayState: StreamOverlayState",
    "let surfaceModel: StreamSurfaceModel",
]))

errors.extend(assert_not_contains(stream_overlay, [
    "@Binding var showOverlay",
    "StreamMetricsPipeline.shared",
]))

errors.extend(assert_contains(render_surface_coordinator, [
    "final class RenderSurfaceCoordinator",
    "func handleSessionChange(",
    "func syncDiagnosticsPolling(",
    "func requestExit(",
    "StreamMetricsPipeline.shared.recordMilestone(.firstFrameRendered)",
]))

errors.extend(assert_contains(webrtc_surface, [
    "struct WebRTCVideoSurfaceView: UIViewRepresentable",
    "let attachmentCoordinator: RendererAttachmentCoordinator",
    "func makeCoordinator() -> RendererAttachmentCoordinator",
    "coordinator.clear()",
]))

errors.extend(assert_not_contains(webrtc_surface, [
    "final class Coordinator",
    "switch settingsStore.diagnostics.upscalingFloorBehavior",
    "reportRendererDecodeFailureIfNeeded",
]))

errors.extend(assert_contains(renderer_attachment, [
    "final class RendererAttachmentCoordinator: NSObject",
    "static func make(",
    "func install(",
    "func update(",
    "func clear()",
]))

errors.extend(assert_contains(metrics_pipeline, [
    "public final class StreamMetricsPipeline: Sendable",
    "public func recordMilestone(",
    "public func snapshot() -> StreamMetricsPipelineSnapshot",
    "public func export(",
]))

errors.extend(assert_contains(metrics_snapshot, [
    "public enum StreamMetricsMilestone",
    "case authReady = \"auth_ready\"",
    "case firstFrameRendered = \"first_frame_rendered\"",
    "case reconnectFailure = \"reconnect_failure\"",
    "public struct StreamMetricsSnapshot: Sendable, Equatable",
]))

errors.extend(assert_contains(metrics_export, [
    "public struct StreamMetricsExportWriter: Sendable",
    "public func export(snapshot: StreamMetricsSnapshot) throws -> Data",
    "public func exportString(snapshot: StreamMetricsSnapshot) throws -> String",
]))

errors.extend(assert_not_contains(stats_hud, [
    "StreamMetricsPipeline.shared.recordMilestone(",
    "StreamMetricsPipeline.shared.recordPerformanceEvent(",
]))

milestone_files = [
    rel("Packages/StratixCore/Sources/StratixCore/SessionController.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamHomeLaunchWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamCloudLaunchWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamOverlayVisibilityCoordinator.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Streaming/StreamReconnectCoordinator.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingSessionRuntime.swift"),
    rel("Packages/StreamingCore/Sources/StreamingCore/Replay/StreamingSessionTrackReplay.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RenderSurfaceCoordinator.swift"),
]

errors.extend(require_paths(milestone_files))
if sum("StreamMetricsPipeline.shared.recordMilestone(" in read_text(path) for path in milestone_files) != len(milestone_files):
    errors.append("Stage 6 runtime/metrics boundary lost one or more required milestone call sites.")

for legacy in [
    rel("Tools/ci/check_stage6_runtime_boundary.py"),
    rel("Tools/ci/check_stage6_metrics_pipeline.py"),
]:
    if legacy.exists():
        errors.append(f"{legacy}: duplicate weaker Stage 6 guard must not remain.")

fail(errors)
print("Stage 6 runtime/metrics boundary guard passed.")
