# Audio Architecture

This document describes how Stratix configures audio for streaming on Apple TV — including the app-level `AVAudioSession` setup, the WebRTC patches, the `FineAudioBuffer` call chain, the `AudioStats` diagnostic system, and the stereo toggle.

## Before You Touch Audio Code

Apple TV has no microphone. WebRTC was designed for two-way audio on devices that have microphones. This fundamental mismatch is the source of almost every audio issue in this project, and it shapes every design decision described below.

Before making any changes to audio code, you need to understand:

1. **Why the default WebRTC audio stack fails on tvOS** — the short answer is that `PlayAndRecord`, `VoiceProcessingIO`, and `inputAvailable` all silently fail or misbehave because there is no microphone.
2. **Which patches fix which problems** — the four patches below address four distinct failure modes. Removing or modifying one without understanding the others will break audio in a way that can be very hard to diagnose.
3. **The stereo situation** — "stereo audio" is a setting in the app, but true independent stereo requires a WebRTC patch (0011) that is not in the vendored binary by default. Without patch 0011, stereo mode causes the octave-low bug described in section 6.

**Quick reference — the four patches and what they fix:**

| Patch | Fixes |
|---|---|
| 0001 | Audio session category: changes from `PlayAndRecord` (fails on tvOS) to `Playback` |
| 0007 | AudioUnit subtype: changes from `VoiceProcessingIO` (no mic required) to `RemoteIO`; fixes RT-thread safety |
| 0008 | Skips the `inputAvailable` check that always returns `false` on Apple TV, causing the audio unit to never start |
| 0011 | Stereo channel support; **without this patch, enabling stereo causes the octave-low bug** |

If you are troubleshooting audio silence on a physical Apple TV, start with patch 0008 — it is the most common root cause. If you are troubleshooting the octave-low bug, see section 6. For the `outputVolume = 0.0` confusion on HDMI, see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — that is expected behavior, not a bug.

---

## Table of Contents

