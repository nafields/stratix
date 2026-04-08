// StreamPerformanceTracker.swift
// Defines stream performance tracker.
//

import Foundation
import OSLog
import os.signpost

public enum StreamPerformanceEvent: String, Sendable {
    case streamIntent = "stream_intent"
    case shellSuspended = "shell_suspended"
    case streamModalPresented = "stream_modal_presented"
    case tokenRefreshStart = "token_refresh_start"
    case tokenRefreshFinish = "token_refresh_finish"
    case lptFetchStart = "lpt_fetch_start"
    case lptFetchFinish = "lpt_fetch_finish"
    case sessionStartRequest = "session_start_request"
    case readyToConnect = "ready_to_connect"
    case peerConnected = "peer_connected"
    case firstVideoTrack = "first_video_track"
    case firstFrameRendered = "first_frame_rendered"
    case inputChannelOpen = "input_channel_open"
    case firstGamepadPacketSent = "first_gamepad_packet_sent"
    case overlayInteractive = "overlay_interactive"
    case shellResumeStart = "shell_resume_start"
    case shellResumeFinish = "shell_resume_finish"
    case artworkRequestStart = "artwork_request_start"
    case artworkCacheHit = "artwork_cache_hit"
    case artworkDecodeFinish = "artwork_decode_finish"
    case artworkFirstVisible = "artwork_first_visible"
}

public enum StreamPerformanceTracker {
    private static let logger = GLogger(category: .streaming)
    private static let signpostLog = OSLog(
        subsystem: "com.stratix.app",
        category: "StreamPerformance"
    )

    public static func mark(
        _ event: StreamPerformanceEvent,
        metadata: [String: String] = [:]
    ) {
        let details = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        let message = details.isEmpty
            ? "[stream-perf] \(event.rawValue)"
            : "[stream-perf] \(event.rawValue) \(details)"
        logger.info("\(message)")

        StreamMetricsPipeline.shared.recordPerformanceEvent(
            event,
            metadata: metadata
        )

        os_signpost(
            .event,
            log: signpostLog,
            name: event.signpostName,
            "%{public}s",
            details
        )
    }
}

private extension StreamPerformanceEvent {
    var signpostName: StaticString {
        switch self {
        case .streamIntent: "stream_intent"
        case .shellSuspended: "shell_suspended"
        case .streamModalPresented: "stream_modal_presented"
        case .tokenRefreshStart: "token_refresh_start"
        case .tokenRefreshFinish: "token_refresh_finish"
        case .lptFetchStart: "lpt_fetch_start"
        case .lptFetchFinish: "lpt_fetch_finish"
        case .sessionStartRequest: "session_start_request"
        case .readyToConnect: "ready_to_connect"
        case .peerConnected: "peer_connected"
        case .firstVideoTrack: "first_video_track"
        case .firstFrameRendered: "first_frame_rendered"
        case .inputChannelOpen: "input_channel_open"
        case .firstGamepadPacketSent: "first_gamepad_packet_sent"
        case .overlayInteractive: "overlay_interactive"
        case .shellResumeStart: "shell_resume_start"
        case .shellResumeFinish: "shell_resume_finish"
        case .artworkRequestStart: "artwork_request_start"
        case .artworkCacheHit: "artwork_cache_hit"
        case .artworkDecodeFinish: "artwork_decode_finish"
        case .artworkFirstVisible: "artwork_first_visible"
        }
    }
}
