# WebRTC Build Reference

This document is the current source-build reference for the vendored `WebRTC.xcframework` that ships with Stratix.

Use this together with [WEBRTC_GUIDE.md](WEBRTC_GUIDE.md) and [../Tools/webrtc-build/README.md](../Tools/webrtc-build/README.md).

---

## Current Committed Build

The committed metadata in [../ThirdParty/WebRTC/webrtc-version.json](../ThirdParty/WebRTC/webrtc-version.json) currently records:

| Field | Value |
|-------|-------|
| Source | `webrtc-googlesource` |
| Revision | `6f7ad28e168d903245c59c2b3d2462f437259cd8` |
| Branch | `main` |
| Built at | `2026-03-18T15:29:29Z` |
| Toolchain | `Xcode 26.3` |
| Patch count | `11` patches |
| Slices | `tvos-arm64` (device) · `tvos-arm64-simulator` (Apple Silicon simulator) |

This is the committed-binary truth, not a planning target. If `Tools/webrtc-build/patches/`, `ThirdParty/WebRTC/webrtc-version.json`, and this document disagree, the scripts and metadata win and this doc needs to be corrected in the same change set.

The other committed metadata checkpoint is the xcframework bundle itself. In practice, contributors should treat these as the binary truth set:

- `ThirdParty/WebRTC/webrtc-version.json`
- `ThirdParty/WebRTC/WebRTC.xcframework/Info.plist`
- `Tools/webrtc-build/patches/`

If one of those says something different from the others, the committed binary story is inconsistent and should be fixed before release work continues.

---

## How This Reference Fits With The Other WebRTC Docs

The repo intentionally splits WebRTC documentation into three layers:

- [WEBRTC_GUIDE.md](WEBRTC_GUIDE.md) explains the app/package integration boundary and where contributors should touch code
- [WEBRTC_CAPABILITIES.md](WEBRTC_CAPABILITIES.md) explains what the committed tvOS build actually supports
- **this file** explains how the binary is produced, why the patches exist, and what to verify when the binary changes

That separation matters because build failures, runtime failures, and capability misunderstandings are different classes of problem. The earlier doc set blurred those together too often.

---

## Why Build From Source?

The standard community packaging for tvOS WebRTC (via JitsiWebRTC CocoaPods) stopped publishing tvOS slices around M124+. When you try to add a pod-based WebRTC to a tvOS target, CocoaPods rejects it:

```
The platform of the target (tvOS 16.0) is not compatible with JitsiWebRTC (124.0.0),
which does not support tvOS.
```

This is a **packaging/distribution problem**, not a WebRTC capability problem. The WebRTC source fully supports peer connections, data channels, unified plan, and ICE on tvOS — it just needs:

1. The correct GN flags (especially `rtc_enable_objc_symbol_export=true` — see below)
2. tvOS-specific patches (audio session, microphone bypass, etc.)
3. A fresh build excluding x86_64 simulator (which has a NASM platform tagging bug)

Stratix builds WebRTC from source and gets full functionality.

---

## Prerequisites

- **macOS with Apple Silicon (M1+)** — required for arm64-native builds
- **Xcode 26** selected via `xcode-select`
- **Python 3** on `PATH` (needed for `depot_tools`)
- **~25 GB free disk space** (~10 GB source + ~10 GB build artifacts)
- **Internet access** for the initial `gclient sync`

The build scripts handle downloading `depot_tools` automatically.

---

## Quick Build (3 Commands)

```bash
cd /path/to/stratix

# 1. Sync WebRTC source (~10 GB, one-time, ~20–40 min)
Tools/webrtc-build/sync_webrtc.sh

# 2. Apply patches + build device + simulator frameworks (~10–20 min)
Tools/webrtc-build/build_webrtc_tvos.sh

# 3. Package into WebRTC.xcframework + refresh webrtc-version.json
Tools/webrtc-build/package_xcframework.sh
```

Output:
- `ThirdParty/WebRTC/WebRTC.xcframework` (replaces the committed binary)
- `ThirdParty/WebRTC/webrtc-version.json` (updated with new build metadata)
- `.cache/webrtc/out/tvos_arm64/`
- `.cache/webrtc/out/tvos_sim_arm64/`

