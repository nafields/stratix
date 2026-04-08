// WebRTCClientImplTVOSAudioBootstrap.swift
// Defines web rtc client impl tvos audio bootstrap for the Integration / WebRTC surface.
//

#if os(tvOS)
import AVFoundation
import Foundation
import StratixCore
import StreamingCore

extension WebRTCClientImpl {
    static func makeTVOSPlaybackAudioConfiguration(sampleRate: Double) -> RTCAudioSessionConfiguration {
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playback.rawValue
        config.categoryOptions = []
        config.mode = AVAudioSession.Mode.moviePlayback.rawValue

        // IMPORTANT:
        // Keep WebRTC config aligned with hardware rate to avoid pitch drift / "slow audio"
        // if tvOS negotiates a non-48k clock (AirPods / route changes can do this).
        config.sampleRate = sampleRate

        // Request 20ms I/O buffer — matches WebRTC's native 20ms packet cadence (960 frames
        // @ 48kHz). Larger values (e.g. 1020ms) cause NetEQ to batch many packets per callback;
        // any late packet in the batch forces NetEQ to increase its delay target, causing
        // unbounded jitter buffer growth at ~500ms/sec on Apple TV HDMI outputs.
        config.ioBufferDuration = 0.020

        config.inputNumberOfChannels = 0
        // Stereo output requires WebRTC C++ patches (patch 0007 GetFormat + patch 0008 audio_device_ios.mm).
        // Without those patches, outputNumberOfChannels=2 causes FineAudioBuffer to fetch only 10ms of
        // "stereo" audio per 20ms mono callback → plays at half speed → one octave lower.
        // Read the user preference; default=false (mono) is the safe fallback.
        let stereoEnabled = SettingsStore.snapshotStream().stereoAudio
        config.outputNumberOfChannels = stereoEnabled ? 2 : 1
        return config
    }

    static func configureWebRTCDefaultAudioConfigurationForTVOSIfNeeded() {
        // Start with WebRTC's preferred 48kHz; runtime reconciliation will align to hardware.
        let config = makeTVOSPlaybackAudioConfiguration(sampleRate: 48_000)
        RTCAudioSessionConfiguration.setWebRTC(config)

        print("[WebRTC] set WebRTC default audio config for tvOS (category=\(config.category), mode=\(config.mode), options=\(config.categoryOptions.rawValue), inputChannels=\(config.inputNumberOfChannels), outputChannels=\(config.outputNumberOfChannels), sampleRate=\(Int(config.sampleRate)), ioBufferMs=\(Int(config.ioBufferDuration * 1000.0)))")
    }

    static func configureAudioSessionForTVOSPlaybackIfNeeded() {
        // tvOS: set category + mode only.
        // DO NOT setPreferredSampleRate(24000) or tiny buffer durations — those commonly trigger
        // resampler/clock mismatch symptoms (slow audio + accumulating A/V delay).
        // Also do NOT call setActive(true) here; WebRTC will activate when its audio unit starts.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            print("[WebRTC] configured AVAudioSession for tvOS playback (mode=moviePlayback, NOT activated yet)")
        } catch {
            print("[WebRTC] failed to configure AVAudioSession category for tvOS playback: \(error.localizedDescription)")
        }

        // Pick ONE model and stick to it. We use automatic management here.
        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.useManualAudio = true
        rtcAudioSession.isAudioEnabled = false
        rtcAudioSession.ignoresPreferredAttributeConfigurationErrors = true
        print("[WebRTC] RTCAudioSession pre-configured (manualAudio=\(rtcAudioSession.useManualAudio), isAudioEnabled=\(rtcAudioSession.isAudioEnabled))")
    }
}
#endif
