# Stratix Architecture

This document describes how the Stratix codebase is put together — the package structure, the boot sequence, the concurrency model, and the streaming boundary. It is current-state documentation: what the code actually looks like today.

After reading this document, you should be able to answer:
- Where does a new HTTP client belong? (`XCloudAPI`)
- Why doesn't the UI reach directly into `StreamingCore`? (the boundary is the test surface)
- What happens between when you tap a game and when video appears on screen?
- What does `@MainActor` own and what lives off it?

If something here conflicts with what you see in the code, trust the code — and please fix the doc.

---

Stratix is a tvOS app that provides an Xbox cloud-gaming client for Apple TV. The repo is organized as one app target plus a small set of local Swift packages. The app owns SwiftUI composition, route and focus state, and the concrete WebRTC integration boundary. The packages own domain controllers, hydration, networking, diagnostics, input, stream runtime contracts, and rendering strategy selection.

## Workspace Shape

The workspace is rooted at `Stratix.xcworkspace` and is split into the app target, local packages, tools, and the vendored WebRTC binary:

```text
Stratix.xcworkspace
├── Apps/
│   └── Stratix/
├── Packages/
│   ├── StratixModels/
│   ├── DiagnosticsKit/
│   ├── InputBridge/
│   ├── XCloudAPI/
│   ├── StreamingCore/
│   ├── VideoRenderingKit/
│   └── StratixCore/
├── ThirdParty/
│   └── WebRTC/WebRTC.xcframework
└── Tools/
```

The dependency direction is intentionally one-way:

- the app depends on packages
- packages never depend on the app
- `StratixModels` stays at the bottom of the graph as the shared model and identifier layer
- `ThirdParty/WebRTC` is consumed only through the app-side integration boundary

The live app target and module name are `Stratix`. The current bundle identifier family is `com.stratix.appletv`. Legacy auth-storage compatibility is handled separately through token-key migration inside `TokenStore`; it is not an indicator that the app still uses the old product name.

## Package Ownership

The packages are deliberately narrow. They are not generic buckets for code that happened to be useful in more than one file.

| Package | What it owns | What it should not own |
|---------|--------------|------------------------|
| `StratixModels` | Shared value types, identifiers, enums, cross-package data shapes | controllers, networking, UI, persistence orchestration |
| `DiagnosticsKit` | Logging categories, performance metrics, telemetry helpers | app routing, SwiftUI views, Xbox clients |
| `InputBridge` | Gamepad input capture, queueing, packet shaping, input primitives | UI, shell focus, streaming overlays |
| `XCloudAPI` | Xbox and xCloud HTTP clients, auth services, token storage, response decoding | SwiftUI state, shell composition, renderers |
| `StreamingCore` | Streaming session façade, runtime contracts, SDP/ICE/channel processing, stream lifecycle | Metal, SwiftUI, app overlays |
| `VideoRenderingKit` | Rendering strategy and upscale-capability resolution | UIKit views, Metal attachment code, app routing |
| `StratixCore` | App lifecycle, controllers, hydration, shell boot, stream orchestration, settings | SwiftUI views, app-only layout concerns, concrete WebRTC view code |

That ownership boundary is more important than the immediate call site. New shared identifiers belong in `StratixModels`. New Xbox HTTP clients belong in `XCloudAPI`. New stream runtime contracts belong in `StreamingCore`. New lifecycle or hydration coordination belongs in `StratixCore`.

## High-Level Runtime Layers

At a high level, the repo is split into four runtime layers:

1. App composition  
   The SwiftUI app target mounts scenes, chooses the visible surface, owns shell-local state, and hosts the WebRTC boundary.
2. Domain controllers  
   `StratixCore` owns session, library, profile, console, stream, achievements, settings, and boot coordination.
3. Runtime services  
   `XCloudAPI`, `StreamingCore`, `InputBridge`, `VideoRenderingKit`, and `DiagnosticsKit` provide the lower-level building blocks those controllers use.
4. Binary integration  
   The vendored WebRTC xcframework is adapted through app-side integration code under `Apps/Stratix/Sources/Stratix/Integration/WebRTC`.

This split is why the repo does not use a single monolithic engine object. The app side decides how to present state. The packages decide how to fetch, transform, persist, and stream it.