---

## GN Configuration

Both slices share a common base set of GN args:

```gn
target_os                     = "ios"       # GN uses "ios" for ALL Apple mobile targets
target_platform               = "tvos"      # Selects appletvos / appletvsimulator SDK
ios_deployment_target         = "17.0"      # Override .gn default of 14.0
use_xcode_clang               = true
is_debug                      = false
rtc_enable_protobuf           = false
rtc_use_h264                  = true
use_goma                      = false
rtc_libvpx_build_vp9          = false       # Xbox uses H.264; VP9 not needed
ios_enable_code_signing       = false
use_rtti                      = true        # Required for ObjC++ bridge code
rtc_enable_objc_symbol_export = true        # CRITICAL — see trap section below
```

Per-slice additions:

```gn
# Device
target_cpu         = "arm64"
target_environment = "device"     # NOT "appletvos" — that's the SDK name

# Simulator (arm64 only)
target_cpu         = "arm64"
target_environment = "simulator"  # NOT "appletvsimulator"
```

Full `gn gen` commands:

```bash
GN=.cache/webrtc/src/src/buildtools/mac/gn
NINJA=.cache/webrtc/src/src/third_party/ninja/ninja

GN_ARGS='target_os="ios" target_platform="tvos" ios_deployment_target="17.0"
  use_xcode_clang=true is_debug=false rtc_enable_protobuf=false rtc_use_h264=true
  use_goma=false rtc_libvpx_build_vp9=false ios_enable_code_signing=false
  use_rtti=true rtc_enable_objc_symbol_export=true'

# Device
$GN gen out/tvos_arm64 --args="$GN_ARGS target_cpu=\"arm64\" target_environment=\"device\""
$NINJA -C out/tvos_arm64 framework_objc

# Simulator
$GN gen out/tvos_sim_arm64 --args="$GN_ARGS target_cpu=\"arm64\" target_environment=\"simulator\""
$NINJA -C out/tvos_sim_arm64 framework_objc
```

> Note: Use the real GN binary at `buildtools/mac/gn`, NOT the `depot_tools` wrapper.

---

## The `rtc_enable_objc_symbol_export` Trap

**This is the single most important GN flag and is not documented anywhere in official sources.**

Without it, the build **succeeds** but linking the app fails:

```
Undefined symbols for architecture arm64:
  "_OBJC_CLASS_$_RTCConfiguration", referenced from: WebRTCClientImpl.o
  "_OBJC_CLASS_$_RTCPeerConnectionFactory", referenced from: WebRTCClientImpl.o
  "_RTCInitializeSSL", referenced from: WebRTCClientImpl.o
  ... (every RTC* symbol)
```

**Root cause chain:**

1. `webrtc.gni` declares: `rtc_enable_objc_symbol_export = rtc_enable_symbol_export`
2. `rtc_enable_symbol_export` defaults to `false`
3. `BUILD.gn` only adds `WEBRTC_ENABLE_OBJC_SYMBOL_EXPORT` define when this flag is `true`
4. `RTCMacros.h` expands `RTC_OBJC_EXPORT` to empty without the define — every ObjC class gets **hidden symbol visibility**

```objc
// RTCMacros.h (simplified):
#ifdef WEBRTC_ENABLE_OBJC_SYMBOL_EXPORT
  #define RTC_OBJC_EXPORT __attribute__((visibility("default")))
#endif
#ifndef RTC_OBJC_EXPORT
  #define RTC_OBJC_EXPORT   // expands to NOTHING — hidden visibility!
#endif
```

The binary is structurally valid (correct architecture, correct platform). The failure only appears at link time when building the consuming app.

**Verification:**

```bash
nm -g .cache/webrtc/out/tvos_sim_arm64/WebRTC.framework/WebRTC \
  | grep "_OBJC_CLASS_\$_RTCConfiguration"
# Should print something — if empty: rtc_enable_objc_symbol_export was not set
```

