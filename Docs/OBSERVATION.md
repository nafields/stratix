# Observation

This document explains how state flows through the Stratix app. Specifically: how controllers get into SwiftUI views, how those views observe changes, and why the repo separates UI state from the runtime work that produces it.

If you are adding a new feature and need to know how to read controller state in a view, or how to create a new observable state type, this doc has the pattern. If you are confused about why a particular `@Environment` call works the way it does, the rules here explain it.

---

This document explains the live observation model in Stratix: what is observable, where observable state is owned, how it is injected into SwiftUI, and how the repo keeps UI publication separate from off-main runtime work.

The important framing is that observation in Stratix is not a migration note anymore. The active app and package surfaces already assume:

- `@Observable` for UI-facing state owners
- typed environment injection
- root ownership at the app edge with `@State`
- explicit separation between UI publication and background execution

## Core Rules

The current observation rules are:

| Rule | Meaning in this repo |
|------|----------------------|
| UI-facing shared state is `@MainActor @Observable` | Controllers and shell-local app state publish on the main actor |
| Root ownership begins at the app edge | `StratixApp` owns the root coordinator with `@State` |
| Shared controllers are injected by concrete type | `.environment(controller)` is the normal app pattern |
| Views read shared state with `@Environment(Type.self)` | No string keys or mega environment objects |
| Child views only use `@Bindable` when they truly mutate an observable owner | Reads do not require `@Bindable` |
| Heavy work stays out of observation | Hydration, networking, persistence, and runtime work publish back through narrow seams |

Legacy patterns for app-owned state are not the preferred architecture here:

- `ObservableObject`
- `@Published`
- `@StateObject`
- `@ObservedObject`
- `@EnvironmentObject`

## Root Ownership

The root ownership model lives in [`StratixApp.swift`](../Apps/Stratix/Sources/Stratix/App/StratixApp.swift).

`StratixApp` owns one `AppCoordinator` as `@State` and injects the long-lived controllers into the root scene:

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

That means the app root owns the controller graph, but child views do not need to know about a mega-owner just to read one piece of state. They can ask for the concrete controller they need.

This root ownership model is one of the biggest practical differences from the repo’s older architecture. The scene owns the coordinator. The coordinator owns controllers. Views consume typed controller seams directly.

## Typed Environment Injection

Typed environment injection is the standard shared-state pattern in the app target.

The live model is:

1. `StratixApp` or another app-owned parent creates the owner
2. the owner is injected with `.environment(...)`
3. child views read the concrete type with `@Environment(Type.self)`

This keeps ownership explicit and improves previewability. A view that only needs `LibraryController` and `SettingsStore` does not need a broader coordinator dependency.

The immediate benefits in Stratix are:

- simpler previews
- easier test harness construction
- less accidental rebroadcast coupling
- narrower view dependencies

## What Is Observable Today

There are two main classes of observable state in the live repo.

### Package-owned controllers

These are the long-lived app-facing owners published from `StratixCore`.

Examples include:

- `AppCoordinator`
- `SessionController`
- `LibraryController`
- `ProfileController`
- `ConsoleController`
- `StreamController`
- `AchievementsController`
- `ShellBootstrapController`
- `SettingsStore`

These types are observable because SwiftUI surfaces actually read them.

### App-owned shell-local state

The app target also owns observable state that is not global controller state. The main example is the CloudLibrary shell, where `CloudLibraryView` owns shell-specific models as `@State`:

- `CloudLibraryViewModel`
- `CloudLibrarySceneModel`
- `CloudLibraryRouteState`
- `CloudLibraryFocusState`
- `CloudLibraryPresentationStore`

Those models are observable because the shell needs to mutate and republish them while the authenticated surface is alive, but they are not global controllers and they are not package-owned domain truth.

## The App-Side Shell Pattern

The CloudLibrary shell is the clearest example of the repo’s current observation model.

The ownership chain is:

```text
StratixApp
  └── AppCoordinator (@State at the app edge)
        └── inject controllers through typed environment
              └── AuthenticatedShellView
                    └── CloudLibraryView
                          ├── @State CloudLibraryRouteState
                          ├── @State CloudLibraryFocusState
                          ├── @State CloudLibrarySceneModel
                          ├── @State CloudLibraryPresentationStore
                          └── controller snapshots from @Environment
```

This is the key split:

- package controllers own domain state and side effects
- app-owned shell models own routed shell presentation state

`CloudLibraryView` then passes those app-owned shell models into `CloudLibraryShellHost`, which uses `@Bindable` only for the models it truly edits.

## When To Use `@Bindable`

`@Bindable` is for direct mutation of an observable owner passed into a child view.

