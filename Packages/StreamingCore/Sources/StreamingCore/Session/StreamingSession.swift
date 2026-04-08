// StreamingSession.swift
// Defines the observable app-facing streaming session facade over the runtime boundary.
//

import Foundation
import StratixModels
import InputBridge
import Observation
import XCloudAPI
import os

let streamLogger = Logger(subsystem: "com.stratix.app", category: "Streaming")

@Observable
@MainActor
/// Publishes stream lifecycle and stats while delegating runtime work to the lower-level session model.
public final class StreamingSession: StreamingSessionFacade {
    public internal(set) var lifecycle: StreamLifecycleState = .idle {
        didSet {
            guard lifecycle != oldValue else { return }
            onLifecycleChange?(lifecycle)
        }
    }
    public internal(set) var stats: StreamingStatsSnapshot = StreamingStatsSnapshot()
    public internal(set) var disconnectIntent: StreamingDisconnectIntent = .reconnectable

    @ObservationIgnored let model: StreamingSessionModel

    @ObservationIgnored public var onVibration: ((VibrationReport) -> Void)?
    @ObservationIgnored public var onLifecycleChange: (@MainActor (StreamLifecycleState) -> Void)? {
        didSet {
            guard let onLifecycleChange else { return }
            onLifecycleChange(lifecycle)
        }
    }
    @ObservationIgnored public var onVideoTrack: ((AnyObject) -> Void)? {
        didSet { replayVideoTrackIfNeeded() }
    }
    @ObservationIgnored public var onAudioTrack: ((AnyObject) -> Void)? {
        didSet { replayAudioTrackIfNeeded() }
    }

    /// Creates a streaming session facade backed by an API client, bridge, and runtime model.
    public init(
        apiClient: XCloudAPIClient,
        bridge: any WebRTCBridge,
        config: StreamingConfig = StreamingConfig(),
        preferences: StreamPreferences = StreamPreferences()
    ) {
        let delegateBox = StreamingRuntimeDelegateBox()
        self.model = StreamingSessionModel(
            apiClient: apiClient,
            bridge: bridge,
            config: config,
            preferences: preferences,
            delegateBox: delegateBox
        )
        delegateBox.setDelegate(self)
    }

    /// Registers the app-owned vibration callback used for controller haptic routing.
    public func setVibrationHandler(_ handler: @escaping (VibrationReport) -> Void) {
        onVibration = handler
    }

    /// Exposes the input queue used by the runtime input channel.
    public var inputQueueRef: InputQueue { model.inputQueue }
}