This check is worth keeping because it catches a failure mode that is easy to misdiagnose: the framework looks structurally valid, `xcodebuild -create-xcframework` succeeds, and the consuming app still explodes later with what looks like a random bridge/link failure. In the current repo, that symptom almost always means the binary was built without exported Objective-C symbols.

---

## Current Patch Set

Applied in order by `build_webrtc_tvos.sh`. All patches are idempotent (`git apply --forward` skips already-applied patches).

The patch files live in `Tools/webrtc-build/patches/`.

---

### `0001-tvos-audio-session.patch`

**File:** `sdk/objc/components/audio/RTCAudioSessionConfiguration.m`

**Problem:** WebRTC's default sets `AVAudioSessionCategoryPlayAndRecord` with `MixWithOthers`. On tvOS, `PlayAndRecord` requires microphone input permission — which doesn't exist. The `MixWithOthers` option causes tvOS to assign the audio session ambient priority, setting the hardware volume to 0.0.

**Fix:** Switch to `Playback` + `moviePlayback` mode with no options on tvOS:

```objc
#if TARGET_OS_TV
_category = AVAudioSessionCategoryPlayback;
_categoryOptions = 0;  // NO MixWithOthers — ambient priority = volume 0
_mode = AVAudioSessionModeMoviePlayback;
#endif
```

`moviePlayback` mode also enables Dolby Digital pass-through on supported hardware.

---

### `0002-tvos-disable-video-capture.patch`

**File:** `sdk/objc/components/capturer/RTCCameraVideoCapturer.mm`

**Problem:** Apple TV has no camera. The capturer implementation crashes if invoked.

**Fix:** Wrap the implementation with `#if !TARGET_OS_TV` and provide a no-op `@implementation` for tvOS. All method signatures remain so the API surface is unchanged.

---

### `0003-tvos-remove-opengl.patch`

**File:** `sdk/objc/BUILD.gn`

**Problem:** tvOS has no OpenGL ES. `RTCEAGLVideoView` references OpenGL APIs that don't exist on tvOS.

**Fix:** Change `if (is_ios)` to `if (is_ios && !rtc_target_tvos)` for OpenGL renderer sources. `RTCMTLVideoView` (Metal) remains fully available and is the correct renderer for tvOS.

---

### `0005-tvos-remove-use-blink-assertion.patch`

**File:** `build/config/apple/mobile_config.gni`

**Problem:** The GN config asserts `use_blink=true` for tvOS builds. This is a Chromium-browser-only flag that has no meaning in a standalone WebRTC build. The assertion fires unconditionally and blocks configuration.

**Fix:** Remove the `assert(use_blink, ...)` entirely. It is safe to remove — no tvOS standalone WebRTC functionality depends on `use_blink`.

---

### `0006-tvos-fix-xctest-module-target.patch`

**File:** `webrtc.gni`

**Problem:** The `rtc_test_executable` template sets `xctest_module_target` for all iOS builds. `ios_app_bundle` on tvOS does not support this variable, causing a GN configuration error.

**Fix:** Add `&& target_platform != "tvos"` to the condition that sets `xctest_module_target`.

---

### `0007-tvos-output-only-audio-unit.patch`

**File:** `sdk/objc/native/src/audio/voice_processing_audio_unit.mm`

**Problem:** The default WebRTC AudioUnit uses `kAudioUnitSubType_VoiceProcessingIO`, which requires microphone capability and fails to initialize on tvOS. Additionally, `NSLog` calls in the 20ms CoreAudio RT callback can block 100ms+ under system load, causing audio glitches.

**Fix — AudioUnit switch:**

```objc
#if TARGET_OS_TV
  vpio_unit_description.componentSubType = kAudioUnitSubType_RemoteIO;
  UInt32 enable_input = 0;  // tvOS has no microphone
#else
  vpio_unit_description.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
  UInt32 enable_input = 1;
#endif
```

All input-path-only setup steps are wrapped with `#if !TARGET_OS_TV`.

**Fix — RT-thread safety (NSLog moved to background):**

