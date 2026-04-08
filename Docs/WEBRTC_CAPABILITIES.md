# WebRTC Capabilities

This document summarizes what the committed WebRTC integration currently supports on tvOS in the live `Stratix` tree, explains why community sources mark tvOS features as unsupported, and documents the exact capabilities confirmed working in production.

---

## Why react-native-webrtc Lists These Features as Unsupported on tvOS

The [react-native-webrtc](https://github.com/react-native-webrtc/react-native-webrtc) README lists the following as **not supported on tvOS**:

| Feature | tvOS |
|---------|------|
| Data Channels | ❌ |
| Screen Capture | ❌ |
| Unified Plan | ❌ |
| Simulcast | ❌ |

**This is a packaging problem, not a WebRTC capability problem.**

react-native-webrtc does not bundle its own WebRTC binary — it depends on **JitsiWebRTC**, a CocoaPods pod that packages prebuilt WebRTC binaries. In recent releases (~M124+), JitsiWebRTC stopped publishing tvOS slices. When you try to add it to a tvOS target, CocoaPods rejects the pod entirely:

```
The platform of the target (tvOS 16.0) is not compatible with JitsiWebRTC (124.0.0),
which does not support tvOS.
```

Because the pod can't be imported, **none** of the peer connection APIs are available — not `RTCDataChannel`, not `RTCConfiguration`, not anything. This is why the feature matrix shows everything as unsupported. **The matrix reflects a packaging failure, not a WebRTC capability.**

Stratix builds WebRTC from source with tvOS-specific patches and a corrected GN flag (`rtc_enable_objc_symbol_export=true`). All of the above features work.

The important detail is that the repo no longer treats "tvOS WebRTC support" as a yes/no badge. It separates three different questions:

1. Can Google WebRTC be built for tvOS at all?
2. Can the committed Stratix binary expose the Objective-C / Swift surface the app needs?
3. Does the current product actually exercise those capabilities end to end?

For Stratix, the answer is yes on all three, but only for the subset the current streaming product and runtime are designed around. That is why this document stays specific instead of copying broad community compatibility tables.

---

## What Stratix Builds

- **Source:** Google WebRTC main branch
- **Format:** `WebRTC.xcframework` with two slices:
  - `tvos-arm64` — Apple TV device (Mach-O platform 3)
  - `tvos-arm64-simulator` — Apple Silicon Simulator (Mach-O platform 8)
- **Deployment target:** tvOS 17.0
- **Build tool:** GN + Ninja
- **Patches applied:** 11 tvOS-specific patches (see [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md))

---

## Confirmed Working on tvOS

All of these are confirmed working in Stratix:

### Peer Connection Core

| API | Status | Notes |
|-----|--------|-------|
| `RTCPeerConnectionFactory` | ✅ Working | Creates peer connections with H.264 codec factories |
| `RTCConfiguration` (Unified Plan) | ✅ Working | `sdpSemantics = .unifiedPlan`, BUNDLE policy, RTCP-mux |
| `RTCPeerConnection` | ✅ Working | Full delegate callbacks (state changes, candidates, tracks) |
| `RTCSessionDescription` | ✅ Working | Offer/answer exchange |
| `RTCIceCandidate` / `RTCIceServer` | ✅ Working | ICE negotiation including Teredo IPv6 expansion |
| `RTCRtpTransceiver` | ✅ Working | Stratix uses `recvOnly` transceivers on tvOS for both remote audio and video |

### Data Channels

| Channel | Status | xCloud role |
|---------|--------|------------|
| `RTCDataChannel` (ordered) | ✅ Working | All 4 xCloud channels run simultaneously |
| `RTCDataChannelConfiguration` | ✅ Working | Ordered, max-retransmit, protocol labels |
| `RTCDataChannelDelegate` | ✅ Working | `didReceiveMessageWith:`, state changes |

Stratix runs 4 data channels simultaneously (`controlV1`, `1.0`, `messageV1`, `chatV1`). All open and exchange data correctly.

That is not theoretical capability. The live bridge configures those labels explicitly in `WebRTCClientImplDataChannels.swift`, and the package/runtime layer depends on them for distinct jobs:

| Channel | Protocol label | Primary role in the live repo |
|---------|----------------|-------------------------------|
| Control | `controlV1` | JSON control-plane coordination and stream commands |
| Input | `1.0` | Packed binary controller/input packets from `InputBridge` and `InputChannel` |
| Message | `messageV1` | Message-plane metadata and stream-side state |
| Chat | `chatV1` | Chat / ancillary lane reserved by the current runtime model |

All four are ordered channels in the current bridge. That matters because the runtime is designed around predictable, protocol-labeled lanes rather than one generic data channel.

### Unified Plan

`config.sdpSemantics = .unifiedPlan` works on tvOS. Transceivers, mid-based routing, and multiple m-sections are all functional. The Stratix `StreamingCore` runtime is built around Unified Plan assumptions.

One live-repo detail is worth spelling out: the app bridge does not simply inherit whatever transceiver shape upstream WebRTC happens to prefer. `WebRTCClientImplBridge.swift` explicitly installs:

- audio transceiver: `recvOnly` on tvOS
- video transceiver: `recvOnly`

That matches the actual Apple TV product posture. The app is consuming remote audio/video and is not pretending the hardware has a usable microphone or camera path.

### Audio and Video

| API | Status | Notes |
|-----|--------|-------|
| `RTCDefaultVideoDecoderFactory` | ✅ Working | H.264 decode of Xbox game stream |
| `RTCMTLVideoView` | ✅ Working | Metal-based video rendering (tvOS requires Metal; no OpenGL) |
| `RTCAudioSession` | ✅ Working | Requires Patch 0001 (Playback category) + Patch 0008 (skip inputAvailable) |
| `RTCAudioTrack` / `RTCVideoTrack` | ✅ Working | Surfaced through the current delegate/transceiver discovery path |
| `kRTCMediaStreamTrackKindAudio/Video` | ✅ Working | Track type constants |

On top of the raw framework capability, the current repo also proves out the app-side responsibilities needed to make those tracks usable:

- track discovery is routed through `RTCPeerConnectionDelegate` callbacks and transceiver inspection
- tvOS audio-track enablement is gated by the app-owned start-gate logic, not just “track arrived”
- renderer selection stays outside the framework and is handled by the app-owned streaming/rendering surface

That split is why the framework can stay focused on transport and codec duties while the app keeps policy control over tvOS playback behavior.

---

## What “Confirmed Working” Means In This Repo

For this document, "confirmed working" means the capability is present in the committed binary **and** the current source tree actually uses it in a real product path.

Examples:

- `RTCDataChannel` counts as confirmed because the live bridge creates all four channels, the runtime sends real control/input/message traffic through them, and the stream can stay healthy with those lanes active.
- `RTCMTLVideoView` counts as confirmed because the framework class is available and the app’s Metal-backed renderer path depends on that integration surface.
- `RTCRtpTransceiver` counts as confirmed because the bridge explicitly adds transceivers and the live stream lifecycle depends on those directions being correct.

By contrast, capabilities like simulcast are **not** marked confirmed just because upstream WebRTC likely supports them. They are marked based on what the committed repo actually builds, wires, and exercises.

---

## What Does NOT Work on tvOS

| Capability | Status | Reason |
|-----------|--------|--------|
| Camera capture (`RTCCameraVideoCapturer`) | ❌ Stubbed | Apple TV has no camera; Patch 0002 provides a no-op implementation |
| Screen capture | ❌ | tvOS has no screen recording API for this use case |
| OpenGL renderer (`RTCEAGLVideoView`) | ❌ | tvOS has no OpenGL ES; use `RTCMTLVideoView` instead |
| `RTCRtpReceiver.capabilities(forKind:)` | ❌ | Not available in the standalone framework build |
| x86_64 Simulator | ❌ | NASM toolchain tags object files with iOS Simulator (platform 7), not tvOS Simulator (platform 8) — linker rejects the mismatch. arm64 Simulator works fine on Apple Silicon Macs. |
| Simulcast | ⚠️ Untested | Framework supports it but Stratix has not wired it up |
| Continuity Camera (tvOS 17+) | ⚠️ Not integrated | Possible but not implemented |
| Multi-stream runtime | Not supported | Product supports one active stream at a time |

---

## Why x86_64 Simulator Is Not Possible

WebRTC's `ios_clang_x64` toolchain stamps NASM object files with:

```
--macho-min-os=ios17.0-simulator
```

This sets Mach-O platform 7 (iOS Simulator). The tvOS Simulator linker requires platform 8 (tvOS Simulator). The mismatch causes every `.s` assembly file to be rejected at link time. There is no `tvos_clang_x64` toolchain in WebRTC's source tree. arm64 Simulator on Apple Silicon is the only viable simulator path.

---

## The Critical GN Flag

When building WebRTC, `rtc_enable_objc_symbol_export=true` is required. Without it:

1. The build succeeds and produces a valid xcframework
2. Every ObjC class is built with hidden visibility (`RTC_OBJC_EXPORT` expands to nothing)
3. Linking the consuming app fails with hundreds of `Undefined symbols for architecture arm64: _OBJC_CLASS_$_RTCConfiguration...` errors

The binary passes all format checks — the failure only appears when linking the Stratix app. See [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md) for the full rebuild guide.

---

## Integration Boundary Rules

| Rule | Why |
|------|-----|
| Concrete WebRTC imports only in `Apps/Stratix/Sources/Stratix/Integration/WebRTC/` | Keeps framework dependency isolated to the app target |
| `StreamingCore` depends only on `WebRTCBridge` protocol | Packages never import `WebRTC.xcframework` directly |
| All concrete WebRTC code behind `#if WEBRTC_AVAILABLE` | Enables simulator + package builds with `MockWebRTCBridge` |

This boundary is one of the most important modernization outcomes in the repo. It means:

- package tests can stay fast and deterministic without linking the vendored framework
- the app target owns the risky platform integration and build-flag coupling
- docs like this one can describe framework capabilities without implying that every package is framework-aware

---

## MockWebRTCBridge for Non-Device Builds

When `-DWEBRTC_AVAILABLE` is absent (simulator builds without the framework, package tests), `MockWebRTCBridge` is used:

```swift
// In package tests — no real WebRTC activity:
let mock = MockWebRTCBridge()
let session = StreamingSession(bridge: mock)
mock.simulateConnectionState(.connected)
```

`MockWebRTCBridge` provides stub implementations for the entire `WebRTCBridge` protocol. All `StreamingCore` logic can be tested without requiring the actual framework.

That mock path is not just a convenience for previews. It is part of how the repo keeps capability claims honest:

- if a behavior only works with the real framework, it belongs in the app/WebRTC boundary docs
- if a behavior is part of the package-side runtime contract, it should still be exercisable through `MockWebRTCBridge`

---

## Source Files

| File | Role |
|------|------|
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImpl.swift` | Main concrete bridge plus always-compiled `MockWebRTCBridge` |
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplBridge.swift` | Peer connection setup, transceivers, offer/answer, and ICE wiring |
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplRTCPeerConnectionDelegate.swift` | Connection-state mapping, candidate forwarding, and remote-track discovery |
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplDataChannels.swift` | Data channel creation and message routing |
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplStats.swift` | WebRTC stats extraction and snapshot shaping for runtime diagnostics |
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplTVOSAudioBootstrap.swift` | tvOS default audio bootstrap and initial playback configuration |
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplTVOSAudio.swift` | tvOS audio gate, watchdog, drain/re-enable behavior, and live boost updates |
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplRTCAudioSessionDelegate.swift` | Route-aware audio reconcile path and session delegate handling |
| `Apps/Stratix/Sources/Stratix/Integration/WebRTC/MetalVideoRenderer.swift` | Metal CAS render path |
| `Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/SampleBufferDisplayRenderer.swift` | `AVSampleBufferDisplayLayer` render path |
| `Packages/StreamingCore/Sources/StreamingCore/WebRTCBridge.swift` | Protocol abstraction (no WebRTC import) |

---

## Related Docs

- [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md) — Complete rebuild guide with all 11 patches and GN arguments
- [WEBRTC_GUIDE.md](WEBRTC_GUIDE.md)
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md) — Audio patches in depth
