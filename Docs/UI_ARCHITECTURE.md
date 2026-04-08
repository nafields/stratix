# UI Architecture

This document explains how the Stratix app is put together from a SwiftUI perspective — how the authenticated shell is composed, where state is owned, how routing works, and why the streaming surface is intentionally separate from the rest of the shell.

**The key mental model:** The app has one main surface — the CloudLibrary shell — and one intentionally separate streaming surface. The CloudLibrary shell owns its own state graph (routes, focus, presentation cache, scene model). The streaming surface launches over it as a full-screen cover and has its own dedicated state. They do not share a visual layer because doing so would couple streaming lifecycle to shell rendering in ways that cause subtle bugs.

Controllers live in packages (`StratixCore`). App-owned state lives in the app target. Views render shaped projections of that state, not raw controller data. This separation is what allows package tests to prove controller logic without ever touching SwiftUI.

See [`OBSERVATION.md`](OBSERVATION.md) for how `@Observable` state flows through the app, and [`ARCHITECTURE.md`](ARCHITECTURE.md) for where UI code fits in the broader package structure.

---

This document explains the live SwiftUI architecture of the `Stratix` app target: how the authenticated shell is composed, where app-side state is owned, how CloudLibrary routing works, and where the streaming surface intentionally splits away from the shell.

## Core UI Principles

The current app UI is organized around four rules:

1. Controller state stays in packages.  
   `StratixCore` controllers own loading, lifecycle, persistence triggers, and external side effects.
2. App-owned shell state stays in the app target.  
   Route, focus, scene, and presentation state for the authenticated shell live in app-side `@Observable` types.
3. Route hosts render shaped projections, not raw controller state.  
   The shell rebuilds presentation caches and scene state before leaf views render.
4. The streaming surface is a separate full-screen boundary.  
   It is launched from the shell, but it does not share the shell’s visual layout tree.

## Root UI Entry

The UI entry starts in [`StratixApp.swift`](../Apps/Stratix/Sources/Stratix/App/StratixApp.swift). `StratixApp` creates the single `AppCoordinator`, injects the long-lived controllers into the environment, and kicks off coordinator boot only when the app is not running in a specialized UI harness mode.

That root scene mounts [`RootView.swift`](../Apps/Stratix/Sources/Stratix/App/RootView.swift). `RootView` is the app’s top-level auth and harness switch:

- `CloudLibraryUITestHarnessView` when the Game Pass home harness flag is active
- `ShellUITestHarnessView` when the shell harness flag is active
- the real auth-driven flow otherwise

Within the real flow, `RootView` switches on `SessionController.authState`:

- `.unknown` -> startup `ProgressView`
- `.unauthenticated` -> `AuthView`
- `.authenticating(info)` -> `DeviceCodeView`
- `.authenticated` -> `AuthenticatedShellView`

This keeps auth branching out of the authenticated shell itself. Once `AuthenticatedShellView` is visible, the shell can assume a live authenticated session.

## Authenticated Shell

[`AuthenticatedShellView.swift`](../Apps/Stratix/Sources/Stratix/Shell/AuthenticatedShellView.swift) is the outer authenticated container. It is intentionally thin and owns only shell-local concerns:

- it mounts `CloudLibraryView`
- it applies accessibility-derived shell adjustments such as reduce-motion transaction suppression and large-text clamping
- it publishes hidden accessibility markers for shell readiness and stream-exit completion used by UI tests

The authenticated shell is therefore not a tab manager or a deep navigator in its own right. It is the boundary that prepares the main CloudLibrary surface and exposes enough state for test harnesses to know when the shell is ready.

## Main Shell Composition

The main authenticated UI hierarchy is:

```text
StratixApp
  └── RootView
        └── AuthenticatedShellView
              └── CloudLibraryView
                    └── CloudLibraryShellHost
                          └── CloudLibraryShellView
                                └── CloudLibraryContentRouteHost
                                      ├── CloudLibraryBrowseRouteHost
                                      ├── CloudLibraryProfileView
                                      ├── CloudLibrarySettingsView
                                      └── NavigationStack -> CloudLibraryDetailHydrationView
```

Two details matter here:

- `CloudLibraryView` is the true app-side shell root
- `CloudLibraryShellHost` is the composition root for routed shell content, not a bag of leaf screens

Older documentation that still centers outdated `CloudLibrary*View` roots as the current routed surfaces is describing an old shell shape.

## CloudLibraryView: App-Side State Owner

