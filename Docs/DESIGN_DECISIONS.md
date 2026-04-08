# Design Decisions

This document records the major engineering decisions behind Stratix, written in ADR format. ADR stands for Architecture Decision Record — each entry documents a real choice that was made, the context that made the choice necessary, what was decided, and what was explicitly rejected.

**Why this format matters:** Code tells you what was built. ADRs tell you why. If you find yourself looking at a pattern in the codebase and wondering "why is it done this way?" — the answer is probably here. And if you are proposing a change that contradicts one of these decisions, reading the relevant ADR will help you understand the tradeoffs you are accepting.

This is not a historical archive. Use it to understand why the repo is shaped the way it is and what tradeoffs were consciously accepted. See also [`ARCHITECTURE.md`](ARCHITECTURE.md) for the current structural picture, and [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md) for where code belongs today.

---

## ADR-001: Native tvOS App — Not a Cross-Platform Wrapper

**Status:** Accepted
**Date:** 2026-02-25

### Context

The goal was to bring Xbox Cloud Gaming streaming to Apple TV. The reference implementations — [unknownskl/greenlight](https://github.com/unknownskl/greenlight) and [unknownskl/xbox-xcloud-player](https://github.com/unknownskl/xbox-xcloud-player) — are written in TypeScript and run in browsers or Electron. Apple TV (tvOS) has no browser runtime and no official xCloud app from Microsoft.

The implementation needed to:
1. Implement Microsoft device code OAuth from scratch
2. Replicate the xCloud signalling protocol (SDP/ICE over HTTPS)
3. Implement the binary input packet format (little-endian gamepad frames)
4. Render H.264 video with low latency on a TV
5. Support the Apple TV Siri Remote and physical game controllers

### Decision

**Native tvOS application in Swift 6.2 / SwiftUI**, structured as a Swift Package Manager monorepo with 7 packages.

- Swift 6.2 with strict concurrency for correctness guarantees across actor boundaries
- 7 Swift packages for clean separation of concerns and testability
- xCloud-first with xHome (local console streaming) as secondary target
- Custom WebRTC build pipeline (`Tools/webrtc-build/`) — 11 tvOS patches applied to Google's source
- `WebRTCBridge` protocol abstraction so packages compile and test without the framework binary
- TypeScript reference used to understand the protocol, not executed at runtime

### Consequences

**Positive:**
- Full control over performance, memory, and latency — no JavaScript/Dart runtime
- Direct access to tvOS APIs: `AVAudioSession`, `GameController`, `Metal`, `AVFoundation`
- Type-safe binary input protocol implementation matching the TypeScript spec exactly
- Unit tests run on macOS without a device or simulator
- `MockWebRTCBridge` lets UI development proceed without the WebRTC source tree

**Negative / Trade-offs:**
- WebRTC must be built and maintained manually
- Microsoft's xCloud and Xbox Live APIs are undocumented; TypeScript reference must be reverse-engineered for protocol changes
- No TypeScript/React Native skill transfer

### Rejected Alternatives

**React Native + react-native-webrtc:** `react-native-webrtc`'s tvOS feature matrix is misleading — it lists tvOS as supported but the WebRTC build drops tvOS-specific patches. Audio does not work on device. The JS runtime is unnecessary overhead for a real-time streaming app. tvOS focus engine is difficult to express idiomatically in React Native.

**Flutter:** tvOS support is community-maintained and lags significantly. No mature WebRTC package with working tvOS audio. The Dart rendering model conflicts with Metal-based video rendering. Accessing tvOS-specific APIs requires platform channels — equivalent complexity to native.

---

## ADR-002: Workspace-First SPM Monorepo

**Status:** Accepted
**Date:** 2026-02-25

### Context

The project needed a structure that supported:
- One tvOS app target consuming all packages
- Package-level unit tests running on macOS (no simulator required)
- Clean dependency direction: packages never depend on the app
- Multiple schemes for different validation scenarios

### Decision

One `Stratix.xcworkspace` with one app target (`Apps/Stratix`) and seven local Swift packages (`Packages/*`).

Packages depend only on other packages. The app depends on packages. `StratixModels` is the leaf package — no local dependencies.

Schemes are scheme-scoped, not project-scoped:
- `Stratix-Debug` — day-to-day development
- `Stratix-ShellUI` — shell validation without auth/network
- `Stratix-Packages` — package unit tests on macOS
- `Stratix-Validation` — full validation sweep

### Consequences

**Positive:**
- Package boundaries enforce clean dependency direction at compile time
- Package tests run fast on macOS without a device or tvOS simulator
- Schemes allow targeted validation without running the full app

**Negative / Trade-offs:**
- Adding a new shared type requires deciding which package it belongs to (good friction, but friction)
- Workspace adds a layer above individual `.xcodeproj` files

### Rejected Alternatives

**Single xcodeproj with folders:** Makes dependency direction invisible and encourages circular access. Package boundaries cannot be enforced. Cannot run tests on macOS without the simulator.

---

## ADR-003: Strict Swift 6.2 Concurrency as a Hard Floor

**Status:** Accepted
**Date:** 2026-02-25

### Context

The app has multiple concurrency boundaries:
- Main actor (UI, controllers)
- Isolated actors (library hydration, cache)
- Off-main tasks (rendering, WebRTC callbacks)
- Real-time threads (CoreAudio I/O thread)

Without strict checking, data races are silent and appear as intermittent crashes in production.

### Decision

**Swift 6.2 with `complete` concurrency checking is mandatory for all targets and packages.** No downgrade.

Three narrow production exceptions exist where `@unchecked Sendable` is required (documented with justification in `CONCURRENCY_EXCEPTIONS.md`). All other cross-boundary state must use `@MainActor`, `actor`, or `Sendable` value types.

### Consequences

**Positive:**
- Data race categories are eliminated at compile time, not discovered at runtime
- Actor isolation boundaries are machine-verified, not documentation-only
- New code written to wrong isolation assumptions fails to compile rather than crash in production

**Negative / Trade-offs:**
- WebRTC C++ callbacks are `@unchecked Sendable` — requires manual reasoning in those files
- Some third-party patterns that predate Swift 6 require adaptation

### Rejected Alternatives

**Minimal concurrency (Swift 5 mode):** Eliminates compile-time race detection. The streaming path has enough concurrency complexity that silent races are a real risk. The three production exceptions are manageable.

---

## ADR-004: Custom WebRTC tvOS Build (Not JitsiWebRTC or react-native-webrtc)

**Status:** Accepted
**Date:** 2026-02-25

### Context

Stratix requires a WebRTC implementation that:
1. Runs on tvOS (Apple TV 4K)
2. Supports `RTCPeerConnection`, `RTCDataChannel`, H.264 decode, and audio playback
3. Integrates with a native Swift codebase

No pre-built binary with complete tvOS support exists from any maintained source.

### Decision

**Build WebRTC from Google's source** at a pinned commit, applying 11 tvOS-specific patches, using the GN/Ninja build system. Package as `WebRTC.xcframework` committed to `ThirdParty/WebRTC/`.

Two slices:
- `tvos-arm64` — Apple TV device
- `tvos-arm64-simulator` — Apple Silicon simulator only (x86_64 not supported)

**Critical GN flag:**
```
rtc_enable_objc_symbol_export = true
```
Without this flag, all Objective-C class symbols have hidden visibility and the Xcode linker fails with `Undefined symbols for architecture arm64: _OBJC_CLASS_$_RTC*`. This flag is undocumented in WebRTC's official documentation.

### Consequences

**Positive:**
- Full tvOS WebRTC support: peer connections, data channels, H.264 decode, Metal video, audio playback — all working on tvOS 26+ device and arm64 simulator
- Framework committed to repo — contributors build without a 10 GB WebRTC source checkout
- `WebRTCBridge` protocol abstraction enables unit tests on macOS

**Negative / Trade-offs:**
- Framework must be rebuilt manually when updating the WebRTC revision
- 11 patches must be kept current with Google's source
- x86_64 Simulator not supported (NASM toolchain limitation — see `WEBRTC_BUILD_REFERENCE.md`)
- Build time: 30–60 min for a clean build

### Rejected Alternatives

**JitsiWebRTC CocoaPod:** JitsiWebRTC dropped tvOS support in M124+. Adding the pod to a tvOS target fails at CocoaPods resolution with a platform compatibility error — before any code is compiled. No ETA for restoration.

**Community forks (Conduit, daily.co, 100ms):** No fork publishes arm64 tvOS slices as of 2026. Forks with tvOS support are typically outdated (M100 or earlier), introducing security and protocol compatibility risk.

**react-native-webrtc:** Lists tvOS as supported but the underlying WebRTC build drops tvOS-specific patches. Audio does not work on physical Apple TV hardware.

---

## ADR-005: @Observable State — Not ObservableObject

**Status:** Accepted
**Date:** 2026-02-25

### Context

The app uses SwiftUI for its entire UI layer. It needs a state observation model that:
- Integrates cleanly with Swift 6.2 strict concurrency
- Supports `@MainActor` isolation for controllers
- Avoids the `willSet` / `didSet` overhead of `@Published` on every property change
- Allows typed environment injection without `EnvironmentValues` key-based lookup

### Decision

**`@Observable` (Swift Observation framework) throughout, with typed environment injection.**

```swift
// Controller definition:
@MainActor
@Observable
public final class LibraryController {
    public var sections: [CloudLibrarySection] = []
    // ...
}

// Injection at root:
WindowGroup {
    RootView(coordinator: appCoordinator)
        .environment(appCoordinator.libraryController)
}

// Consumption in views:
struct CloudLibraryHomeView: View {
    @Environment(LibraryController.self) private var libraryController
}
```

### Consequences

**Positive:**
- Only accessed properties trigger re-renders (fine-grained observation)
- `@MainActor` isolation is explicit and verifiable
- `@Bindable` provides two-way binding to `@Observable` types
- No `@Published` boilerplate on every property

**Negative / Trade-offs:**
- Requires iOS 17+ / tvOS 17+ (not a constraint for this project)
- `@Observable` types cannot be used as `@EnvironmentObject` — requires migration if existing code uses the older pattern

### Rejected Alternatives

**`ObservableObject` + `@Published`:** Triggers view re-renders on every `willSet`, not just on accessed properties. Requires `@EnvironmentObject` for injection which uses string-keyed lookup. Does not integrate cleanly with Swift 6.2 `@MainActor` isolation.

---

## ADR-006: CloudLibrary State Shaped Before Rendering

**Status:** Accepted
**Date:** 2026-02-26

### Context

`CloudLibraryShellHost` assembles state from `LibraryController`, `ProfileController`, `SettingsStore`, and multiple computed properties. Child screens (`CloudLibraryHomeView`, `CloudLibraryGridView`, `CloudLibraryDetailView`) are complex and deeply nested.

Two questions arose:
- Should child screens read from controllers directly via `@Environment`?
- Or should the shell host assemble pure value-typed state and pass it down?

### Decision

**`CloudLibraryShellHost` assembles typed state structs. Child screens receive pure value-typed parameters and emit typed callbacks.**

Child screens have zero `@Environment` reads. They are fully previewable with static fixtures:

```swift
// Fixture-based preview — no network, no actor state:
#Preview("Home") {
    CloudLibraryHomeView(
        stateSnapshot: CloudLibraryStateSnapshot.fixture,
        sceneModel: CloudLibrarySceneModel.fixture,
        loadState: .loaded,
        // ...
    )
}
```

### Consequences

**Positive:**
- Every screen has a working Xcode Preview with no network or actor state
- Logic changes in controllers do not require touching view files
- Focus tests can be written against pure struct inputs

**Negative / Trade-offs:**
- `CloudLibraryShellHost` / `CloudLibraryView` becomes larger as screens are added — it is the state assembly root
- Fixture structs must be kept in sync with real state; a missing field means an incomplete preview

### Rejected Alternatives

**Direct `@Environment` reads in child screens:** Makes screens impossible to preview with static data. Tightly couples view layout to controller internals.

---

## ADR-007: WebRTC Behind an App-Owned Protocol Abstraction

**Status:** Accepted
**Date:** 2026-02-25

### Context

`WebRTC.xcframework` is a vendored binary. Direct imports in package code would mean the packages require the framework to compile — preventing macOS unit tests and CI builds without the binary.

### Decision

**`WebRTCBridge` protocol in `StreamingCore` abstracts all WebRTC interactions.**

```swift
// Package protocol (no framework import):
public protocol WebRTCBridge: AnyObject, Sendable {
    func createOffer() async throws -> SessionDescription
    func setLocalDescription(_ sdp: SessionDescription) async throws
    func setRemoteDescription(_ sdp: SessionDescription) async throws
    func addIceCandidate(_ candidate: IceCandidate) async throws
    func send(channelKind: DataChannelKind, data: Data) async throws
    func close()
    var connectionState: RTCConnectionState { get }
    // ...
}
```

Two implementations:
- **`WebRTCClientImpl`** — the concrete implementation surface under `Apps/Stratix/Sources/Stratix/Integration/WebRTC/`; split across multiple `WebRTCClientImpl*` files and compiled only when `-DWEBRTC_AVAILABLE` is set
- **`MockWebRTCBridge`** — a no-op implementation used for UI development, unit tests, and explicit non-WebRTC or harness-friendly paths

### Consequences

**Positive:**
- All 7 packages compile and test on macOS without the WebRTC binary
- `MockWebRTCBridge` allows full UI iteration and Xcode Previews
- CI can validate package logic without needing the framework

**Negative / Trade-offs:**
- Protocol must be kept in sync with actual WebRTC API usage
- `WebRTCClientImpl` is the only file that can be trusted for real streaming behavior

### Rejected Alternatives

**Direct WebRTC imports in StreamingCore:** Makes the package depend on the vendored framework. All package tests require the binary. CI becomes heavier.

---

## ADR-008: Streaming Split by Responsibility

**Status:** Accepted
**Date:** 2026-02-25

### Context

The streaming feature touches many concerns: session provisioning, WebRTC signalling, video rendering, controller input, audio configuration, data channel protocol, and shell recovery. Keeping all of this in one place would create a monolithic feature with no clear boundaries.

### Decision

**Streaming responsibilities are split across packages and the app target by concern:**

| Concern | Owner |
|---------|-------|
| Stream launch and reconnect policy | `StratixCore` |
| Session lifecycle, SDP/ICE, data channels | `StreamingCore` |
| Controller input at 125 Hz | `InputBridge` |
| Render strategy resolution | `VideoRenderingKit` |
| Diagnostics and metrics | `DiagnosticsKit` |
| Concrete WebRTC bridge and renderer | App target (`Integration/WebRTC/`) |
| Stream views and overlay | App target (`Features/Streaming/`) |

Packages never import from the app. The app imports packages for protocols and contracts.

### Consequences

**Positive:**
- Each package can be tested independently
- Render strategy and session logic can evolve separately
- New streaming features go in the right package, not in the app target

**Negative / Trade-offs:**
- Adding a new streaming feature requires deciding where it belongs (good friction)
- Protocol additions in `StreamingCore` require updating `WebRTCClientImpl` in the app

### Rejected Alternatives

**Single streaming module in the app target:** No package-level test coverage. All streaming code is coupled to WebRTC binary availability.

---

## ADR-009: Device Spoofing for Resolution Control

**Status:** Accepted
**Date:** 2026-02-25

### Context

Microsoft's xCloud servers return different video quality tiers based on the client device identity. The server uses the `osName` value in the `x-ms-device-info` header to determine resolution:

| `osName` | Resolution tier |
|----------|-----------------|
| `android` | 720p |
| `windows` | 1080p |
| `tizen` | 1080p HQ (HDR) |

Without device spoofing, Apple TV would receive 720p streams (Android tier).

### Decision

**SDP offers include `User-Agent` and `x-ms-device-info` headers with Windows/Chrome values.** The default spoofing tier is `windows` (1080p).

This is applied in `SDPProcessor.processLocalSDP()` via the device-spoofing transform, which adds HTTP headers to the SDP before sending to the server.

### Consequences

**Positive:**
- Full 1080p streams on Apple TV without any server-side change
- `tizen` tier is available for 1080p HQ if HDR support is validated

**Negative / Trade-offs:**
- If Microsoft changes the tier table, the spoofing values need updating
- The approach depends on undocumented server behavior

### Rejected Alternatives

**No spoofing (Apple TV default identity):** Receives 720p tier from the server. Not acceptable for a TV-first streaming app.

---

## ADR-010: Adopt `com.stratix.appletv` Bundle IDs And Preserve Auth Compatibility

**Status:** Accepted
**Date:** 2026-04-07

### Context

The live repo now uses `Stratix` consistently for the app target, workspace schemes, test targets, and bundle identifiers:

- Main app: `com.stratix.appletv`
- Test targets: `com.stratix.appletv.*`

At the same time, older local developer installs and test devices may still contain Keychain entries written under the historical `greenlight.*` keys.

### Decision

**The project moves bundle identifiers fully to the `com.stratix.appletv` family, while `TokenStore` preserves backward compatibility by migrating legacy `greenlight.*` Keychain entries forward on read.**

This separates two concerns cleanly:

- bundle identifiers and entitlements reflect the current product name
- auth continuity for existing local installs is preserved without keeping stale bundle naming in the project file

### Consequences

**Positive:**
- The app project, entitlements, docs, and test targets now align on the current `Stratix` name.
- Public repo readers do not have to interpret a split naming story between code and bundle ids.
- Existing local auth state can still upgrade cleanly through `TokenStore`.

**Trade-offs:**
- Keychain migration logic must remain in place until old local installs are no longer a concern.
- Release and signing operations still need normal verification whenever bundle-id-facing infrastructure changes.

### Rejected Alternatives

**Keep legacy bundle identifiers indefinitely:** Avoids short-term signing coordination, but keeps the repo in a misleading half-renamed state and leaks obsolete product identity into contributor-facing tooling and docs.

**Rename bundle IDs without Keychain migration support:** Simplifies storage code, but forces unnecessary local sign-in churn for existing installs and makes auth upgrades less graceful.

---

## ADR-011: ZStack Overlay Model for Guide/Profile/Achievements

**Status:** Accepted
**Date:** 2026-02-26

### Context

The app has overlays that must appear over the content with:
- Blur on the background content (not possible if content is dismissed)
- Slide-from-leading-edge animation
- Full-screen dimming scrim
- Smooth 0.22s easeOut transition
- Content must remain in the hierarchy while the overlay is open

### Decision

**Overlays are rendered as `ZStack` layers with explicit `zIndex` values.** Only one overlay is visible at a time; others are conditionally included in the hierarchy via `if` statements.

Animation:
```swift
.transition(.move(edge: .leading).combined(with: .opacity))
.animation(.easeOut(duration: 0.22))
```

### Consequences

**Positive:**
- Full control over animation, blur, scrim, and dismissal
- Background content remains in the hierarchy (required for blur effect)
- All three overlays animate correctly on tvOS

**Negative / Trade-offs:**
- `ZStack` with `if` conditions can cause layout recalculation when overlays appear
- zIndex management requires care when adding new overlays

### Rejected Alternatives

**`.sheet` / `.fullScreenCover`:** tvOS sheet presentation does not support the slide-from-leading-edge animation. The blur effect requires the content to remain in the hierarchy; sheet presentation removes it.

**`NavigationStack` push:** Navigation push replaces content rather than layering over it. Cannot produce the blur-and-dim effect over the existing content.

---

## ADR-012: AppCoordinator in Extraction-Only Mode

**Status:** Accepted
**Date:** 2026-02-25

### Context

`AppCoordinator` was originally a large coordination hub that owned many responsibilities. As the codebase matured, those responsibilities were progressively extracted into dedicated controllers (`LibraryController`, `StreamController`, `ProfileController`, etc.).

`AppCoordinator` now exists primarily as the object that instantiates and wires controllers together during app boot.

### Decision

**`AppCoordinator` is in extraction-only mode.** New permanent responsibilities go into dedicated controllers, not into `AppCoordinator`.

- `AppCoordinator.init()` creates controllers and wires dependencies
- `AppCoordinator` delegates coordinator callbacks to the appropriate controller
- `AppCoordinator` does not own persistent state beyond what is needed for wiring

### Consequences

**Positive:**
- New features get clean ownership from the start (in a dedicated controller)
- `AppCoordinator` shrinks over time rather than growing
- Individual controllers are testable in isolation

**Negative / Trade-offs:**
- Some wiring logic in `AppCoordinator` must remain until controllers are fully independent
- New contributors may be tempted to add convenience methods to `AppCoordinator`

### Rejected Alternatives

**Keep adding to AppCoordinator:** The coordinator grows unbounded. All new features couple to a single large object that is difficult to test.

---

## Current Decision Rules

These rules apply to all new work:

- Prefer package placement when a type is shared or non-UI
- Prefer app-target placement when a type is SwiftUI composition, route ownership, or the concrete WebRTC/render bridge
- Prefer truthful names over extension-style shard names
- Prefer current-state docs in `Docs/` over anything in `Docs_to_update/`
- New permanent responsibilities go into dedicated controllers, not `AppCoordinator`
- New external library dependencies are not permitted (ADR-001); all functionality is implemented in-house or via Apple frameworks — the only permitted external dependencies are `WebRTC.xcframework` and `swift-async-algorithms`

---

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md) — top-level system shape and package graph
- [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md) — per-package ownership and key types
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md) — streaming runtime detail
- [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md) — WebRTC build pipeline
- [CONCURRENCY_EXCEPTIONS.md](CONCURRENCY_EXCEPTIONS.md) — three documented `@unchecked Sendable` exceptions