```objc
// Before (WRONG — NSLog on RT thread):
NSLog(@"[WebRTC][tvOS] playout PCM callback=%llu ...", cb, nf, avg);

// After (CORRECT — dispatch_async is lock-free ~50ns):
dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSLog(@"[WebRTC][tvOS] playout PCM callback=%llu ...", cb, nf, avg);
});
```

**Also adds:**
- PCM throughput counter (`s_tvos_pcm_total_frames`) — logs as `throughput=NNN/s (N.N%)`
- Gap detector — logs `PCM callback STALL gap=XXms` when consecutive callbacks are >40ms apart
- Sample analysis (min/max/avgAbs) — gated to ~2.4s log intervals, not every 20ms callback

---

### `0008-tvos-skip-input-available-check.patch`

**File:** `sdk/objc/components/audio/RTCAudioSession.mm`

**Problem: This is the root cause of complete audio silence on physical Apple TV.**

`configureWebRTCSession:error:` contained:

```objc
if (!self.inputAvailable) {
    RTCLogError(@"No audio input path is available!");
    [self unconfigureWebRTCSession:nil];
    return NO;
}
```

On tvOS, `inputAvailable` is **always** `NO` (no microphone). This caused a silent failure chain:

1. `configureWebRTCSession` returns `NO`
2. `ConfigureAudioSessionLocked()` propagates `false`
3. `InitPlayOrRecord()` returns `false` — audio unit never starts
4. Playout callback never fires → complete silence

Critically: the session appeared fully healthy (WebRTC state `connected`, video rendered, audio track delivered). No error surfaced to Swift code.

**Fix:**

```objc
#if !TARGET_OS_TV
  if (!self.inputAvailable) {
    RTCLogError(@"No audio input path is available!");
    [self unconfigureWebRTCSession:nil];
    return NO;
  }
#endif
```

**Verification after applying:** Connect device to Console.app, start streaming, look for:
```
[WebRTC][tvOS] playout PCM callback=... avgAbs=NNN
```
If `NNN > 0`, audio data is flowing. If the log never appears, the audio unit didn't start.

---

### `0009-tvos-fix-metal-renderer-uiview.patch`

**File:** `sdk/objc/components/renderer/metal/RTCMTLRenderer.h`

**Problem:** The Metal renderer header referenced `UIView` with an incorrect conditional import that failed to compile for tvOS targets.

**Fix:** Correct the conditional import so the header compiles cleanly for all Apple targets including tvOS.

---

### `0010-tvos-neteq-max-delay.patch`

**File:** `audio/channel_receive.cc`

**Problem:** Without a jitter buffer delay cap, NetEQ can accumulate unbounded delay when xCloud delivers audio in bursts. The `jbTargetWinMs` metric climbs continuously, causing `AudioResync` to trigger unnecessarily.

**Fix:** Sets a maximum NetEQ jitter buffer delay cap that prevents runaway delay growth while still allowing normal jitter smoothing. See `AudioStats.jbTargetWinMs` monitoring in [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md).

---

### `0011-tvos-stereo-audio-channels.patch`

**Files:**
- `sdk/objc/native/src/audio/voice_processing_audio_unit.h`
- `sdk/objc/native/src/audio/voice_processing_audio_unit.mm`
- `sdk/objc/native/src/audio/audio_device_ios.mm`

**Problem:** Before this patch, `GetFormat()` always returned a mono AudioUnit format regardless of `outputNumberOfChannels`. Setting `outputNumberOfChannels=2` (for the "Stereo Audio" toggle) configured `FineAudioBuffer` for stereo but the AudioUnit buffer remained mono. This caused the **octave-low bug** — audio played at half speed, one octave lower.

**Fix:**
- `GetFormat(sample_rate, num_channels)` — scales `mBytesPerPacket`, `mBytesPerFrame`, `mChannelsPerFrame` by `num_channels`
- `Initialize(sample_rate, num_channels=1)` — passes channels to `GetFormat`
- `OnGetPlayoutData` — removes the mono-only DCHECK; scales `FineAudioBuffer` ArrayView by `audio_buffer->mNumberChannels`
- All 3 `Initialize()` call sites — forward `playout_parameters_.channels()`

See [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md) §5–6 for the complete octave-low bug explanation.