[`CloudLibraryView.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryView.swift) owns the app-side state graph for the authenticated shell. It reads controller snapshots from package-owned controllers and combines them with app-owned state objects.

The app-owned state set is:

- `CloudLibraryViewModel`
- `CloudLibrarySceneModel`
- `CloudLibraryRouteState`
- `CloudLibraryFocusState`
- `CloudLibraryPresentationStore`
- `LibraryQueryState`
- `activeStreamContext`

The controller-facing inputs come from the environment:

- `LibraryController`
- `SessionController`
- `AchievementsController`
- `ConsoleController`
- `ProfileController`
- `StreamController`
- `PreviewExportController`
- `SettingsStore`

`CloudLibraryView` is responsible for:

- capturing controller state as app-side snapshots
- building a shell-facing `CloudLibraryLoadState`
- wiring refresh, detail-load, achievements-load, sign-out, and stream-launch closures into the shell host
- rebuilding scene and presentation state with `.task(id:)` driven mutations
- presenting the full-screen stream surface when a stream launch succeeds

This makes `CloudLibraryView` the bridge between controller-owned state and routed SwiftUI shell composition.

## Shell Host Layering

[`CloudLibraryShellHost.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Shell/CloudLibraryShellHost.swift) owns the routed shell behavior. It takes the app-owned state objects and pre-shaped closures from `CloudLibraryView`, then turns them into browse, utility, and detail action bundles.

`CloudLibraryShellHost` owns:

- `CloudLibraryRouteState`
- `CloudLibraryFocusState`
- `CloudLibraryPresentationStore`
- shell layout policy
- back-action policy
- shell interaction coordination
- a queued `pendingAsyncActions` model for deferred async work

The host renders [`CloudLibraryShellView.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Shell/CloudLibraryShellView.swift), which is the visual container for:

- the side rail
- the current content surface
- remote-command handlers for back and settings shortcuts

`CloudLibraryShellView` is intentionally not a state owner. It receives already-computed inputs from the host.

## Routed Content Model

[`CloudLibraryContentRouteHost.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryContentRouteHost.swift) is the switch point between browse, utility, and detail content.

It routes to:

- browse surfaces through `CloudLibraryBrowseRouteHost`
- utility overlays through `CloudLibraryProfileView` and `CloudLibrarySettingsView`
- detail navigation through a `NavigationStack` that pushes `CloudLibraryDetailHydrationView`

That detail path eventually resolves into `CloudLibraryTitleDetailScreen` once the necessary data is ready.

The browse host in [`CloudLibraryBrowseRouteHost.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryBrowseRouteHost.swift) is the current browse switchboard. It renders:

- `CloudLibraryHomeScreen`
- `CloudLibraryLibraryScreen`
- `CloudLibrarySearchScreen`
- `CloudLibraryConsolesView`

It also applies load-state gating before library and search content render, so those screens do not need to duplicate the shell-wide loading and cached-data logic.

## State Ownership Model

The live CloudLibrary UI uses several distinct state owners with different responsibilities.

### Route State

[`CloudLibraryRouteState.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryRouteState.swift) owns the facts about where the shell is:

- active browse route
- active utility route, if any
- detail navigation stack
- remembered-route restoration status and diagnostics

It is the source of truth for browse-versus-utility-versus-detail routing.

### Focus State

[`CloudLibraryFocusState.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryFocusState.swift) stores shell-owned focus facts that survive route rebuilds:

- last focused tile IDs per browse route
- settled hero tile IDs for home and library
- whether the side rail is expanded
- whether the shell still owes an initial content-focus handoff

The current focus model is deliberately hybrid:

- the shell stores stable focus facts and focus-entry requests
- the concrete focus target still lives in leaf screens and SwiftUI focus primitives
- shell-facing helper methods such as `requestTopContentFocus` and `requestUtilityFocus` preserve the shell contract even when the leaf surface owns the concrete move

That is the live design. It is not accurate to describe the shell as purely token-driven anymore, and it is not accurate to pretend the shell directly controls every concrete focus transition either.

### Presentation Store

[`CloudLibraryPresentationStore.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryPresentationStore.swift) caches shaped projections for:

- shell chrome
- side-rail state
- shell presentation
- utility-route presentation
- browse-route presentation

Route hosts consume these projections instead of rebuilding them from raw controller state on every render.

### Scene Model

