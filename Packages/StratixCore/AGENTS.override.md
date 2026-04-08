# AGENTS.override.md — Packages/StratixCore/

StratixCore is the app's lifecycle and coordination package. It owns `AppCoordinator`, all controllers injected into the SwiftUI environment, auth state, hydration workflows, and stream management.

**Modernization contract reference:** For modernization work in this package, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with the modernization plan, monolith breakdown, and file matrix.

---

## What lives here

```
StratixCore/Sources/StratixCore/
├── App/
│   ├── AppCoordinator.swift               ← @MainActor, ObservableObject
│   ├── AppCoordinatorTestingSupport.swift
│   ├── Composition/                       ← DI and controller composition
│   ├── Shell/                             ← Shell controller, priority handling
│   └── Lifecycle/                         ← Startup, shutdown, refresh
├── Artwork/                               ← Artwork pipeline + prefetch
├── Hydration/                             ← Library data hydration + persistence
└── Stream/                                ← Stream management + lifecycle
```

---

## AppCoordinator

`AppCoordinator` is `@MainActor` and `ObservableObject`. It is the single root of all app-level controllers. Its controllers are injected as typed environment objects in `StratixApp`.

When you add a new controller to the app:
1. Add it to `AppCoordinator` as a property
2. Inject it in `StratixApp` with `.environment(coordinator.newController)`
3. Read it in the view that needs it with `@Environment(NewController.self) var controller`

Do not pass controllers as constructor arguments through the view hierarchy. Use environment injection.

---

## Hydration

The hydration layer fetches and caches CloudLibrary content. It feeds data to `CloudLibraryViewModel` in the app target via the `libraryController`.

If you are working on CloudLibrary data freshness, caching, or offline persistence:
- The hydration workflow lives here, not in the app target's `CloudLibraryView+CacheMaintenance.swift`
- `CloudLibraryView+CacheMaintenance.swift` in the app target calls into the controller; it does not own the cache logic
- SwiftData adoption (if decided feasible) belongs in the hydration layer, not in the view model

---

## Current file-shape guidance

The old `LibraryController+PostLoadWarmup.swift` micro-shard has already been merged away. The current `LibraryController` cluster is the baseline:

- `LibraryController.swift`
- `LibraryControllerCatalogSupport.swift`
- `LibraryControllerHydrationDebug.swift`
- `LibraryControllerMRUDelta.swift`

These companion files are substantive and correctly split. Do not add new single-function extension shards around `LibraryController`.

---

## Rules

1. No SwiftUI or UIKit in StratixCore. Controllers are `@MainActor` value types or actors, not views.
2. `AppCoordinator` is the only type that creates controllers. Do not instantiate controllers elsewhere.
3. `AppCoordinatorTestingSupport.swift` provides test-only coordinator helpers. Use it in tests, not the production initializer.
4. The stream lifecycle (connecting, disconnecting, reconnecting) is owned in `Stream/` — do not route stream state through CloudLibrary.
5. Do not add new extension files to the `LibraryController` cluster. The correct extension files are `+CatalogSupport`, `+HydrationDebug`, and `+MRUDelta`. New logic goes in the closest matching existing file.

---

## Concurrency

`AppCoordinator` is `@MainActor`. Its controllers may be actors or `@MainActor` classes depending on whether they need concurrent access. New controllers should be actors if they manage shared mutable state accessed from background tasks (e.g., hydration, network responses). They should be `@MainActor` if they primarily respond to UI events.