## App Boot and Lifecycle

The live boot flow is coordinator-driven, but it is no longer accurate to describe startup as one `ShellBootstrapController.bootstrap()` call. Startup is spread across the app entry, root auth branching, a lifecycle coordinator, and a shell-boot coordinator.

The app entry point is [`StratixApp.swift`](../Apps/Stratix/Sources/Stratix/App/StratixApp.swift). `StratixApp` creates a single `AppCoordinator` and injects the long-lived controllers into the root scene using typed environment injection:

- `sessionController`
- `libraryController`
- `profileController`
- `consoleController`
- `streamController`
- `shellBootstrapController`
- `achievementsController`
- `inputController`
- `previewExportController`
- `settingsStore`

`StratixApp` also decides whether normal coordinator boot should run at all. Shell UI harness modes short-circuit the normal app-start flow so deterministic test harnesses can own startup sequencing.

The next layer is [`RootView.swift`](../Apps/Stratix/Sources/Stratix/App/RootView.swift). `RootView` reads `SessionController.authState` and selects one of four top-level surfaces:

- a startup progress view when auth state is still unknown
- `AuthView` when no valid session exists
- `DeviceCodeView` while device-code authentication is in progress
- `AuthenticatedShellView` once a full authenticated session is available

`RootView` also handles active-scene transitions and forwards them into the coordinator, again only outside the deterministic UI harness modes.

The coordinator layer is built in [`AppCoordinator.swift`](../Packages/StratixCore/Sources/StratixCore/App/AppCoordinator.swift). `AppCoordinator` is intentionally thin composition glue. It builds and holds the controller graph, attaches controller dependencies, and forwards lifecycle events into dedicated workflows:

- `onAppear()`
- `handleAppDidBecomeActive()`
- `performBackgroundAppRefresh()`
- `beginShellBootHydrationIfNeeded()`

Lifecycle work itself lives in [`AppLifecycleCoordinator.swift`](../Packages/StratixCore/Sources/StratixCore/App/Lifecycle/AppLifecycleCoordinator.swift). That coordinator owns the normal startup, foreground refresh, background refresh, and sign-out flows.

Shell hydration after a successful authenticated token apply is handled through [`AppShellBootCoordinator.swift`](../Packages/StratixCore/Sources/StratixCore/App/Shell/AppShellBootCoordinator.swift). That coordinator decides whether shell boot hydration should begin, whether disk caches should be restored first, and whether the shell is currently suspended for stream-priority mode.

The current boot flow is therefore better described like this:

```text
StratixApp
  └── AppCoordinator
        ├── inject controllers into RootView
        └── onAppear() -> AppLifecycleCoordinator

RootView
  ├── chooses auth / device-code / authenticated shell
  └── forwards scene active events to AppCoordinator

SessionController full auth success
  └── AppCoordinator.handleSessionDidAuthenticateFromController(...)
        └── AppShellBootCoordinator.beginShellBootHydrationIfNeeded(...)
              ├── optionally restore disk caches
              ├── build shell hydration plan
              └── trigger library refresh and prefetch
```

## Authenticated Shell

The authenticated app surface begins in [`AuthenticatedShellView.swift`](../Apps/Stratix/Sources/Stratix/Shell/AuthenticatedShellView.swift). That view is intentionally small. It does three jobs:

- mounts `CloudLibraryView` as the primary authenticated experience
- applies shell-wide accessibility adaptations derived from `SettingsStore`
- publishes hidden readiness markers used by shell UI tests

Those shell-wide accessibility adaptations include large-text clamping and animation suppression when reduce-motion is enabled.

Although the repo still has distinct auth, guide, and stream surfaces, the authenticated shell is no longer a deep tab-based architecture doc of its own. The main authenticated experience is the CloudLibrary shell.

## CloudLibrary Is the Main App Surface

