# Package Guide

This document explains the seven local Swift packages under `Packages/` — what each one owns, what it depends on, and where new code belongs. It is a practical reference for the question every contributor eventually asks: "where does this code go?"

If you are new to the repo, read [`ARCHITECTURE.md`](ARCHITECTURE.md) first for the overall picture. This doc digs deeper into each package.

---

## Why The Repo Uses Packages

The package split is not there for file organization. It exists to make each layer independently testable.

Here is a concrete example: if `XCloudAPI` leaked into `StratixCore` as concrete types instead of protocols, every test for lifecycle behavior would need live auth — a real Microsoft account, a real network connection, a real token. As it stands, you can test the entire controller layer on macOS without a network connection, because `XCloudAPI` is a separate package with a clean protocol seam.

The same principle holds throughout the graph:
- Streaming runtime compiles and tests without UIKit or Metal because `StreamingCore` has no UI dependencies
- Controller input encodes and decodes correctly on macOS because `InputBridge` depends only on `StratixModels`
- Shared data shapes flow across the entire system because `StratixModels` has no local dependencies at all

**The boundary is the test surface, not just a style preference.** When code crosses into the wrong layer, the test that was proving it independently can no longer run.

The app target stays focused on SwiftUI composition, routing, and the concrete WebRTC integration. Everything that can be separated into a package, is.

## Package Graph

The live package graph is:

```text
                    StratixModels
                         │
      ┌──────────────────┼──────────────────┐
      │                  │                  │
DiagnosticsKit       InputBridge         XCloudAPI
      │                  │                  │
      └──────────────────┼──────────────────┘
                         │
                    StreamingCore
                         │
         ┌───────────────┼───────────────┐
         │               │               │
VideoRenderingKit        │          StratixCore
         └───────────────┴───────────────┘
                         │
                     Apps/Stratix
```

The direct manifest dependencies in the live repo are:

| Package | Direct dependencies |
|---------|---------------------|
| `StratixModels` | none |
| `DiagnosticsKit` | `StratixModels`, `swift-async-algorithms` |
| `InputBridge` | `StratixModels` |
| `XCloudAPI` | `StratixModels`, `DiagnosticsKit` |
| `StreamingCore` | `DiagnosticsKit`, `StratixModels`, `InputBridge`, `XCloudAPI` |
| `VideoRenderingKit` | none |
| `StratixCore` | `StratixModels`, `XCloudAPI`, `StreamingCore`, `DiagnosticsKit`, `InputBridge`, `VideoRenderingKit` |

Two architectural rules matter more than the picture:

- packages never depend on the app target
- `StratixModels` stays at the bottom of the graph as the shared leaf package

## Platforms And Test Targets

The packages are all built with Swift tools version `6.2`, but they do not all target the same platforms.

| Package | Platforms | Test target |
|---------|-----------|-------------|
| `StratixModels` | macOS 14, tvOS 26, iOS 17 | `StratixModelsTests` |
| `DiagnosticsKit` | macOS 14, tvOS 26, iOS 17 | `DiagnosticsKitTests` |
| `InputBridge` | macOS 14, tvOS 26, iOS 17 | `InputBridgeTests` |
| `XCloudAPI` | macOS 14, tvOS 26, iOS 17 | `XCloudAPITests` |
| `StreamingCore` | macOS 14, tvOS 26, iOS 17 | `StreamingCoreTests` |
| `VideoRenderingKit` | tvOS 26, macOS 14 | `VideoRenderingKitTests` |
| `StratixCore` | macOS 14, tvOS 26, iOS 17 | `StratixCoreTests` |

`VideoRenderingKit` is the narrowest package because it is about render-strategy selection, not broad app logic or protocol surfaces.

## Cross-Package Rules

Before looking at each package individually, these cross-cutting rules explain most of the design:

1. `StratixModels` is the only shared leaf package.  
   If multiple packages need a common identifier or value type, put it there rather than inventing mirrored structs in two places.
2. `XCloudAPI` owns HTTP clients and auth storage.  
   If the code talks directly to Xbox or xCloud services, it does not belong in `StratixCore` or the app target.
3. `StreamingCore` owns the runtime contract layer.  
   It can define the session façade, channels, lifecycle, bridge protocols, and runtime sequencing, but it should not own app-specific render views.
4. `StratixCore` owns controllers and workflows.  
   If the code coordinates auth, hydration, shell boot, lifecycle, or stream orchestration across multiple lower layers, it belongs there.
5. The app target owns SwiftUI composition.  
   Packages should not take on side-rail layout, route hosts, shell presentation caches, or other app-shell details.

## `StratixModels`

`StratixModels` is the leaf package and the shared vocabulary of the repo. It has no local package dependencies and should remain easy for every other package to import.

It primarily owns:

- typed identifiers such as `TitleID`, `ProductID`, and `ConsoleID`
- library and catalog value types such as `CloudLibraryItem`, `CloudLibrarySection`, and `CloudLibraryProductDetail`
- streaming configuration and lifecycle types such as `StreamingConfig`, `StreamPreferences`, and `StreamLifecycleState`
- stats, protocol, and WebRTC-adjacent data shapes such as `SessionDescription`, `IceCandidatePayload`, and `StreamingStatsSnapshot`
- controller input models such as `GamepadButtons`, `GamepadInputFrame`, and `ControllerSettings`

