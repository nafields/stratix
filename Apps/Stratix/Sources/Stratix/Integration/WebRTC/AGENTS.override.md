# AGENTS.override.md — Integration/WebRTC/

This directory is the concrete implementation boundary for the vendored WebRTC framework. Every file here is conditionally compiled with `#if WEBRTC_AVAILABLE`. This is the only place in the app where WebRTC types appear directly.

**Modernization contract reference:** For modernization work in this boundary layer, use `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix.

---

## Files

### MetalVideoRenderer cluster

| File | Status | Notes |
|------|--------|-------|
| `MetalVideoRenderer.swift` | Keep | Root `RTCVideoRenderer`-conformant Metal renderer. |
| `MetalVideoRendererDrawPipeline.swift` | Keep | Draw-pipeline setup and frame submission. |
| `MetalVideoRendererPresentationResources.swift` | Keep | Texture and scaler resource lifecycle. |
| `MetalVideoRenderer+Sizing.swift` | Keep | Draw-size support for the Metal path. |
| `CASShader.metal` | Keep | Metal compute shader for conversion and CAS upscaling. |

### SampleBufferDisplayRenderer cluster

| File | Status |
|------|--------|
| `SampleBufferDisplayRenderer.swift` | Keep |
| `SampleBufferDisplayRendererLifecycle.swift` | Keep |
| `SampleBufferDisplayRendererLowLatencyFrameInterpolation.swift` | Keep |
| `SampleBufferDisplayRendererLowLatencySuperResolution.swift` | Keep |
| `SampleBufferDisplayRendererLowLatencySupport.swift` | Keep |
| `SampleBufferDisplayRendererPlainPipeline.swift` | Keep |

These are substantive files. Do not collapse them back into a single monolith and do not add tiny wrapper shards around them.

### WebRTCClientImpl cluster

| File | Role |
|------|------|
| `WebRTCClientImpl.swift` | Root concrete `WebRTCBridge` implementation. |
| `WebRTCClientImplBridge.swift` | Objective-C bridge layer. |
| `WebRTCClientImplCallbackRouting.swift` | Delegate callback routing into the Swift surface. |
| `WebRTCClientImplDataChannels.swift` | Data-channel setup and teardown. |
| `WebRTCClientImplRTCAudioSessionDelegate.swift` | Audio-session delegate conformance. |
| `WebRTCClientImplRTCPeerConnectionDelegate.swift` | Peer-connection delegate conformance. |
| `WebRTCClientImplStats.swift` | WebRTC stats collection. |
| `WebRTCClientImplTVOSAudio.swift` | tvOS-specific audio handling. |
| `WebRTCClientImplTVOSAudioBootstrap.swift` | tvOS audio bootstrap path. |
| `WebRTCClientImplDataChannelDelegateProxy.swift` | Data-channel delegate proxy class. |
| `WebRTCClientStateSupport.swift` | Supporting state and helper types. |

The `WebRTCClientImpl` split is correct and should be preserved. Each companion file owns one responsibility.

---

## Rules

1. All files in this directory are `#if WEBRTC_AVAILABLE`-guarded. Do not remove that guard.
2. Do not add new WebRTC imports outside `Integration/WebRTC/`.
3. `MetalVideoRenderer` is `@unchecked Sendable` with documented locking-based safety. Do not remove that without an equivalent proof.
4. The tvOS audio behavior in this directory must stay aligned with the patch set under `Tools/webrtc-build/patches/`.

---

## FrameProbeRenderer note

`FrameProbeRenderer` lives in `Features/Streaming/Rendering/UIKitAdapters/FrameProbeRenderer.swift`, not here. It is probe infrastructure rather than part of the concrete WebRTC bridge root.

It still needs concurrency care:

- `renderFrame()` runs from WebRTC's internal thread pool
- mutable probe state crosses concurrency domains
- any UI-facing callback must hop safely back to `@MainActor`

---

## Concurrency

`MetalVideoRenderer` receives `RTCVideoRenderer` callbacks from WebRTC-managed threads. UI-facing callbacks such as telemetry and first-frame notifications must route back to `@MainActor`.

`WebRTCClientImpl` delegate conformances must not touch `StreamSurfaceModel` or other UI-facing state directly from the WebRTC thread.

---

## Tests

- `StratixTests/WebRTCClientImplSafetyTests.swift`
- `StratixTests/WebRTCVideoSurfaceViewBinderTests.swift`