1. [The Problem: No Microphone on Apple TV](#1-the-problem-no-microphone-on-apple-tv)
2. [Patch 0001: Audio Session Category](#2-patch-0001-audio-session-category)
3. [Patch 0007: RemoteIO AudioUnit + RT-Thread Safety](#3-patch-0007-remoteio-audiounit--rt-thread-safety)
4. [Patch 0008: Skip inputAvailable Check](#4-patch-0008-skip-inputavailable-check)
5. [Patch 0011: Stereo Audio Channel Support](#5-patch-0011-stereo-audio-channel-support)
6. [Root Cause Deep-Dive: The Octave-Low Bug](#6-root-cause-deep-dive-the-octave-low-bug)
7. [App-Level Audio Configuration](#7-app-level-audio-configuration)
8. [The Stereo Toggle: What's Wired and What Isn't](#8-the-stereo-toggle-whats-wired-and-what-isnt)
9. [Audio Start Gate and Reconcile Path](#9-audio-start-gate-and-reconcile-path)
10. [Audio Resync Watchdog](#10-audio-resync-watchdog)
11. [Live Audio Controls and Debug Logging](#11-live-audio-controls-and-debug-logging)
12. [AudioStats Diagnostic System](#12-audiostats-diagnostic-system)
13. [Real-Time Thread Rules](#13-real-time-thread-rules)
14. [Audio Flow Diagram](#14-audio-flow-diagram)
15. [Common Pitfalls](#15-common-pitfalls)
16. [What's Still To Do](#16-whats-still-to-do)

---

## 1. The Problem: No Microphone on Apple TV

WebRTC's default audio stack assumes a device with both a microphone and a speaker. Every default code path on iOS — `PlayAndRecord`, `VoiceProcessingIO`, `inputAvailable` checks — assumes bidirectional audio. Apple TV has no microphone, which causes every default to fail silently or crash.

Stratix works around these failures through 4 coordinated C++ patches and one app-level configuration function.

| Patch | File | What it fixes |
|-------|------|---------------|
| 0001 | `RTCAudioSessionConfiguration.m` | Audio session category: `PlayAndRecord` → `Playback` |
| 0007 | `voice_processing_audio_unit.mm` | AudioUnit subtype: `VoiceProcessingIO` → `RemoteIO`; RT-thread NSLog safety; PCM throughput counter |
| 0008 | `RTCAudioSession.mm` | Skip `inputAvailable` check (root cause of complete audio silence on physical Apple TV) |
| 0011 | `voice_processing_audio_unit.h/.mm`, `audio_device_ios.mm` | Stereo channel support; fixes octave-low bug |

---

## 2. Patch 0001: Audio Session Category

**File:** `sdk/objc/components/audio/RTCAudioSessionConfiguration.m`

The WebRTC default sets `AVAudioSessionCategoryPlayAndRecord` with `MixWithOthers`.

On tvOS, `PlayAndRecord` requires microphone input permission — which doesn't exist. The `MixWithOthers` option causes tvOS to assign the audio session ambient priority, which sets the hardware volume to 0.0.

**Fix:** Switch to `Playback` + `moviePlayback` mode with no options:

```objc
#if TARGET_OS_TV
_category = AVAudioSessionCategoryPlayback;
_categoryOptions = 0;  // NO MixWithOthers — ambient priority = volume 0
_mode = AVAudioSessionModeMoviePlayback;
#endif
```

`moviePlayback` mode enables Dolby Digital pass-through on supported HDMI hardware.

---

## 3. Patch 0007: RemoteIO AudioUnit + RT-Thread Safety

**File:** `sdk/objc/native/src/audio/voice_processing_audio_unit.mm`

This patch does three things:

### 3a. Switch to RemoteIO

The WebRTC default uses `kAudioUnitSubType_VoiceProcessingIO`. On tvOS, this AudioUnit subtype requires microphone capability and fails to initialize.

**Fix:** Switch to `kAudioUnitSubType_RemoteIO` on tvOS and disable the input bus:

```objc
#if TARGET_OS_TV
  vpio_unit_description.componentSubType = kAudioUnitSubType_RemoteIO;
  UInt32 enable_input = 0;  // tvOS has no microphone
#else
  vpio_unit_description.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
  UInt32 enable_input = 1;
#endif
```

All input-path-only setup steps (disable AU buffer allocation, muted speech listener, bypass voice processing) are wrapped with `#if !TARGET_OS_TV`.

### 3b. Move NSLog Off the Real-Time Thread

**Why this matters:** The CoreAudio I/O callback fires every 20ms with a hard deadline. `NSLog` acquires a lock on Apple's unified logging subsystem and can block for 100ms+ under system load. A single blocked NSLog on the RT thread causes the audio unit to miss its deadline → CoreAudio inserts silence → the next callback sees an accumulated buffer → audio glitches.

**Before (broken):**
```objc
// In the 20ms RT callback — WRONG:
NSLog(@"[WebRTC][tvOS] playout PCM callback=%llu ...", cb, nf, avg);
```

**After (fixed):**
```objc
// Capture scalars by value, log asynchronously on a background thread:
uint64_t cb = s_tvos_playout_callback_count;
dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSLog(@"[WebRTC][tvOS] playout PCM callback=%llu ...", cb, ...);
});
```

`dispatch_async` is a lock-free queue enqueue (~50 ns) — safe on the RT thread.

### 3c. PCM Throughput Counter and Gap Detection

The callback maintains two diagnostics:

- **PCM throughput counter:** `s_tvos_pcm_total_frames += num_frames` — accumulates every callback. Logged every ~2.4 s as `throughput=NNN/s (N.N%)`. `100%` = running at real-time. This is the ground-truth hardware health signal.
- **Gap detector:** If two callbacks are >40ms apart (indicating a missed deadline), logs `PCM callback STALL gap=XXms`. Only fires during degraded conditions; NSLog cost is acceptable there.

Sample analysis (min/max/avgAbs) runs only on the ~2.4 s log-interval callbacks, not every 20ms. `avgAbs > 0` confirms audio data is non-silent.

---

## 4. Patch 0008: Skip inputAvailable Check

**File:** `sdk/objc/components/audio/RTCAudioSession.mm`

**This was the root cause of complete audio silence on physical Apple TV.**

`configureWebRTCSession:error:` contained a check:

```objc
if (!self.inputAvailable) {
    RTCLogError(@"No audio input path is available!");
    [self unconfigureWebRTCSession:nil];
    return NO;
}
```

On tvOS, `inputAvailable` is **always** `NO` — Apple TV has no microphone. This caused:

1. `configureWebRTCSession` returns `NO`
2. `ConfigureAudioSessionLocked()` propagates `false`
3. `InitPlayOrRecord()` returns `false` — audio unit never starts
4. Playout callback never fires → complete silence

**Fix:** Guard the check with `#if !TARGET_OS_TV` so it is skipped entirely on Apple TV.

**Why this was insidious:** There were no obvious failure signals:
- The session appeared healthy: `RTCPeerConnection` state = `connected`
- Video decoded and rendered normally
- The audio track was delivered via `didReceiveAudioTrack` delegate
- No error was surfaced to Swift code — `configureWebRTCSession` failure was swallowed

This patch only matters on physical Apple TV hardware. The simulator runs on macOS, which has both input and output audio — `inputAvailable` returns `YES` on the simulator even for tvOS builds. Audio will work in the simulator without patch 0008, masking the device-only failure.

---

## 5. Patch 0011: Stereo Audio Channel Support

**Files:**
- `sdk/objc/native/src/audio/voice_processing_audio_unit.h`
- `sdk/objc/native/src/audio/voice_processing_audio_unit.mm`
- `sdk/objc/native/src/audio/audio_device_ios.mm`

Before this patch, `GetFormat()` always returned a mono format regardless of `outputNumberOfChannels`. This meant setting `outputNumberOfChannels=2` would configure FineAudioBuffer for stereo but the AudioUnit would still receive a mono buffer → the octave-low bug (see §6 for details).

### Changes in voice_processing_audio_unit.h/.mm

`GetFormat` and `Initialize` now accept `num_channels`:

```cpp
// Before:
bool Initialize(Float64 sample_rate);
AudioStreamBasicDescription GetFormat(Float64 sample_rate) const;

// After:
bool Initialize(Float64 sample_rate, UInt32 num_channels = 1);
AudioStreamBasicDescription GetFormat(Float64 sample_rate, UInt32 num_channels) const;
```

`GetFormat` now scales the format accordingly:
```cpp
format.mBytesPerPacket   = num_channels * kBytesPerSample;
format.mBytesPerFrame    = num_channels * kBytesPerSample;
format.mChannelsPerFrame = num_channels;  // was always kRTCAudioSessionPreferredNumberOfChannels (= 1)
```

### Changes in audio_device_ios.mm

Three changes in `OnGetPlayoutData`:

**1. Broaden the DCHECK** — was `RTC_DCHECK_EQ(1, audio_buffer->mNumberChannels)` (crashed with 2-channel config). Now accepts 1 or 2 channels:
```cpp
RTC_DCHECK_GE(audio_buffer->mNumberChannels, 1u);
RTC_DCHECK_LE(audio_buffer->mNumberChannels, 2u);
```

**2. Fix silence-path size check:**
```cpp
// Before (wrong for stereo):
RTC_CHECK_EQ(size_in_bytes / kBytesPerSample, num_frames);
// After:
RTC_CHECK_EQ(size_in_bytes, num_frames * audio_buffer->mNumberChannels * kBytesPerSample);
```

**3. Scale FineAudioBuffer ArrayView by channel count:**
```cpp
// Before:
fine_audio_buffer_->GetPlayoutData(ArrayView<int16_t>(buf, num_frames), ...);
// After:
fine_audio_buffer_->GetPlayoutData(ArrayView<int16_t>(buf, num_frames * audio_buffer->mNumberChannels), ...);
```

All three `Initialize()` call sites in `audio_device_ios.mm` now forward the channel count:
```cpp
audio_unit_->Initialize(playout_parameters_.sample_rate(), playout_parameters_.channels());
```

The `RTC_DCHECK_EQ(playout_parameters_.channels(), 1)` in `UpdateAudioDeviceBuffer` was broadened to accept 1 or 2 channels (recording is still mono-only on iOS/tvOS).

---

## 6. Root Cause Deep-Dive: The Octave-Low Bug

**Symptom:** Audio plays one octave lower than expected. Present on both device and simulator.

**Root cause:** `outputNumberOfChannels = 2` in `makeTVOSPlaybackAudioConfiguration` while the WebRTC AudioUnit format was hardcoded to mono (before patch 0011).

### Full Call Chain

```
1. Swift: makeTVOSPlaybackAudioConfiguration(48000)
   └─ config.outputNumberOfChannels = 2   ← BUG (pre-fix: was hardcoded 2)

2. C++: audio_device_ios.mm
   playout_parameters_.reset(config.sampleRate, config.outputNumberOfChannels)
   └─ playout_parameters_.channels() = 2

3. UpdateAudioDeviceBuffer()
   └─ audio_device_buffer_->SetPlayoutChannels(2)

4. FineAudioBuffer constructor
   playout_channels_ = 2
   playout_samples_per_channel_10ms_ = 480        // 48000 × 10ms
   num_elements_10ms = 2 × 480 = 960

5. GetFormat() [pre-patch 0011]
   mChannelsPerFrame = kRTCAudioSessionPreferredNumberOfChannels = 1  ← ALWAYS MONO
   AudioUnit buffer: 960 frames × 1 channel

6. CoreAudio render callback (every 20ms, num_frames = 960):
   OnGetPlayoutData():
     audio_buffer->mNumberChannels = 1   ← AudioUnit still mono
     GetPlayoutData(ArrayView<int16_t>(buf, num_frames=960), ...)

7. FineAudioBuffer::GetPlayoutData(audio_buffer.size()=960):
   Loop: while (playout_buffer_.size() < 960)
     Iteration 1: 0 < 960 → RequestPlayoutData(480)
                  └─ appends num_elements_10ms = 2×480 = 960 elements (stereo interleaved)
                  └─ playout_buffer_.size() now = 960 → EXITS LOOP (only ONE call!)
   memcpy(buf, playout_buffer_.data(), 960 × sizeof(int16_t))

8. CoreAudio plays 960 mono samples at 48kHz = 20ms
   But those 960 samples encode only 10ms of audio content
   → Audio plays at HALF SPEED → ONE OCTAVE LOWER
```

### Why This Also Explains playoutRate ≈ 50%

With `channels=2`, FineAudioBuffer makes only **one** `RequestPlayoutData(480)` call per 20ms → one `GetAudio()` call → one NetEQ packet extraction. xCloud sends 10ms Opus frames (480 samples each):

```
Per 20ms: emittedCount += 480 (one extraction × 10ms)
Per second: 50 × 480 = 24,000
playoutRate = 24,000 / 48,000 = 50%
```

After the fix (`channels=1`), FineAudioBuffer makes **two** calls per 20ms:
```
Per 20ms: emittedCount += 480 + 480 = 960
Per second: 50 × 960 = 48,000
playoutRate = 48,000 / 48,000 = 100%
```

### The Fix

**Swift (no WebRTC rebuild needed for mono):**
```swift
// WebRTCClientImplTVOSAudioBootstrap.swift — makeTVOSPlaybackAudioConfiguration
let stereoEnabled = SettingsStore.snapshotStream().stereoAudio
config.outputNumberOfChannels = stereoEnabled ? 2 : 1
```

The underlying persisted preference still lives under the `guide.stereo_audio` key in `SettingsStore`, but the live bootstrap path now reads it through the snapshot API so the bridge can consume a stable, sendable value outside the main-actor UI layer.

**WebRTC C++ (patch 0011, rebuild needed for stereo to work correctly):**
Patch 0011 makes `GetFormat()` use `num_channels` instead of the hardcoded `1`, so when `outputNumberOfChannels=2` is set, the AudioUnit buffer actually has 2 channels, matching what FineAudioBuffer expects.

---

## 7. App-Level Audio Configuration

### makeTVOSPlaybackAudioConfiguration

`WebRTCClientImplTVOSAudioBootstrap.swift` calls this to build the `RTCAudioSessionConfiguration` for tvOS:

```swift
static func makeTVOSPlaybackAudioConfiguration(sampleRate: Double) -> RTCAudioSessionConfiguration {
    let config = RTCAudioSessionConfiguration.webRTC()
    config.category = AVAudioSession.Category.playback.rawValue
    config.categoryOptions = []
    config.mode = AVAudioSession.Mode.moviePlayback.rawValue

    // Keep WebRTC aligned to the active hardware rate to avoid pitch/sync drift.
    config.sampleRate = sampleRate

    // 20 ms matches WebRTC's expected callback cadence on tvOS.
    config.ioBufferDuration = 0.02
    config.inputNumberOfChannels = 0
    let stereoEnabled = SettingsStore.snapshotStream().stereoAudio
    config.outputNumberOfChannels = stereoEnabled ? 2 : 1
    return config
}
```

Called from both:
- `configureWebRTCDefaultAudioConfigurationForTVOSIfNeeded()` — initial setup at app launch
- `reconcileTVOSAudioSession()` — on `AVAudioSession` route changes (HDMI connect/disconnect)

### configureAudioSessionForTVOSPlaybackIfNeeded

The app bridge also pre-configures `RTCAudioSession` for manual tvOS playback control:

```swift
let rtcAudioSession = RTCAudioSession.sharedInstance()
rtcAudioSession.useManualAudio = true
rtcAudioSession.isAudioEnabled = false
rtcAudioSession.ignoresPreferredAttributeConfigurationErrors = true
```

This is important to the current repo behavior:

- WebRTC defaults are installed once
- tvOS playback category/mode are prepared up front
- actual audio enablement is deferred until the stream has both a connected peer and a remote audio track

### audioSessionDidStartPlayOrRecord

`WebRTCClientImpl` implements the `RTCAudioSessionDelegate` callback:

```swift
func audioSessionDidStartPlayOrRecord(_ audioSession: RTCAudioSession) {
    logAudio("didStartPlayOrRecord ...")
    scheduleTVOSAudioReconcile(reason: "didStartPlayOrRecord")
}
```

**Why this changed:** the current repo no longer blindly enables audio from this delegate callback. Instead it schedules a reconcile pass that respects the tvOS audio gate and the live hardware route.

---

## 8. The Stereo Toggle: What's Wired and What Isn't

### Wired

| Component | What it does |
|-----------|-------------|
| `guide.stereo_audio` UserDefaults key | UI toggle persisted to UserDefaults |
| `SettingsStore.snapshotStream().stereoAudio` | Current bootstrap path used by `makeTVOSPlaybackAudioConfiguration` to read the stereo preference |
| `makeTVOSPlaybackAudioConfiguration` | Sets `outputNumberOfChannels = stereoEnabled ? 2 : 1` |
| `reconcileTVOSAudioSession` | Re-reads the setting on audio route changes via `makeTVOSPlaybackAudioConfiguration` |
| `VoiceProcessingAudioUnit::GetFormat(sample_rate, num_channels)` | AudioUnit format now reflects channel count (patch 0011) |
| `VoiceProcessingAudioUnit::Initialize(sample_rate, num_channels)` | Passes channels to `GetFormat` (patch 0011) |
| `OnGetPlayoutData` ArrayView size | Scaled by `audio_buffer->mNumberChannels` (patch 0011) |
| All 3 `audio_unit_->Initialize()` call sites | Forward `playout_parameters_.channels()` (patch 0011) |
| `stereoAudio` default | `false` (mono is safe; stereo requires patch 0011 in the xcframework) |

### Not Wired / Limitations

| Gap | Reason / Impact |
|-----|----------------|
| **Mid-stream channel change** | `FineAudioBuffer` is initialized once at stream start with `playout_channels_`. Toggling stereo during an active stream has no effect until the next stream start. |
| **True stereo content from xCloud** | xCloud sends stereo Opus. The Opus decoder in WebRTC's NetEQ downmixes to mono before `NeedMorePlayData` is called. With `outputChannels=2`, both L and R channels are filled with the same mono content (duplicated — not true independent L/R stereo). True stereo would require patching the Opus decoder chain. |
| **No mid-stream channel count log** | There is no warning if `guide.stereo_audio` is toggled while streaming. The active stream silently keeps its initial channel config. |
| **No stats HUD channel indicator** | The streaming stats HUD does not show the current channel count. `outputChannels` is logged at stream init but not surfaced in the real-time stats display. |

### Enabling Stereo

1. Enable the "Stereo Audio" toggle in the guide overlay
2. Stop and restart the stream (the toggle only takes effect at next stream start)
3. The WebRTC xcframework must be built with patch 0011 — without it, stereo will cause the octave-low bug (see §6)

---

## 9. Audio Start Gate and Reconcile Path

The biggest runtime change since the earlier audio docs is that Stratix now has an explicit **audio start gate** on tvOS.

### Why the gate exists

There are two distinct conditions that need to be true before the app should trust the output path:

1. the peer connection has actually reached `.connected`
2. a real remote audio track has been discovered and retained

The current gate tracks those separately:

- `audioGateHasRemoteTrack`
- `audioGatePeerConnected`
- `audioGateOpened`

The gate is reset when the bridge is preparing a new connection or closing an old one:

- `resetTVOSAudioStartGate(reason: "applyH264CodecPreferences")`
- `resetTVOSAudioStartGate(reason: "close")`

### How the gate opens

The open sequence is intentionally conservative:

1. `handlePeerConnectionConnected` marks the peer as connected
2. `publishRemoteTrackIfNeeded` marks the remote audio track as discovered
3. `maybeOpenTVOSAudioStartGate` checks whether both conditions are now true
4. if so, it:
   - records `audioGateOpenedAtTimestamp`
   - resets strike and trigger counters
   - clears drain-in-progress state
   - enables `RTCAudioSession.isAudioEnabled`
   - re-enables the retained `remoteAudioTrack`
   - schedules a reconcile pass

This is why the current repo can reason about startup grace periods and drift from a meaningful “audio really started now” timestamp instead of guessing from a generic lifecycle event.

### reconcileTVOSAudioSession

Once the gate is open, the app bridge reconciles the active audio session against the real hardware route:

```swift
let hardwareRate = avSession.sampleRate > 0 ? avSession.sampleRate : 48_000
let config = Self.makeTVOSPlaybackAudioConfiguration(sampleRate: hardwareRate)
```

Important current behavior:

- the app aligns WebRTC to the current hardware sample rate
- it keeps the session active during stream startup and route stabilization
- it intentionally does **not** force a reconfigure on every `ioBufferDuration` mismatch, because tvOS hardware often chooses a slightly different effective buffer size than the requested 20 ms
- route changes call back into this same reconcile path

The practical result is that Stratix now has a route-aware, hardware-aware playback configuration loop instead of a one-shot startup configuration.

---

## 10. Audio Resync Watchdog

The current repo also has a tvOS-specific **audio resync watchdog** built around `TVOSAudioResyncPolicy` in `StratixCore`.

### Inputs the policy uses

The watchdog does not fire on one noisy metric. It evaluates a bundle of live inputs:

- `watchdogEnabled`
- `drainInProgress`
- `jitterBufferDelayMs`
- `jitterBufferWindowDelayMs`
- `jitterBufferWindowTargetMs`
- `jitterMs`
- `packetsLost`
- `jitterBufferEmittedCount`
- `audioVideoPlayoutDeltaMs`
- `gateOpenedAtTimestamp`

### Policy gates

The current policy suppresses action when:

- the watchdog is disabled
- a prior drain is still in progress
- too few frames have been emitted to trust the signal yet
- the stream is still within the startup grace period
- target delay is healthy
- the bad condition has not repeated enough times
- the cooldown window is still active

The default thresholds in the current implementation are deliberately conservative:

- at least `24_000` emitted samples before trusting the measurement
- a `6` second startup grace period after the gate opens
- repeated high-delay / high-drift conditions before triggering
- cooldown windows that depend on whether the policy escalates to a harder recovery mode

### Recovery behavior

When the policy does trigger, the execution layer can request a drain/re-enable cycle:

- disable the remote track
- wait for the chosen drain duration
- re-enable the track
- schedule audio reconcile again

The code also records and logs suppression reasons. That is valuable when debugging because it tells you **why** the watchdog did not fire, not just whether it fired.

---

## 11. Live Audio Controls and Debug Logging

The current repo has more live runtime audio control than the original audio doc described.

### Audio boost

`updateAudioBoost(dB:)` applies live gain to the retained remote audio track:

```swift
let gainLinear = min(pow(10.0, dB / 20.0), 10.0)
audioTrack.source.volume = gainLinear
```

This means the guide’s audio-boost control is not just a persisted preference for the next stream. It actively updates the current stream.

### Audio-specific debug key

The bridge uses a dedicated audio debug key:

- `debug.webrtc_audio_logs`

That is deliberate. Audio diagnostics can be noisy, and the repo keeps them separate from generic networking or shell logs.

### Watchdog setting

The watchdog is also wired to a current diagnostics setting:

- `debug.audio_resync_watchdog_enabled`

That setting is surfaced through the shared settings model and the diagnostics settings pane, so the behavior is not hidden inside the bridge.

---

## 12. AudioStats Diagnostic System

`WebRTCClientImpl` emits periodic audio diagnostics while streaming. In the current repo these appear under the explicit audio logging path, for example:

```
[WebRTC][AudioStats:v3] jitterMs=... jbAvgMs=... jbWinMs=... jbTargetWinMs=... playoutRate=...
```

### Fields

| Field | Source | Healthy value |
|-------|--------|---------------|
| `playoutRate` | `emittedCount / (48000 × elapsed)` | `~100%` |
| `jbWinMs` | NetEQ jitter buffer window (actual) | `20–80ms` (oscillates — see below) |
| `jbTargetWinMs` | NetEQ target window | `≤200ms` |
| `resyncCount` | How many AudioResync triggers fired | `0` (rare) |
| `throughput` | PCM frames played / elapsed seconds | `48000/s (100%)` |

### Interpreting playoutRate

- **~100%:** Healthy. Two `RequestPlayoutData(480)` calls per 20ms callback. xCloud sends 10ms Opus frames → two extractions × 480 = 960 emitted/20ms → `48000/48000 = 100%`.
- **~50%:** Channels = 2 bug. FineAudioBuffer makes only one `RequestPlayoutData` call per 20ms, emitting 480 samples/20ms → `24000/48000 = 50%`. Audio plays one octave lower.
- **<100% (not 50%):** NetEQ buffer underrun or decoder stall. Check network quality.

### Interpreting jbWinMs Sawtooth

The jitter buffer window oscillates in a sawtooth pattern between ~20ms and ~80ms. This is **expected behavior** for xCloud's bursty delivery, not a bug:

```
xCloud sends audio in bursts (multiple 10ms Opus frames at once)
→ Burst arrives → jitter buffer fills → jbWinMs rises
→ NetEQ drains at 10ms/getAudio → jbWinMs falls
→ Next burst arrives → cycle repeats
```

A watchdog prevents unnecessary audio resync from firing on this sawtooth:
```swift
// Only trigger AudioResync if target delay is genuinely stuck high:
guard jbTargetWinMs > 200 else { return }
```

### PCM Throughput vs. playoutRate

These are independent measurements:
- **throughput** measures actual CoreAudio I/O thread activity (hardware running)
- **playoutRate** measures NetEQ extraction rate (content being pulled from jitter buffer)

`throughput=100%` with `playoutRate=50%` is the signature of the channels=2 bug: hardware running at full speed, but only half the jitter buffer content consumed per unit time.

---

## 13. Real-Time Thread Rules

The CoreAudio I/O thread (`OnGetPlayoutData`) has a **20ms hard deadline**. Any operation that can block must not run on this thread.

### Banned on the RT Thread

| Operation | Why banned | Alternative |
|-----------|-----------|-------------|
| `NSLog` | Acquires logging subsystem lock; can block 100ms+ | `dispatch_async(QOS_CLASS_UTILITY, …)` |
| `os_log` | Same internal lock as NSLog | Same workaround |
| `malloc` / `free` | Heap lock; priority inversion risk | Pre-allocate in constructor |
| `std::mutex::lock` (contended) | Priority inversion | `std::atomic` for shared state |
| File I/O | Kernel syscall; unbounded latency | Async I/O on background thread |
| Objective-C message dispatch to UI | Main thread; blocks | Never from RT thread |

### Allowed on the RT Thread

- `std::atomic` load/store
- `clock_gettime_nsec_np` (lock-free monotonic clock)
- Simple integer arithmetic
- `memset` / `memcpy` on pre-allocated buffers
- `dispatch_async` (lock-free queue enqueue)

### The dispatch_async Pattern (from Patch 0007)

```objc
// 1. Capture all needed values as value-type locals (NOT pointers to shared state):
uint64_t cb = s_tvos_playout_callback_count;  // scalar
UInt32   nf = num_frames;                      // scalar
unsigned int avg = ...;                        // scalar

// 2. Dispatch to background (lock-free):
dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSLog(@"...", cb, nf, avg);  // Safe — runs on background thread
});
```

**Critical:** Only capture scalars. Never capture pointers to audio buffers — they may be recycled by CoreAudio before the block runs.

---

## 14. Audio Flow Diagram

```
xCloud Server
│
│  Opus (stereo, 10ms frames) via RTP over WebRTC DTLS-SRTP
│
▼
WebRTC NetEQ Jitter Buffer
│  Accumulates packets, smooths jitter
│  GetAudio() → Opus decode → mono PCM (16-bit, 48kHz, 480 samples/call)
│  Note: Opus is stereo but NetEQ outputs mono PCM currently
│
▼
FineAudioBuffer (C++)
│  playout_channels_ = 1 (mono, default) or 2 (stereo, requires patch 0011)
│  num_elements_10ms = channels × 480
│  GetPlayoutData(ArrayView<int16_t>(buf, num_frames × channels)):
│    while (playout_buffer_ too small): RequestPlayoutData(480)
│    → memcpy to CoreAudio buffer
│
▼
CoreAudio VoiceProcessingAudioUnit
│  (patched: RemoteIO on tvOS — patch 0007)
│  OnGetPlayoutData callback (every 20ms, 960 frames)
│  mChannelsPerFrame = 1 (mono) or 2 (stereo, requires patch 0011)
│
▼
AVAudioSession (patched configuration — patch 0001)
│  Category: Playback      (was: PlayAndRecord)
│  Mode: moviePlayback     (Dolby Digital pass-through on HDMI)
│  Options: none           (was: MixWithOthers → silent at ambient priority)
│  inputNumberOfChannels: 0
│  outputNumberOfChannels: 1 (mono, default) or 2 (stereo)
│
▼
HDMI output → TV / AV receiver
│
└── outputVolume = 0.0 is NORMAL on tvOS
    Volume is controlled by the TV / AV receiver via HDMI CEC,
    not by software. Never use outputVolume as a silence indicator.
```

---

## 15. Common Pitfalls

### "outputVolume = 0.0" is not silence

`AVAudioSession.outputVolume` returns 0.0 on tvOS HDMI output. This is normal — volume is controlled by the TV or AV receiver via HDMI CEC, not by software. Do not use `outputVolume` as a silence indicator on Apple TV.

### "The PCM callback never fires"

If `[WebRTC][tvOS] playout PCM callback=` does not appear in the console, the audio unit was never started. Most likely cause: patch 0008 was not applied, or `configureWebRTCSession` returned `NO` for another reason.

### "Audio works in simulator but not on device"

The simulator runs on macOS, which has both input and output audio. `inputAvailable` returns `YES` on the simulator even for tvOS builds. Patch 0008 only matters on real Apple TV hardware. This means the bug is completely hidden in simulator testing.

### "MixWithOthers causes silence"

If you add `AVAudioSessionCategoryOptionMixWithOthers` to the patched configuration, tvOS treats the app as an ambient audio client and may assign it volume 0.0. Remove `MixWithOthers` entirely.

### "Audio is one octave lower than expected"

Root cause is channel count mismatch. See §6 for the full call chain. Quick checks:

1. Look for `playoutRate ≈ 50%` in AudioStats — if so, `outputNumberOfChannels=2` is active but patch 0011 is not (or xcframework was not rebuilt after applying it)
2. Check `guide.stereo_audio` / `SettingsStore.snapshotStream().stereoAudio` — it must remain `false` unless patch 0011 is applied
3. In `WebRTCClientImplTVOSAudioBootstrap.swift`, verify the `outputNumberOfChannels` line reads the current stereo preference rather than hardcoding `2`

### "stereoAudio toggle is ON but audio is still mono-sounding"

Expected. xCloud's Opus stream is decoded to mono in NetEQ's decoder chain. Setting `outputChannels=2` fills both L and R channels with the same mono content (duplicated — not true stereo). True independent stereo would require changes to the Opus decoder path, which is not currently implemented.

### "NSLog / RTCLog spam in the console"

The PCM callback logs every ~2.4 s (every 120th callback). If you're seeing per-callback logging, an older version of patch 0007 (pre-RT-thread fix) may be applied. Rebuild with the current patch set.

---

## 16. What's Still To Do

### High Priority

| Task | Details |
|------|---------|
| **Verify stereo toggle on device** | Enable "Stereo Audio" in guide, restart stream. Confirm no octave-low regression and that the init/reconcile logs show `outputChannels=2`. Listen for the expected mono-duplicated stereo behavior. |
| **Stats HUD: show channel count** | Add `outputChannels: Int` to `AudioStats`. Display in the live stats overlay during streaming so the current channel config is immediately visible. |

### Medium Priority

| Task | Details |
|------|---------|
| **Mid-stream channel change** | Toggling "Stereo Audio" during an active stream currently has no effect. To implement: call `SetupAudioBuffersForActiveAudioSession()` after toggling, which re-creates `FineAudioBuffer` with the new channel count. Requires careful locking (must not be called from the RT thread). Safest approach: "apply on next stream start" with a pending-change indicator in the UI. |
| **True stereo from Opus** | xCloud sends stereo Opus frames. Currently the NetEQ/Opus decoder in WebRTC outputs mono. Patching the decoder to output 2-ch PCM would require changes to `webrtc/modules/audio_coding/neteq/` and the Opus wrapper. Significant effort; may not be audibly meaningful for game audio on TV speakers. |
| **Wired-network audio jitter** | On Ethernet (vs. WiFi), xCloud delivers packets with lower jitter. The jitter buffer target will naturally settle at ~20ms instead of ~40ms. No action needed, but worth documenting in AudioStats interpretation. |

### Low Priority / Cosmetic

| Task | Details |
|------|---------|
| **Expose gate/watchdog state in the HUD** | The gate and watchdog are well-instrumented in logs but not surfaced in the live HUD. Exposing open/closed state, trigger count, or suppression reason would make device triage faster. |
| **AudioResync unit test** | The watchdog gate (`jbTargetWinMs > 200ms`) is not unit-tested. Add a test that simulates high jitter buffer delay and confirms the resync trigger fires. |

---

## Ownership

| Area | Location |
|------|----------|
| WebRTC patching and rebuild instructions | `Tools/webrtc-build/` |
| App bridge and audio session configuration | `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImpl.swift` |
| Stream runtime contracts and track attachment | `Packages/StreamingCore` |
| Diagnostics and metrics | `Packages/DiagnosticsKit` |

---

## Validation

For audio-adjacent changes:

- **Simulator:** Validates everything except patch 0008 (inputAvailable is always YES on macOS). The octave-low bug, playoutRate metric, and PCM callback counter are all testable on simulator.
- **Physical Apple TV device:** Required to validate patch 0008 (audio silence). Console.app filter: `process:Stratix subsystem:com.stratix` → look for `[WebRTC][tvOS] playout PCM callback=` within the first few seconds of stream start.
- **Audio silence on device but not simulator:** Almost always patch 0008 missing or xcframework not rebuilt.
- **Octave-low on both sim and device:** Always a `guide.stereo_audio=true` + missing patch 0011 combination.

---

## Related Docs

- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md) — streaming runtime and session lifecycle
- [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md) — full patch listing and rebuild guide
- [WEBRTC_GUIDE.md](WEBRTC_GUIDE.md) — WebRTC integration boundary
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — audio issue quick-reference
- [TESTING.md](TESTING.md) — validation lanes