[`CloudLibrarySceneModel.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneModel.swift) owns scene-level derived state:

- status state
- route projection state
- hero-background state
- mutation bookkeeping

This is where the shell records derived facts like current surface identity and hero-background resolution, separate from the raw controller snapshots and separate from the user-facing route state.

## Presentation Rebuild Flow

The current shell does not rebuild everything inline in body builders. Instead it uses explicit task-driven mutation boundaries.

At a high level:

1. `CloudLibraryView` captures controller state as snapshots.
2. It derives shell-facing load state and other shaping inputs.
3. `CloudLibraryShellHost` schedules presentation rebuild work with stable task IDs.
4. `CloudLibraryPresentationStore` rebuilds shell, utility, and browse projections.
5. `CloudLibrarySceneModel` rebuilds route, status, and hero-background derived state.
6. Route hosts render the resulting projections.

This is why the shell can stay largely deterministic even though the underlying controllers are doing async work. The UI layer consumes shaped values instead of poking controller state directly from every leaf.

## Shell-Local UI State

The authenticated shell no longer owns a dedicated transient feedback center. Shell-local UI state instead lives in app-owned models created inside `CloudLibraryView` and passed into the routed shell surfaces that actually need them.

This is intentionally narrower than making those view-state models global app controllers. They are UI-local state, not domain controllers.

Other shell-local UI state lives in app-owned models rather than package controllers:

- selected search query
- side-rail expansion
- preferred focused tiles
- detail navigation stack
- presentation caches
- hero-background state

## Streaming UI Boundary

The stream surface is launched from the shell but is not rendered inside the shell layout hierarchy.

`CloudLibraryView` presents a full-screen cover when `activeStreamContext` becomes non-nil. That full-screen cover wraps `StreamView` in `StreamControllerInputHost`, keeping stream-specific controller-input handling local to the stream surface.

Inside [`StreamView.swift`](../Apps/Stratix/Sources/Stratix/Features/Streaming/StreamView.swift), the UI owns stream-local rendering state:

- `StreamSurfaceModel`
- `RenderSurfaceCoordinator`
- `RendererAttachmentCoordinator`

`StreamView` is responsible for:

- starting the stream if needed
- reacting to `StreamController` command streams
- showing launch artwork before the first rendered frame
- mounting `WebRTCVideoSurfaceView`
- showing overlay, reconnect, and stats UI
- cleaning up render state on disappear

This means the shell launches the stream, but once the stream is active, the UI boundary is different. Shell composition concerns and stream render-surface concerns do not live in the same view tree.

## Preview And Harness Considerations

The UI layer contains explicit preview and harness support:

- previews live under `Integration/Previews` and selected feature files
- root harness swapping happens in `RootView`
- shell readiness and stream-exit markers live in `AuthenticatedShellView`
- stream runtime markers live in `StreamView`

These harness seams are intentional. They make the shell testable without turning the main UI into a pile of conditional debug-only branches.

## UI Guardrails

The app target should not take ownership of:

- token lifecycle or auth storage
- Xbox API calls
- stream-session signaling contracts
- hydration orchestration and persistence policy
- controller graphs and lifecycle workflows

Those stay in packages, primarily `StratixCore`, `XCloudAPI`, and `StreamingCore`.

Likewise, packages should not take ownership of:

- SwiftUI shell routing
- side-rail layout
- shell-local focus memory
- stream overlay composition
- route presentation projection caches

Those stay in the app target.

Common anti-patterns in this repo are:

- reaching for `AppCoordinator` directly in views instead of reading the concrete controller needed
- rebuilding shell projections in leaf views instead of consuming shaped presentation state
- leaking stream-specific input or overlay behavior back into the shell root
- moving SwiftUI composition into package code that should stay UI-free

## Key Source Files

| File | Responsibility |
|------|----------------|
| [`StratixApp.swift`](../Apps/Stratix/Sources/Stratix/App/StratixApp.swift) | app entry and environment injection |
| [`RootView.swift`](../Apps/Stratix/Sources/Stratix/App/RootView.swift) | auth-state and harness switching |
| [`AuthenticatedShellView.swift`](../Apps/Stratix/Sources/Stratix/Shell/AuthenticatedShellView.swift) | authenticated shell container and UI-test markers |
| [`CloudLibraryView.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryView.swift) | app-side shell state owner |
| [`CloudLibraryShellHost.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Shell/CloudLibraryShellHost.swift) | shell composition root |
| [`CloudLibraryContentRouteHost.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryContentRouteHost.swift) | browse / utility / detail routing |
| [`CloudLibraryBrowseRouteHost.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryBrowseRouteHost.swift) | browse-route switchboard |
| [`CloudLibraryPresentationStore.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryPresentationStore.swift) | presentation caching |
| [`CloudLibrarySceneModel.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneModel.swift) | scene-level derived state |
| [`StreamView.swift`](../Apps/Stratix/Sources/Stratix/Features/Streaming/StreamView.swift) | active streaming surface |
| [`StreamControllerInputHost.swift`](../Apps/Stratix/Sources/Stratix/Features/Streaming/StreamControllerInputHost.swift) | stream-local controller-input interception |

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [OBSERVATION.md](OBSERVATION.md)
- [HYDRATION.md](HYDRATION.md)
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md)
- [PREVIEW_STANDARDS.md](PREVIEW_STANDARDS.md)
