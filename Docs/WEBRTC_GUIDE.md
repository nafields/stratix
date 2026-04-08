# WebRTC Guide

This guide explains the live WebRTC boundary in Stratix: where the concrete
framework integration lives, why the repo ships a committed custom build, how the
package boundary is kept clean, and when contributors actually need to touch the
vendored binary.

> **What most contributors need to know:** The vendored `WebRTC.xcframework` is already built and committed. You do not need to rebuild it to work on the app, the shell, the streaming runtime, or any of the packages. The only time you need to touch the WebRTC binary is if you are changing the tvOS-specific patches (audio session, stereo support, etc.) or upgrading to a newer WebRTC revision. If that is not you, read [Where WebRTC Lives](#where-webrtc-lives) and [Guard Rule](#guard-rule), then move on.

This is a current-state repo guide. It is not a generic WebRTC tutorial and it is
not a historical narrative of every previous integration shape.

## Why Stratix Ships A Custom WebRTC Build

Stratix does not depend on an external package manager WebRTC wrapper. The repo
ships a committed `WebRTC.xcframework` because the current Apple TV runtime needs a
specific combination of packaging, platform patches, and stable local availability.

The practical reasons are:

- the app needs a known-good binary contributors can build against immediately
- tvOS-specific behavior requires a curated patch set, not a stock upstream drop
- the concrete integration has to support the repo’s streaming, rendering, and
  audio paths as they exist today
- the package layer must stay testable without importing the framework directly

The key distinction is between:

- the framework binary that makes the concrete runtime possible
- the package-level bridge abstraction that keeps the rest of the repo decoupled

## Where WebRTC Lives

### Committed Binary

The vendored framework is committed at:

- [ThirdParty/WebRTC/WebRTC.xcframework](../ThirdParty/WebRTC/WebRTC.xcframework)

The committed metadata is:

- [ThirdParty/WebRTC/webrtc-version.json](../ThirdParty/WebRTC/webrtc-version.json)

### Build Tooling

The source-build pipeline lives at:

- [Tools/webrtc-build](../Tools/webrtc-build)

Important entrypoints:

- `Tools/webrtc-build/sync_webrtc.sh`
- `Tools/webrtc-build/build_webrtc_tvos.sh`
- `Tools/webrtc-build/package_xcframework.sh`

### Concrete Integration Boundary

The concrete Swift-side integration boundary is:

- [Apps/Stratix/Sources/Stratix/Integration/WebRTC](../Apps/Stratix/Sources/Stratix/Integration/WebRTC)

This is the only place that should directly own WebRTC framework behavior in the
application codebase.

## Guard Rule

All concrete WebRTC use must remain behind:

- `#if WEBRTC_AVAILABLE`

That rule is important for two reasons:

1. package code must not take a hard dependency on the vendored framework
2. the app still needs a viable non-framework path for tests, previews, and other
   development surfaces that should not require the full runtime binary

Do not move concrete WebRTC symbol references out of the integration boundary.

## Real Bridge vs Mock Bridge

One of the most important repo design choices is that the mock bridge is deliberate,
not incidental.

### Mock Path

`WebRTCClientImpl.swift` includes `MockWebRTCBridge`, which is always compiled.

The mock bridge exists so the rest of the stack can still exercise the streaming
control path without linking the real framework. It provides:

- synthetic offer creation
- synthetic connected peer behavior
- synthetic channel-open events
- a no-op send path
- clean shutdown behavior

That makes it possible to keep higher-level code testable and preview-friendly.

### Real Path

When `WEBRTC_AVAILABLE` is enabled, the same integration folder also provides the
real `WebRTCClientImpl`, which owns:

- peer connection factory and peer connection construction
- transceiver and data-channel setup
- offer/answer and ICE operations
- callback routing
- stats collection
- tvOS audio session integration
- remote track publication to the app/rendering layer

The point of the mock/real split is that package code does not need to know which
one is active. It only depends on the `WebRTCBridge` contract.

## Package Boundary

The package boundary is defined by:

- [Packages/StreamingCore/Sources/StreamingCore/WebRTCBridge.swift](../Packages/StreamingCore/Sources/StreamingCore/WebRTCBridge.swift)

`StreamingCore` depends on `WebRTCBridge`, not on `WebRTC.xcframework`.

That boundary is one of the most important repo rules because it keeps the lower
layers testable and lets the app target own the Apple-platform specifics:

- UIKit
- Metal
- tvOS audio behavior
- concrete framework delegates

In other words:

- `StreamingCore` owns streaming runtime mechanics
- the app target owns the concrete framework-backed implementation of those mechanics

## Current Integration Split

The current integration folder is broader than just one bridge file. The live split
is:

| File | Responsibility |
| --- | --- |
| `WebRTCClientImpl.swift` | Declares the mock bridge and the framework-backed bridge root. |
| `WebRTCClientImplBridge.swift` | Offer/answer, ICE, connection state mapping, transceiver setup, shutdown. |
| `WebRTCClientImplCallbackRouting.swift` | Routes runtime callbacks and retained-track handoff into the session layer. |
| `WebRTCClientImplDataChannels.swift` | Data channel creation, wiring, send behavior, and channel bookkeeping. |
| `WebRTCClientImplDataChannelDelegateProxy.swift` | Delegate proxy that isolates per-channel event handling. |
| `WebRTCClientImplRTCPeerConnectionDelegate.swift` | Peer connection delegate callbacks. |
| `WebRTCClientImplRTCAudioSessionDelegate.swift` | `RTCAudioSession` delegate handling for the tvOS audio path. |
| `WebRTCClientImplStats.swift` | Stats collection and snapshot shaping. |
| `WebRTCClientImplTVOSAudio.swift` | Live tvOS audio runtime controls and reconcile behavior. |
| `WebRTCClientImplTVOSAudioBootstrap.swift` | tvOS audio bootstrap and default configuration helpers. |
| `WebRTCClientStateSupport.swift` | Internal state support utilities for the bridge. |
| `MetalVideoRenderer.swift` and helpers | App-owned Metal-backed video rendering path that consumes the remote track. |

This is why it is misleading to describe the integration as if one file alone owns
“WebRTC.” The live boundary is a small subsystem.

## Current Committed Build State

The committed metadata currently records:

| Field | Value |
| --- | --- |
| Source | `webrtc-googlesource` |
| Revision | `6f7ad28e168d903245c59c2b3d2462f437259cd8` |
| Branch | `main` |
| Built at | `2026-03-18T15:29:29Z` |
| Toolchain | `Xcode 26.3` |
| Patch count | `12` |

The repo currently expects device and Apple Silicon simulator slices. x86_64
simulator support is intentionally not part of the active path.

The metadata file is not decorative. It is the source of truth for the committed
binary’s revision and patch set. If the framework changes, the metadata must move
with it.

## Current Build Pipeline

The authoritative build notes live in:

- [Tools/webrtc-build/README.md](../Tools/webrtc-build/README.md)

The practical rebuild flow is:

```bash
Tools/webrtc-build/sync_webrtc.sh
Tools/webrtc-build/build_webrtc_tvos.sh
Tools/webrtc-build/package_xcframework.sh
```

The build pipeline currently expects:

- Apple Silicon host
- Xcode selected with `xcode-select`
- Python 3 on `PATH`
- enough disk space for checkout and build outputs
- working network access for source sync

The active GN/build notes that matter most for contributors are:

- `target_platform="tvos"`
- `rtc_enable_objc_symbol_export=true`
- the GN deployment target used by the framework pipeline is lower than the repo’s
  app/package floor and should not be confused with the app’s public runtime floor
- x86_64 simulator support is intentionally out of scope for the committed binary

That symbol-export setting is worth calling out because it is one of the easiest
ways to produce a framework that looks structurally valid but is unusable by the app.

## What The App-Side WebRTC Layer Owns

The app target owns the concrete platform integration work that package code must
not absorb.

That includes:

- peer connection delegate handling
- ordered data-channel creation and runtime callback wiring
- remote audio track ownership
- tvOS audio session behavior
- stats collection from the concrete bridge
- handoff of remote video into the renderer stack

This division is intentional. The packages own the runtime logic, but the app owns
platform implementation details such as:

- `RTCPeerConnection`
- `RTCDataChannel`
- `RTCAudioSession`
- Metal-backed rendering surfaces

## How The Stream Runtime Uses The Bridge

The bridge is consumed through `StreamingCore`, especially by:

- `StreamingSession`
- `StreamingRuntime`

The live interaction looks like this:

1. `StratixCore` launch workflows create a `StreamingSession`
2. `StreamingSession` wraps a model and delegates connection ownership downward
3. `StreamingRuntime` calls bridge operations such as:
   - `applyH264CodecPreferences()`
   - `createOffer()`
   - `setLocalDescription(...)`
   - `setRemoteDescription(...)`
   - `addRemoteIceCandidate(...)`
   - `send(...)`
   - `close()`
4. the bridge publishes:
   - connection-state changes
   - local ICE candidates
   - channel open events
   - data/text channel messages
   - remote video track
   - remote audio track

That is the architectural reason the bridge abstraction exists. The runtime needs a
compact contract for signaling and callbacks, while the app target needs freedom to
implement that contract however the current platform/runtime requires.

## When You Need To Touch The Binary

Most day-to-day work in Stratix does not require rebuilding WebRTC.

You usually do **not** need a rebuild when:

- you are changing SwiftUI stream UI
- you are changing `StreamController` or workflow logic
- you are changing session/runtime code above the bridge contract
- you are changing render-surface coordination in app-side Swift
- you are adjusting diagnostics or stats presentation

You **do** need to rebuild or reconsider the committed binary when:

- the pinned upstream revision changes
- the patch set changes
- a concrete platform behavior cannot be fixed in the app-side Swift layer
- the binary’s metadata would otherwise become untruthful
- the device/simulator slice outputs or packaging expectations change

The repo intentionally keeps that threshold high. The binary should move when it
must, not because ordinary app work happened nearby.

## Practical Constraints

There are a few practical rules contributors should keep in mind:

- the concrete framework lives only in the app target boundary
- package code should continue to compile conceptually against the bridge contract
- if you add a new app-side WebRTC helper file, it belongs inside the integration
  boundary, not in `StreamingCore`
- build metadata and docs must stay synchronized with the current patch set
- if a doc links to a WebRTC/rendering path, it must point at a live doc, not a
  removed historical filename

## Related Docs

- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md)
- [WEBRTC_CAPABILITIES.md](WEBRTC_CAPABILITIES.md)
- [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md)
- [TESTING.md](TESTING.md)
- [XCODE_VALIDATION_MATRIX.md](XCODE_VALIDATION_MATRIX.md)