**Note:** Without this patch, `guide.stereo_audio` must remain `false`. Enabling stereo without patch 0011 will cause the octave-low bug.

---

### `0012-tvos-fix-decoder-pixel-buffer-attributes.patch`

**File:** VideoToolbox decoder configuration

**Problem:** The H.264 hardware decoder pixel buffer attributes needed adjustment for correct Metal texture compatibility on tvOS.

**Fix:** Updates the pixel buffer creation attributes to ensure decoded frames are compatible with the Metal rendering pipeline.

---

## Packaging

After building both slices:

```bash
xcodebuild -create-xcframework \
  -framework .cache/webrtc/out/tvos_arm64/WebRTC.framework \
  -framework .cache/webrtc/out/tvos_sim_arm64/WebRTC.framework \
  -output ThirdParty/WebRTC/WebRTC.xcframework
```

The resulting xcframework:
- `tvos-arm64/` — `LC_BUILD_VERSION` platform 3 (tvOS device)
- `tvos-arm64-simulator/` — `LC_BUILD_VERSION` platform 8 (tvOS Simulator)

`package_xcframework.sh` automatically refreshes `webrtc-version.json` from the live patch directory so committed metadata stays aligned with the actual build inputs.

Do not hand-edit `webrtc-version.json` to paper over a mismatch after the fact. If the metadata is wrong, regenerate it from the packaging script or fix the patch directory / build inputs first.

---

## Common Failure Modes

These are the failures contributors are most likely to hit when touching the WebRTC binary or build scripts.

### Build succeeds, app link fails with `_OBJC_CLASS_$_RTC...` undefined symbols

This is the `rtc_enable_objc_symbol_export=true` problem described above. The binary exists, but the Objective-C surface is hidden from the app target.

### Device video works, but device audio is silent

This is usually **not** a generic WebRTC failure. In Stratix it normally means one of these:

- the binary was built without patch `0008-tvos-skip-input-available-check.patch`
- the app-side tvOS audio bootstrap/reconcile path regressed
- the stream never opened the tvOS audio gate because the remote track or peer-connected milestone was not observed correctly

That is why this build reference cross-links [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md) instead of treating audio as a generic “WebRTC just works” area.

### Audio plays one octave low after enabling stereo

This is the stereo channel mismatch described in patch `0011`. It means the Swift-side configuration allowed stereo output but the vendored binary does not contain the channel-aware AudioUnit / `FineAudioBuffer` changes.

### tvOS simulator framework link fails only on x86_64

That is the unsupported toolchain path, not a random local-environment problem. The active repo pipeline only supports:

- `tvos-arm64`
- `tvos-arm64-simulator`

Trying to force an x86_64 tvOS simulator slice reintroduces the known Mach-O platform mismatch described later in this file.

### Patch metadata and docs disagree

Treat that as a real repo-truth bug, not a style issue. The current public repo carries the binary, patch set, and metadata together. If one moved and the others did not, fix the mismatch before describing the pipeline as stable.

---

## Why x86_64 Simulator Is Not Supported

WebRTC's `ios_clang_x64` toolchain stamps NASM object files with:
```
--macho-min-os=ios17.0-simulator  (Mach-O platform 7 = iOS Simulator)
```

The tvOS Simulator linker requires **platform 8** (tvOS Simulator). This mismatch cannot be patched at the GN level — there is no `tvos_clang_x64` toolchain in the WebRTC source tree.

Apple Silicon Macs run the arm64 simulator natively, so x86_64 is not needed.

---

## Rebuild Checklist

Use this when bumping the WebRTC revision or updating the patch set:

1. **Check the WebRTC changelog** for breaking API changes or new tvOS-relevant fixes
2. **Update the revision** in `Tools/webrtc-build/sync_webrtc.sh` if pinning to a specific commit
3. **Run `sync_webrtc.sh`** — gclient will fetch the new revision
4. **Re-apply patches** — run `build_webrtc_tvos.sh`; it applies patches before building. If a patch fails to apply cleanly, the upstream file changed and the patch needs updating.
5. **Rebuild both slices** — `build_webrtc_tvos.sh` (~5–10 min incremental, ~20 min clean)
6. **Verify symbol export** — run `nm -g` check from the GN trap section
7. **Repackage** — `package_xcframework.sh`
8. **Verify xcframework slices** — should report 2 slices: `tvos-arm64` (platform 3) and `tvos-arm64-simulator` (platform 8)
9. **Test Xcode build** — `xcodebuild ... build` should succeed
10. **Verify audio on device** — look for `[WebRTC][tvOS] playout PCM callback=...` in Console.app; `avgAbs > 0` confirms audio data is flowing; `throughput=48000/s (100.0%)` confirms real-time playback; `playoutRate≈100%` in AudioStats confirms correct channel count
11. **Update `ThirdParty/WebRTC/webrtc-version.json`** — done automatically by `package_xcframework.sh`
12. **Update this document** with new version info and any patch changes

---

## Operational Rule

Do not rebuild the vendored WebRTC framework for ordinary Swift/UI changes.

Rebuild only when:
- the pinned WebRTC revision changes
- the patch set changes
- the binary metadata needs to be refreshed to stay truthful
- a low-level tvOS runtime issue cannot be solved in app-side Swift code

---

## What Actually Works on tvOS

All confirmed working in the Stratix streaming app:

| API | Status | Notes |
|-----|--------|-------|
| `RTCPeerConnection` | Working | Unified Plan semantics |
| `RTCPeerConnectionFactory` | Working | With H.264 codec factories |
| `RTCConfiguration` | Working | `sdpSemantics = .unifiedPlan`, BUNDLE, RTCP-mux |
| `RTCDataChannel` | Working | All 4 xCloud channels simultaneously |
| `RTCIceCandidate` / `RTCIceServer` | Working | Strip `a=` prefix for Xbox signalling |
| `RTCSessionDescription` | Working | Offer/answer exchange |
| `RTCRtpTransceiver` | Working | Audio recvOnly, video recvOnly |
| `RTCDefaultVideoDecoderFactory` | Working | H.264 decode (Xbox game stream) |
| `RTCMTLVideoView` | Working | Metal-based video rendering |
| `RTCAudioSession` | Working | Playback category (patches 0001 + 0008 required) |
| `RTCAudioTrack` / `RTCVideoTrack` | Working | Via delegate callbacks |
| `RTCCameraVideoCapturer` | Stubbed | No camera; methods are no-ops |
| `RTCEAGLVideoView` | Unavailable | OpenGL ES not on tvOS; use Metal |
| `RTCRtpReceiver.capabilities(forKind:)` | Unavailable | Not in standalone build |
| x86_64 Simulator | Not supported | NASM platform tagging issue |

“Works on tvOS” in this table means more than “the class exists in the framework.” In the live repo, these APIs are actually exercised through:

- `WebRTCClientImpl` in the app target
- `WebRTCBridge` in `StreamingCore`
- the current xCloud session lifecycle in `StreamingSession` and `StreamingRuntime`
- the renderer attach path in the app-owned streaming surface

That distinction is why the repo does not rely on generic upstream marketing language about tvOS support. It documents the subset the current app really uses and validates.

---

## Xcode Integration

After packaging:

1. Embed `ThirdParty/WebRTC/WebRTC.xcframework` in the app target with **Embed & Sign**
2. Bridging header contains `#import <WebRTC/WebRTC.h>`
3. Build Settings → **Other Swift Flags**: add `-DWEBRTC_AVAILABLE`
4. The `#if WEBRTC_AVAILABLE` flag gates `WebRTCClientImpl` — without it, the app compiles with `MockWebRTCBridge`

---

## Related Docs

- [WEBRTC_GUIDE.md](WEBRTC_GUIDE.md) — integration boundary and responsibilities
- [WEBRTC_CAPABILITIES.md](WEBRTC_CAPABILITIES.md) — what's confirmed working and unsupported
- [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md) — audio patches deep dive
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md) — how WebRTC fits in the streaming stack
- [../Tools/webrtc-build/README.md](../Tools/webrtc-build/README.md) — build script quick-start
