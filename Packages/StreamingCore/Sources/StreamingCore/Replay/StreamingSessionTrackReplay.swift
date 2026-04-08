// StreamingSessionTrackReplay.swift
// Defines streaming session track replay for the Replay surface.
//

import Foundation
import DiagnosticsKit

@MainActor
extension StreamingSession {
    func runtimeDidReceiveVideoTrack(_ track: AnyObject) {
        let isFirstVideoTrack = model.latestVideoTrack == nil
        model.latestVideoTrack = track
        if isFirstVideoTrack {
            StreamMetricsPipeline.shared.recordMilestone(.firstFrameReceived)
        }
        onVideoTrack?(track)
    }

    func runtimeDidReceiveAudioTrack(_ track: AnyObject) {
        model.latestAudioTrack = track
        onAudioTrack?(track)
    }

    func replayVideoTrackIfNeeded() {
        guard let onVideoTrack, let latestVideoTrack = model.latestVideoTrack else { return }
        model.videoTrackReplayCount += 1
        let replayCount = model.videoTrackReplayCount
        if replayCount <= 3 {
            streamLogger.info("Replaying cached WebRTC video track to new handler (replay #\(replayCount, privacy: .public))")
        } else if replayCount == 4 {
            streamLogger.warning(
                "Video track handler installed repeatedly — replay #\(replayCount, privacy: .public) reached; subsequent replay logs suppressed. Possible render loop."
            )
        }
        onVideoTrack(latestVideoTrack)
    }

    func replayAudioTrackIfNeeded() {
        guard let onAudioTrack, let latestAudioTrack = model.latestAudioTrack else { return }
        streamLogger.info("Replaying cached WebRTC audio track to new handler")
        onAudioTrack(latestAudioTrack)
    }
}