In the live repo, `CloudLibraryShellHost` is the clearest example. It takes mutable shell state owners such as:

- `CloudLibraryRouteState`
- `CloudLibraryFocusState`
- `CloudLibraryPresentationStore`

and binds them so the host can mutate those owners directly.

Use `@Bindable` when:

- the child view is a real editor of the owner
- the owner is still the same long-lived observable object
- the mutation belongs in the child’s responsibility

Do not use `@Bindable` when:

- the child only reads state
- the child is working from a value snapshot
- the mutation should be pushed back behind a narrower callback

In other words, `@Bindable` is not a default. It is a statement that the child view is part of the owner’s mutation surface.

## When To Use `@State`

In this repo, `@State` is used for two different kinds of ownership:

1. root ownership of long-lived top-level owners  
   Example: `StratixApp` owning `AppCoordinator`
2. shell-local ownership of app-specific observable models  
   Example: `CloudLibraryView` owning its route, focus, scene, and presentation state

Use `@State` for:

- app-edge ownership
- shell-local state that should live as long as the parent view
- local-but-observable models specific to one app surface

Do not escalate something into a shared controller just because multiple subviews read it. If the state is still specific to one app shell or one visual surface, `@State` on an app-owned observable model is usually the right choice.

## Explicit Local Observable State

Not every observable object in the app needs to be globally injected.

[`CloudLibraryView.swift`](../Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryView.swift) owns several `@MainActor` app-side state models directly with `@State`, including `CloudLibrarySceneModel`, `CloudLibraryRouteState`, `CloudLibraryFocusState`, and `CloudLibraryPresentationStore`.

That is an important current-truth detail:

- these models are real observable state
- they are app-local to the authenticated shell surface
- they are passed explicitly into the CloudLibrary shell instead of being lifted into global controllers
- they are not examples of custom `EnvironmentValues` entries

This is the preferred model when the state is UI-local and not broadly shared across unrelated app surfaces.

## Observable Facade Over Off-Main Runtime Work

The streaming stack is the clearest example of “observable at the UI edge, non-observable underneath.”

[`StreamingSession.swift`](../Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSession.swift) is `@Observable @MainActor` because the app reads:

- lifecycle state
- stats
- disconnect intent
- track callbacks

But the heavy runtime work is not owned by the observable façade. The lower runtime layer lives in types such as [`StreamingSessionRuntime.swift`](../Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingSessionRuntime.swift) and related runtime models.

That means:

- SwiftUI reads `StreamingSession`
- runtime sequencing stays outside SwiftUI observation
- lifecycle, stats, tracks, and vibration are republished back through the façade

This is the pattern to copy when a UI needs observable state but the underlying execution layer should stay off-main and more narrowly scoped.

## What Is Intentionally Not Observable

A type does not become observable just because Swift code touches it.

In the live repo, these categories intentionally stay outside the observable layer:

- hydration workers and orchestrators
- SwiftData repositories
- disk persistence writers
- runtime session engines
- lower-level WebRTC bridge implementations
- task registries and debounce utilities

Examples include:

- `LibraryHydrationWorker`
- `LibraryHydrationOrchestrator`
- `SwiftDataLibraryRepository`
- `StreamingSessionRuntime`
- `TaskRegistry`

Those types can still influence UI state, but they do so by publishing results back through controllers or observable façades instead of being observed directly.

## Observation And Concurrency

Observation in Stratix is tightly coupled to the repo’s concurrency model.

The rule is not “everything should be `@MainActor`.” The rule is:

- UI-facing publication belongs on the main actor
- background work stays off-main
- results cross the boundary through narrow, explicit seams

That is why the repo treats “make the helper `@MainActor` too” as a regression unless the helper is actually a UI-facing owner.

This matters especially for:

- hydration flows
- network clients
- token refresh and auth exchange
- render-surface work
- streaming runtime sequencing
- metrics collection

Observation should make UI state easier to read and safer to publish. It should not be used as an excuse to serialize more of the runtime than necessary.

## Review Checklist

When reviewing observation-related changes in this repo, ask:

- does the new observable type actually own UI-facing state
- is the owner placed at the correct level: app root, app shell, or controller layer
- did a view gain a too-broad dependency instead of a narrower typed environment seam
- is `@Bindable` being used only where the child really mutates the owner
- did heavy work drift onto `@MainActor`
- did the change reintroduce `ObservableObject`, `@Published`, or `@EnvironmentObject` for app-owned state

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [UI_ARCHITECTURE.md](UI_ARCHITECTURE.md)
- [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md)
- [HYDRATION.md](HYDRATION.md)
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
