# Library Hydration

When Stratix launches and you sign in, it does not just fetch your game library from scratch every time. It restores a cached snapshot first (so the shell becomes interactive quickly), then fetches fresh data in the background, and later enriches that data with artwork and metadata from Xbox.com. This process — taking data from multiple sources and turning it into a usable, persisted library — is what the codebase calls hydration.

This document explains how that process works, what the pieces are, and who owns each step. Read it when you are working on library data behavior, persistence, or the startup experience. See [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md) for where the hydration code lives in the package structure, and [`RUNTIME_FLOW.md`](RUNTIME_FLOW.md) for how hydration fits into the broader boot sequence.

---

This document explains the live hydration subsystem in Stratix: how the library cache is restored, how live catalog refresh works, how post-stream recovery stays targeted, and how hydration results are published and persisted without turning `LibraryController` into a single monolithic algorithm bucket.

## What Hydration Means In Stratix

Hydration is the set of workflows that turn Xbox and xCloud library inputs into the observable `LibraryState` consumed by the app shell.

The current goals are:

1. restore useful cached state quickly enough for the authenticated shell to become interactive
2. fetch fresh network data only when the planner decides the current snapshot is incomplete or stale
3. publish library updates in ordered stages instead of one giant all-at-once mutation
4. keep post-stream recovery targeted when a delta is sufficient
5. persist unified library snapshots with enough metadata to reject low-quality or wrong-market cache data on the next launch

Hydration is therefore not just “load cached sections, then hit the network.” It is a planner-driven system with explicit request, orchestration, publication, and persistence seams.

## Main Pieces

The hydration subsystem spans a small set of clearly separated responsibilities.

### `LibraryController`

[`LibraryController.swift`](../Packages/StratixCore/Sources/StratixCore/LibraryController.swift) is the observable façade. It owns the canonical `LibraryState` and exposes the public entry points that the rest of the app uses:

- `refresh(forceRefresh:reason:)`
- `restoreDiskCachesIfNeeded(isAuthenticated:)`
- `makeShellBootHydrationPlan(isAuthenticated:)`
- `refreshPostStreamResumeDelta(plan:)`

`LibraryController` does not inline the full hydration algorithm. It delegates orchestration to dedicated hydration types and applies typed `LibraryAction` updates back into `LibraryState`.

### `LibraryHydrationOrchestrator`

[`LibraryHydrationOrchestrator.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationOrchestrator.swift) is the main coordinator for the three hydration flows:

- startup restore
- live refresh
- post-stream delta

It does not fetch everything itself. Instead it stitches together the planner, worker, publication, persistence, and workflow types and returns a typed `LibraryHydrationOrchestrationResult`.

### `LibraryHydrationPlanner`

[`LibraryHydrationPlanner.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationPlanner.swift) decides whether the current library snapshot is fresh and complete enough to reuse.

The planner checks more than timestamp age. It also evaluates:

- whether sections exist
- whether home merchandising exists
- whether the unified home is marked ready
- whether discovery data exists
- whether snapshot market and language still match the current hydration config
- whether completeness metadata says any section is incomplete

That is why startup restore and post-stream recovery can be selective instead of always forcing a full network refresh.

### `LibraryHydrationWorker`

`LibraryHydrationWorker` performs cache I/O and decode work away from the main actor. Startup restore relies on it to load the persisted startup payload without blocking the UI-facing controller.

### Live-refresh workflows

The live refresh path is split across two main workflow types:

- [`LibraryHydrationLiveRefreshWorkflow.swift`](../Packages/StratixCore/Sources/StratixCore/LibraryHydrationLiveRefreshWorkflow.swift)
- [`LibraryHydrationLiveCommitWorkflow.swift`](../Packages/StratixCore/Sources/StratixCore/LibraryHydrationLiveCommitWorkflow.swift)

The refresh workflow fetches live inputs and shapes catalog state. The commit workflow decides what should be published, what should be persisted, and in what staged order the publication should happen.

### Post-stream workflow

[`LibraryHydrationPostStreamDeltaWorkflow.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationPostStreamDeltaWorkflow.swift) handles the targeted post-stream path. It tries to recover with MRU-driven deltas first and escalates to full refresh only when a delta cannot safely repair shell-visible library state.

### Publication coordinator

[`LibraryHydrationPublicationCoordinator.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationPublicationCoordinator.swift) stages actions back into `LibraryController`. This is the seam that turns one orchestration result into ordered publication phases instead of one unordered mutation burst.

### Persistence

Persistence is split:

- unified sections, home merchandising, and discovery live in [`SwiftDataLibraryRepository.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/SwiftDataLibraryRepository.swift)
- product details are written through [`LibraryHydrationPersistence.swift`](../Packages/StratixCore/Sources/StratixCore/LibraryHydrationPersistence.swift) using a debounced disk writer

That split lets startup restore pull the shell-facing unified snapshot quickly while still keeping the larger product-detail cache separately managed.

## The Typed Request / Result Model

Hydration no longer relies on a grab bag of booleans and controller-local side effects. The live code passes explicit request and result types through the system.

The core request type is [`LibraryHydrationRequest.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationRequest.swift). A request records:

- `trigger`
- `market`
- `language`
- whether delta refresh is preferred
- whether full refresh is forced
- whether cache restore is allowed
- whether persistence writes are allowed
- whether initial route publication should be deferred
- the user-visible refresh reason, when one exists
- a source description for logging and metadata

The trigger values are:

- `shellBoot`
- `startupRestore`
- `liveRefresh`
- `postStreamDelta`
- `foregroundResume`
- `backgroundWarm`

Each top-level workflow produces a `LibraryHydrationOrchestrationResult`. That result contains:

- the `LibraryAction` values to apply
- a `LibraryHydrationPersistenceIntent`
- an optional cached discovery payload
- the source trigger
- a `LibraryHydrationPublicationPlan`
- an optional post-stream outcome

This is what allows the controller to separate “what needs to be published” from “how and when should it be persisted.”

## Startup Restore

Startup restore is now a shell-boot support path, not the entire shell-boot algorithm.

The actual startup chain looks like this:

```text
AppShellBootCoordinator
  ├── optionally restore disk caches first
  │     └── LibraryController.restoreDiskCachesIfNeeded(isAuthenticated:)
  │           └── LibraryHydrationOrchestrator.performStartupRestore(...)
  │                 ├── LibraryHydrationStartupRestoreWorkflow
  │                 ├── LibraryHydrationWorker.loadStartupCachePayload(...)
  │                 └── LibraryHydrationPlanner.makeStartupRestoreResult(...)
  └── ask LibraryController for a shell-boot plan
        └── ShellBootstrapController.beginHydrationIfNeeded(...)
```

The important point is that startup restore and shell boot are related, but they are not the same thing.

`restoreDiskCachesIfNeeded(isAuthenticated:)` only runs if the current session is authenticated and the relevant caches have not already been loaded into memory. It can restore:

- the unified sections snapshot
- the product-details cache

The orchestrator’s startup-restore result is converted into typed `LibraryAction` values and then published through the publication coordinator. Startup restore uses a minimal publication plan centered on route restoration rather than the full live-refresh sequence.

If the cache is missing, stale, incomplete, wrong-market, or otherwise rejected by the planner, startup restore simply leaves the controller in a state where a live refresh can do the real repair work.

## Shell-Boot Planning

Hydration planning also feeds shell boot directly.

`LibraryController.makeShellBootHydrationPlan(isAuthenticated:)` delegates to the planner, which decides between:

- `.prefetchCached`
- `.refreshNetwork`

The planner chooses `.prefetchCached` only when the controller already has a fresh, complete startup snapshot:

- sections are present
- home merchandising exists
- initial home merchandising has completed
- the snapshot is still within the unified hydration TTL

Otherwise it chooses `.refreshNetwork`.

That plan is then handed to [`ShellBootstrapController.swift`](../Packages/StratixCore/Sources/StratixCore/ShellBootstrapController.swift), which owns the visible shell-bootstrap gate state:

- `.idle`
- `.hydrating(statusText:deferRoutePublication:)`
- `.ready`

The shell bootstrap controller does not decide freshness itself. It executes the plan it was given and keeps the shell gate visible for at least the plan’s minimum duration.

## Live Refresh

The public entry point is `LibraryController.refresh(forceRefresh:reason:)`.

The controller first handles cheap gate checks:

- skip when hydration is suspended for stream-priority mode
- skip when the current unified snapshot is still fresh and a forced refresh was not requested
- coalesce duplicate refreshes through the controller task registry

If a refresh should run, the controller uses [`LibraryHydrationRefreshWorkflow.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationRefreshWorkflow.swift) to:

- mark loading state
- build a live-refresh hydration request
- call `hydrationOrchestrator.performLiveRefresh(...)`
- apply the orchestration result
- retry after silent token refresh when the initial refresh fails for auth reasons

### What live fetch does

`LibraryHydrationLiveRefreshWorkflow` is where the live inputs are gathered.

The live fetch path:

1. validates the available library token candidates
2. resolves the preferred xCloud host for the chosen token
3. fetches cloud titles and MRU titles from `XCloudAPIClient`
4. optionally merges supplementary catalog responses such as the F2P lane
5. shapes the raw title responses into `LibraryHydrationCatalogState`
6. runs `LibraryHydrationCatalogShapingWorkflow`
7. refreshes home merchandising for the newly shaped sections

This is also where host resolution and token fallback live. The workflow does not assume one always-valid xCloud token or one static service host.

### What live commit does

`LibraryHydrationLiveCommitWorkflow` takes the fetch result and converts it into:

- the `LibraryAction` values to publish
- a `LibraryHydrationPersistenceIntent`
- a `LibraryHydrationPublicationPlan`

For a normal live refresh, the publication plan can include staged phases such as:

- `authShell`
- `routeRestore`
- `mruAndHero`
- `visibleRows`
- `detailsAndSecondaryRows`
- `socialAndProfile`
- `backgroundArtwork`

That plan is what lets the controller publish core shell-visible state first and defer heavier secondary work until later in the sequence.

## Publication Staging

Publication happens through [`LibraryHydrationPublicationCoordinator.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationPublicationCoordinator.swift), not through random direct controller mutations.