The largest app feature slice is `Features/CloudLibrary`. The true entry point is [`CloudLibraryView.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryView.swift), not a cluster of standalone home or grid roots.

`CloudLibraryView` owns the app-side state graph for the authenticated shell:

- `CloudLibraryViewModel`
- `CloudLibrarySceneModel`
- `CloudLibraryRouteState`
- `CloudLibraryFocusState`
- `CloudLibraryPresentationStore`
- `LibraryQueryState`
- `activeStreamContext`

It also reads snapshots from package-owned controllers:

- `LibraryController`
- `SessionController`
- `ProfileController`
- `ConsoleController`
- `StreamController`
- `AchievementsController`
- `PreviewExportController`
- `SettingsStore`

That split is important. Controller state stays in `StratixCore`. App-owned route, focus, scene, and presentation shaping stays in the app target.

`CloudLibraryView` mounts [`CloudLibraryShellHost.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Shell/CloudLibraryShellHost.swift), which is the main composition root for the shell. `CloudLibraryShellHost` owns:

- shell composition
- side-rail routing
- route action bundles for browse, utility, and detail paths
- deferred async shell work through a queued pending-action model
- shell-level presentation rebuild tasks

`CloudLibraryShellHost` does not directly render every screen inline. Instead it routes through a layered host structure:

```text
CloudLibraryView
  └── CloudLibraryShellHost
        └── CloudLibraryShellView
              └── CloudLibraryContentRouteHost
                    ├── CloudLibraryBrowseRouteHost
                    │     ├── CloudLibraryHomeScreen
                    │     ├── CloudLibraryLibraryScreen
                    │     ├── CloudLibrarySearchScreen
                    │     └── CloudLibraryConsolesView
                    ├── CloudLibraryProfileView
                    ├── CloudLibrarySettingsView
                    └── NavigationStack -> CloudLibraryDetailHydrationView
                                             └── CloudLibraryTitleDetailScreen
```

That layered routing model is the current shape of the app. Older documentation that still centers outdated `CloudLibrary*View` roots as the active screen graph is stale.

## Presentation and Data Shaping

The CloudLibrary shell is designed so route hosts read already-shaped view state instead of rebuilding everything directly from controllers.

Three pieces matter:

1. Pure library data shaping in `Apps/Stratix/Sources/Stratix/Data/CloudLibrary`  
   These transforms are side-effect-free and testable without mocks.
2. Presentation caching in [`CloudLibraryPresentationStore.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryPresentationStore.swift)  
   This caches shell, browse, and utility presentation projections so route hosts consume stable view-state objects.
3. Scene mutation in [`CloudLibrarySceneModel.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneModel.swift)  
   This stores derived status, route, and hero-background state that is rebuilt from route, load, and focus inputs.

The result is a clear split:

- controllers own data lifecycle and persistence
- view models and builders shape data into shell-facing projections
- route hosts render those projections

## Streaming Boundary

Streaming is intentionally split across the app target and several packages.

The app target owns the visible streaming surface:

- `StreamView`
- `StreamControllerInputHost`
- `RenderSurfaceCoordinator`
- `RendererAttachmentCoordinator`
- WebRTC UIKit and Metal attachment code
- the concrete WebRTC bridge under `Integration/WebRTC`

The packages own the non-UI runtime:

- `StreamingCore` for streaming session state, runtime contracts, lifecycle, SDP, ICE, and channels
- `XCloudAPI` for stream session creation and Xbox service communication
- `StratixCore` for stream orchestration policy and controller ownership
- `DiagnosticsKit` for runtime metrics
- `InputBridge` for controller packet generation
- `VideoRenderingKit` for rendering strategy resolution

The main entry on the app side is [`StreamView.swift`](../Apps/Stratix/Sources/Stratix/Features/Streaming/StreamView.swift). `CloudLibraryView` presents it through a full-screen cover once a launch succeeds, wrapped in `StreamControllerInputHost` so controller-input interception remains stream-local instead of leaking back into the shell root.

That means the streaming boundary is not “SwiftUI on top of WebRTC” in one file. It is a layered runtime:

```text
CloudLibraryView
  └── StreamControllerInputHost
        └── StreamView
              ├── stream overlay and exit behavior
              ├── renderer coordination
              └── WebRTCVideoSurfaceView

Packages
  ├── StratixCore owns stream controller and orchestration
  ├── StreamingCore owns runtime and session contracts
  ├── XCloudAPI owns stream-session API work
  ├── InputBridge owns controller packets
  └── VideoRenderingKit owns capability strategy
```