This package should not grow controller logic, network clients, shell state, or persistence seams. If a type crosses package boundaries but still feels too behavioral for `StratixModels`, that is usually a sign it belongs in a higher-level package instead.

Use `StratixModels` when:

- a value type is used by two or more packages
- a typed ID prevents mixing unrelated raw strings
- a protocol payload or runtime snapshot must stay UI-free

Do not use `StratixModels` as a dumping ground for generic helpers. It is a shared model package, not a utilities package.

## `DiagnosticsKit`

`DiagnosticsKit` is the shared home for repo-wide logging and streaming/performance telemetry. It depends on `StratixModels` and the external `swift-async-algorithms` package.

The most visible public seam is [`Logger.swift`](../Packages/DiagnosticsKit/Sources/DiagnosticsKit/Logger.swift), which defines:

- `LogCategory`
- `AppLogConfiguration`
- `LoggerStore`
- `GLogger`

`GLogger` wraps `os.Logger` with the repo’s shared categories:

- auth
- api
- streaming
- webrtc
- input
- video
- audio
- ui

The package also owns metrics and performance surfaces such as:

- stream-metrics recording and export
- performance trackers
- timing and milestone utilities

`DiagnosticsKit` is the right home for:

- shared logging categories
- telemetry primitives
- metrics-pipeline utilities
- reusable performance trackers

It is not the right home for:

- business rules about when to refresh or reconnect
- UI overlays or HUD views
- network clients
- controller-state façades

If a diagnostic type needs to know about app routing or SwiftUI, it has likely crossed the boundary and belongs elsewhere.

## `InputBridge`

`InputBridge` owns controller input capture, queueing, and packet shaping. It depends only on `StratixModels`.

The core types in the live package are:

- `GamepadHandler`
- `InputQueue`
- `InputPacket`

`GamepadHandler` reads physical controller state and normalizes it into `GamepadInputFrame`. `InputQueue` coalesces the latest input state. `InputPacket` encodes and decodes the binary wire format sent over the input channel.

This package is deliberately UI-free. It should not know about shell focus, SwiftUI overlays, or the authenticated shell. It also should not own app-specific controller observation policy; the higher-level controller graph decides when to observe controllers and when to forward those inputs into the runtime.

`InputBridge` is the right home for:

- packet-format logic
- gamepad frame normalization
- queueing and coalescing
- haptics packet parsing

It is not the right home for:

- stream overlay shortcuts
- sign-in or shell navigation behavior
- Game Pass route selection
- WebRTC data-channel ownership

For the full wire-format story, see [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md).

## `XCloudAPI`

`XCloudAPI` owns the HTTP client layer for Xbox and xCloud services. It depends on `StratixModels` and `DiagnosticsKit`.

The primary entry point is [`XCloudAPIClient.swift`](../Packages/XCloudAPI/Sources/XCloudAPI/XCloudAPIClient.swift). That client handles:

- cloud-title library requests
- MRU library requests
- console discovery for home streaming
- stream-session setup inputs
- region and host-sensitive API requests

Other important package surfaces include:

- `MicrosoftAuthService`
- `TokenStore`
- `GamePassCatalogClient`
- `GamePassSiglClient`
- `XboxWebProfileClient`
- `XboxWebPresenceClient`
- `XboxSocialPeopleClient`
- `XboxComProductDetailsClient`

This package owns the token chain, service hosts, request and response decoding, and transport-layer error handling. It is also where compatibility logic for older auth-key names lives: `TokenStore` now writes `stratix.*` keys and migrates older `greenlight.*` entries forward on read.

`XCloudAPI` is the right home for:

- auth service clients
- keychain token persistence
- xCloud library and session endpoints
- Xbox social, profile, and presence clients
- response-decoding helpers and API error types

It is not the right home for:

- app shell route decisions
- streaming runtime state machines
- SwiftUI presentation state
- render-surface code

If a type needs to call an HTTPS endpoint directly, `XCloudAPI` is the first package to consider.

## `StreamingCore`

`StreamingCore` is the runtime contract and session package. It depends on `DiagnosticsKit`, `StratixModels`, `InputBridge`, and `XCloudAPI`.

The package does not own UIKit, SwiftUI, or Metal rendering code. Instead it owns the runtime abstractions that the app-side integration layer plugs into.

Important live seams include:

- [`StreamingSession.swift`](../Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSession.swift)
- `StreamingSessionModel`
- `StreamingRuntime`
- `StreamingSessionRuntime`
- `WebRTCBridge`
- the data-channel types such as `ControlChannel` and `InputChannel`
- SDP and ICE processing utilities

`StreamingSession` is the app-facing observable façade. Underneath it, lower-level runtime types own the protocol and session sequencing. The package is where the runtime decides how to connect, exchange signaling data, process channel traffic, and report lifecycle changes.

`StreamingCore` is the right home for:

- session façades and runtime models
- bridge protocols that abstract the concrete WebRTC implementation
- channel framing and lifecycle handling
- SDP and ICE processing
- runtime stats and disconnect-intent behavior

It is not the right home for:

- concrete WebRTC UIKit adapters
- Metal renderer attachment
- shell overlay views
- route or focus state

That split is what lets the package compile and test independently of the app’s concrete WebRTC integration boundary.

## `VideoRenderingKit`

`VideoRenderingKit` is the smallest package. It currently has no local package dependencies and targets tvOS 26 plus macOS 14.

Its purpose is narrow: render-strategy resolution and upscale capability logic. In practice, this includes surfaces such as:

- `RenderLadderPlanner`
- `UpscaleCapabilityResolver`

This package is the right place for:

- deciding what render strategy is appropriate for a device or runtime context
- mapping capabilities into render-planning outputs
- isolating rendering-strategy logic away from SwiftUI and controller orchestration

It is not the right place for:

- actual Metal view ownership
- UIKit adapter views
- stream overlay logic
- app-shell settings UI

The app target still owns the concrete render-surface attachment layer. `VideoRenderingKit` helps decide what should happen, not how the view tree should be built.

## `StratixCore`

`StratixCore` is the highest-level package. It depends on every other local package except the app target, and it owns the controller and workflow layer that ties the runtime together.

Important live surfaces include:

- `AppCoordinator`
- `SessionController`
- `LibraryController`
- `ProfileController`
- `ConsoleController`
- `StreamController`
- `ShellBootstrapController`
- `AchievementsController`
- `InputController`
- `PreviewExportController`
- `SettingsStore`

It also owns the major coordination and workflow subsystems:

- app lifecycle coordination
- shell boot coordination
- hydration planning and orchestration
- stream launch and reconnect workflows
- artwork prefetch and post-load warmup
- console, profile, and achievement controller services

`StratixCore` is the right home for:

- long-lived controller façades consumed by the app target
- orchestration across auth, library, streaming, profile, and shell boot
- persistence and hydration coordination
- settings storage and shell-facing policy
- workflow-level business logic

It is not the right home for:

- SwiftUI route hosts
- side-rail layout and presentation projection builders
- concrete HTTP clients
- concrete WebRTC UIKit integration

If a feature needs to coordinate multiple packages and publish app-facing controller state, `StratixCore` is usually the right place.

## Choosing Where New Code Goes

When you need to add new code, follow ownership rather than convenience.

Use this decision guide:

- If it is a shared identifier or immutable value shape used across packages, put it in `StratixModels`.
- If it logs or records metrics across package boundaries, put it in `DiagnosticsKit`.
- If it reads or encodes controller input, put it in `InputBridge`.
- If it calls Xbox or xCloud endpoints, put it in `XCloudAPI`.
- If it manages stream-session runtime or channel behavior, put it in `StreamingCore`.
- If it chooses a rendering strategy but does not own a view, put it in `VideoRenderingKit`.
- If it coordinates lifecycle, hydration, controllers, or stream orchestration, put it in `StratixCore`.
- If it is specifically about SwiftUI shell composition or app presentation, keep it in `Apps/Stratix`.

The most common mistakes are:

- putting app-shell presentation logic in `StratixCore`
- putting HTTP clients in `StratixCore` instead of `XCloudAPI`
- putting runtime sequencing in the app target instead of `StreamingCore`
- putting shared identifiers in higher packages instead of `StratixModels`

## Adding Or Changing A Package

If you need to change package structure, keep these constraints in mind:

- do not introduce app-target dependencies into packages
- do not add a new package just to make one feature feel tidier
- do not move SwiftUI views into packages unless the package is explicitly intended to own UI, which the current local packages are not
- keep manifests honest about platform support

For most work in this repo, changing the boundary between existing packages is riskier than adding a new type inside the correct existing owner.

## Validation

Package-level work should normally be validated through:

- `swift test --package-path Packages/<PackageName>`
- the shared workspace package scheme `Stratix-Packages` when the change spans multiple packages
- the app build when package APIs are consumed directly by the app target

The app workspace remains the integration point. Even when a package test passes, a package boundary change is not really validated until the workspace builds cleanly.

## Related Docs

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — high-level runtime layers, boot sequence, and concurrency model
- [`HYDRATION.md`](HYDRATION.md) — how library data is persisted and restored (owned by `StratixCore`)
- [`STREAMING_ARCHITECTURE.md`](STREAMING_ARCHITECTURE.md) — how the streaming stack uses `StreamingCore`, `InputBridge`, and `VideoRenderingKit`
- [`RUNTIME_FLOW.md`](RUNTIME_FLOW.md) — end-to-end flows traced across these package boundaries
- [`CONTROLLER_INPUT.md`](CONTROLLER_INPUT.md) — the wire format and input pipeline owned by `InputBridge`
- [`WEBRTC_GUIDE.md`](WEBRTC_GUIDE.md) — the WebRTC integration boundary and why `StreamingCore` owns the protocol, not the framework
- [`TESTING.md`](TESTING.md) — how to validate package changes