The coordinator splits actions into:

- primary actions
- detail actions

It then applies them according to the publication plan:

- route-restore and primary shell stages
- detail publication stage
- profile and social warming
- visible home artwork prefetch
- broader library artwork prefetch

This is the seam that keeps library hydration from feeling like one opaque controller mutation even though the end result is still one coherent `LibraryState`.

## Persistence Model

Hydration persistence has two durable outputs.

### Unified snapshot in SwiftData

[`SwiftDataLibraryRepository.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/SwiftDataLibraryRepository.swift) stores the unified shell-facing snapshot in one SwiftData record:

```swift
@Model
final class UnifiedLibraryCacheRecord {
    @Attribute(.unique) var key: String
    var savedAt: Date
    var payload: Data
}
```

That unified snapshot contains the pieces needed to restore the shell quickly:

- sections
- home merchandising
- SIGL discovery cache
- unified-home-ready state
- hydration metadata

The repository can:

- load cached sections
- save sections
- load cached home merchandising
- save home merchandising
- load the full unified snapshot
- save the full unified snapshot
- clear the unified snapshot

The repository store name is `StratixLibraryRepository`.

### Product details on disk

Product details are persisted separately through [`LibraryHydrationPersistence.swift`](../Packages/StratixCore/Sources/StratixCore/LibraryHydrationPersistence.swift). That file owns:

- the debounced `DiskSnapshotWriter`
- `LibraryHydrationPersistenceStore`
- snapshot-finalization helpers

This store writes product details separately from the unified sections snapshot so detail-heavy cache data does not distort the shell-startup restore path.

### Metadata matters

Persistence does not write anonymous blobs. The generated snapshots carry `LibraryHydrationMetadata`, including:

- snapshot ID
- generation time
- cache version
- market
- language
- refresh source
- hydration generation
- home-ready flag
- completeness by section
- deferred publication stages
- trigger

The planner uses that metadata to decide whether a cached snapshot is good enough to trust on the next boot.

## Post-Stream Delta

Post-stream recovery is intentionally not just “run a normal refresh again.”

`LibraryController.makePostStreamHydrationPlan()` asks the planner whether the current library state is healthy enough to allow an MRU delta path. The planner returns either:

- `.refreshMRUDelta`
- `.refreshNetwork`

If the state is missing sections, missing home merchandising, missing freshness timestamps, or stale, the planner escalates to full refresh.

If a delta is allowed, [`LibraryHydrationPostStreamDeltaWorkflow.swift`](../Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationPostStreamDeltaWorkflow.swift) does the targeted path:

1. fetch live MRU entries
2. apply an MRU-based section delta
3. refresh home merchandising for the affected sections
4. emit a recovery state and persistence intent

The workflow can return three meaningful outcomes:

- `requiresFullRefresh(...)`
- `noChange`
- `appliedDelta`

That makes stream-exit recovery explicit and testable instead of hiding it inside a generic “reload library” call.

## Where The UI Sees Hydration

The app target never talks to `SwiftDataLibraryRepository` or the hydration workflows directly. The UI only sees the results through `LibraryController` and the shell state derived from it.

In practice:

- `CloudLibraryView` reads controller snapshots
- `CloudLibraryLoadStateBuilder` turns those snapshots into shell-facing load state
- `CloudLibraryPresentationStore` and `CloudLibrarySceneModel` rebuild view projections from the updated controller state

This keeps persistence and orchestration out of the SwiftUI layer.

## Ownership Summary

| Concern | Live owner |
|---------|------------|
| Observable library façade | `LibraryController` |
| Hydration planning | `LibraryHydrationPlanner` |
| Startup restore orchestration | `LibraryHydrationOrchestrator` + `LibraryHydrationStartupRestoreWorkflow` |
| Live fetch | `LibraryHydrationLiveRefreshWorkflow` |
| Live publish/persist decision | `LibraryHydrationLiveCommitWorkflow` |
| Post-stream delta recovery | `LibraryHydrationPostStreamDeltaWorkflow` |
| Ordered publication | `LibraryHydrationPublicationCoordinator` |
| Unified snapshot persistence | `SwiftDataLibraryRepository` |
| Product-details persistence | `LibraryHydrationPersistenceStore` |
| Shell boot gate | `ShellBootstrapController` |

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [UI_ARCHITECTURE.md](UI_ARCHITECTURE.md)
- [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md)
- [OBSERVATION.md](OBSERVATION.md)
- [RUNTIME_FLOW.md](RUNTIME_FLOW.md)