For runtime and WebRTC-specific detail, see [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md), [RUNTIME_FLOW.md](RUNTIME_FLOW.md), and [WEBRTC_GUIDE.md](WEBRTC_GUIDE.md).

## Persistence

Persistent library hydration state lives in `StratixCore`.

The important split is:

- unified library, home merchandising, and discovery snapshot in `SwiftDataLibraryRepository`
- product details persisted separately through `LibraryHydrationPersistenceStore`
- runtime settings in `SettingsStore` via `UserDefaults`
- authentication tokens in `TokenStore` via Keychain

This keeps the startup restore path optimized for shell interactivity while preserving larger cache data separately.

For the full hydration story, see [HYDRATION.md](HYDRATION.md).

## Validation Surface

The shared workspace exposes these main validation lanes:

| Scheme | Purpose |
|--------|---------|
| `Stratix-Debug` | day-to-day development build |
| `Stratix-ShellUI` | shell UI validation harness |
| `Stratix-Packages` | package-level test lane |
| `Stratix-Validation` | broad validation sweep |
| `Stratix-Perf` | performance test lane |
| `Stratix-Profile` | profiling build |
| `Stratix-MetalProfile` | GPU/Metal profiling |
| `Stratix-ReleaseRun` | local release-configuration run |

See [TESTING.md](TESTING.md) and [XCODE_VALIDATION_MATRIX.md](XCODE_VALIDATION_MATRIX.md) for the exact workflows and when to use each lane.

## Observation and Concurrency Model

Stratix uses modern observation and strict concurrency as architectural rules, not as incidental implementation details.

Observation rules:

- `StratixApp` owns the root `AppCoordinator` with `@State`
- long-lived controllers are injected by concrete type with `.environment(...)`
- consuming views read them with `@Environment(Type.self)`
- app-owned shell state uses `@Observable` types such as `CloudLibraryRouteState`, `CloudLibraryFocusState`, `CloudLibraryPresentationStore`, and `CloudLibrarySceneModel`

Concurrency rules:

- UI-facing shell and controller state is `@MainActor`
- shared mutable service state that crosses tasks belongs in actors or isolated runtime types
- rendering and heavy runtime work remain off the main actor
- WebRTC-specific escape hatches are contained to the app-side integration boundary and must remain documented

This is why the repo does not model everything as one global main-actor object. UI state is main-actor owned. Streaming runtime, persistence, and lower-level processing stay outside that boundary and publish results back through narrow seams.

## Where New Code Should Go

When adding code, follow ownership instead of convenience:

- new shell composition, route hosts, or SwiftUI state helpers belong in `Apps/Stratix`
- new Xbox service clients belong in `Packages/XCloudAPI`
- new stream runtime contracts or session lifecycle helpers belong in `Packages/StreamingCore`
- new hydration, lifecycle, or controller orchestration belongs in `Packages/StratixCore`
- new shared identifiers or cross-package model types belong in `Packages/StratixModels`
- new diagnostics primitives belong in `Packages/DiagnosticsKit`

If a change only feels shared because two app files want it, that does not automatically make it package-worthy. Keep the boundary honest.

## Related Docs

- [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md) — per-package ownership detail and the decision guide for where new code goes
- [`UI_ARCHITECTURE.md`](UI_ARCHITECTURE.md) — SwiftUI shell, CloudLibrary composition, route ownership, and focus state layering
- [`OBSERVATION.md`](OBSERVATION.md) — `@Observable` state, typed environment injection, and snapshot-based reads
- [`HYDRATION.md`](HYDRATION.md) — how library data is restored, refreshed, cached, and persisted
- [`STREAMING_ARCHITECTURE.md`](STREAMING_ARCHITECTURE.md) — streaming stack from user tap to video frame
- [`RUNTIME_FLOW.md`](RUNTIME_FLOW.md) — end-to-end flows traced across package boundaries
- [`WEBRTC_GUIDE.md`](WEBRTC_GUIDE.md) — the custom WebRTC build and its integration boundary
- [`DESIGN_DECISIONS.md`](DESIGN_DECISIONS.md) — why major architectural choices were made (ADR format)
- [`TESTING.md`](TESTING.md) — validation lanes and what each one proves
- [`GLOSSARY.md`](GLOSSARY.md) — definitions for terms like xCloud, xHome, ICE, SDP, and xctestplan
