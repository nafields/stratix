# Runtime Flow

This document traces the execution paths that matter most in Stratix — from app boot through auth and into live streaming. It follows work as it crosses package boundaries so you can understand not just what happens, but where it happens and why it is split that way.

**This doc is most useful when you are debugging.** If something breaks mid-stream, or you want to understand why a lifecycle event triggers a particular behavior, tracing through this doc will tell you which layer owns the broken step. If you just want the high-level architecture, [`ARCHITECTURE.md`](ARCHITECTURE.md) is a better starting point.

---

This document describes how the live Stratix runtime moves work through the app
target and the packages. It focuses on the current execution path, not desired
architecture and not git history.

The repo’s runtime is controller-led, but it is not coordinator-monolithic. The
app target owns SwiftUI composition and the concrete WebRTC boundary. The package
layer owns stateful controllers, workflows, networking, persistence, and the
stream runtime. The most useful mental model is:

1. the app boots one controller graph
2. lifecycle coordinators decide which controller work should run
3. controllers delegate real work to workflows, services, and packages
4. state comes back to the app through observation-friendly controller surfaces

## Runtime Ownership Map

The active runtime owners are:

| Owner | Package / Target | Runtime responsibility |
| --- | --- | --- |
| `AppCoordinator` | `StratixCore` | Holds the top-level graph and forwards work to lifecycle and shell-boot coordinators |
| `AppLifecycleCoordinator` | `StratixCore` | Foreground, background, startup, and sign-out flow orchestration |
| `AppShellBootCoordinator` | `StratixCore` | Shell hydration startup, cache restore, and first library boot path |
| `SessionController` | `StratixCore` | Auth state, token refresh, cloud-connect auth, region cache |
| `LibraryController` | `StratixCore` | Catalog hydration, cache restore, artwork warmup, product detail state |
| `ProfileController` | `StratixCore` | Current user profile, presence, social graph, presence-write capability |
| `ConsoleController` | `StratixCore` | xHome console discovery |
| `StreamController` | `StratixCore` | Launch intent, reconnect policy, runtime attachment, stream-facing controller state |
| `InputController` | `StratixCore` | GameController observation, hold-command interpretation, vibration routing, injected frames |
| `ShellBootstrapController` | `StratixCore` | Shell hydration gate and initial route/publication delay state |
| `StreamingSession` | `StreamingCore` | Main-actor observable facade over the stream runtime |
| `StreamingRuntime` | `StreamingCore` | Actor-isolated signaling, SDP/ICE, channel startup, runtime snapshots |
| `XCloudAPIClient` and related clients | `XCloudAPI` | Service calls for cloud/home sessions, profile, presence, social, and Xbox web surfaces |

That map is the key correction to older docs. The runtime is not “the app target
plus AppCoordinator.” The controller graph is built in `StratixCore`, and each
major domain now has a clearer owner.

## Top-Level Boot Sequence

At launch, the app does not immediately “load the shell.” It performs a staged
startup:

```text
StratixApp / RootView appears
        │
        ▼
AppCoordinator.onAppear()
        │
        ▼
AppLifecycleCoordinator.onAppear()
        │
        ├── update controller settings from SettingsStore
        ├── optionally run launch haptics probe
        └── SessionController.onAppear()
                │
                ├── restore tokens from secure storage if present
                ├── otherwise try silent refresh
                └── publish auth state
                        │
                        ▼
AppCoordinator.handleSessionDidAuthenticateFromController(...)
        │
        ▼
AppShellBootCoordinator.beginShellBootHydrationIfNeeded(...)
        │
        ├── optionally restore disk caches first
        ├── ask LibraryController for a shell boot hydration plan
        └── ShellBootstrapController.beginHydrationIfNeeded(...)
                │
                ├── refresh network state or prefetch cached state
                ├── enforce minimum visible duration for the loading gate
                └── publish `.ready`
```

Three different types own this boot:

- `AppLifecycleCoordinator` owns startup policy
- `SessionController` owns auth restoration
- `AppShellBootCoordinator` plus `ShellBootstrapController` own the initial shell
  hydration gate

That is why older descriptions like “`ShellBootstrapController.bootstrap()` loads
the app” are no longer accurate enough.

## Authentication Runtime

`SessionController` is the live auth state machine. It publishes:

- `authState`
- `lastAuthError`
- `xcloudRegions`

It talks to an auth service abstraction rather than embedding Microsoft/Xbox HTTP
code directly. The default implementation is `MicrosoftSessionAuthClient`, which
wraps `MicrosoftAuthService`.

### Startup Auth Flow

On startup, `SessionController.onAppear()` does this:

1. try `restoreStreamTokens()`
2. if cached tokens exist:
   - apply them immediately as authenticated state
   - trigger a background refresh to keep the session fresh
3. if cached tokens do not exist:
   - attempt refresh-token re-authentication
4. if refresh fails:
   - publish `.unauthenticated`

So the startup auth path is optimistic and user-friendly:

- cached tokens first
- silent refresh second
- interactive sign-in only if those fail

### Interactive Sign-In Flow

Interactive sign-in is started by `SessionController.beginSignIn()`. The controller
does not expose every low-level Xbox auth endpoint directly; instead it runs the
high-level sequence:

1. request device code
2. publish `.authenticating(DeviceCodeInfo)`
3. poll for MSA token
4. exchange the MSA token for the full `StreamTokens` bundle
5. apply tokens

Applying tokens is important because it does more than just mutate `authState`.
`applyTokens(...)` also:

- clears `lastAuthError`
- updates cached xCloud regions
- records auth metrics
- notifies the `AppCoordinator` event sink

That last step is what triggers the shell boot hydration path.

### Cloud-Connect Auth During Stream Launch

Streaming has one special auth path beyond ordinary session refresh:

- `SessionController.cloudConnectAuth(logContext:)`

That method:

1. refreshes stream tokens
2. fetches the LPT-style connect user token needed by the xCloud `/connect` step
3. returns both the refreshed token bundle and the connect token together

That means stream launch does not rely on stale session state. It explicitly asks
the session layer for stream-ready auth input right before the connect workflow.

### Region Cache

`SessionController` also caches xCloud regions. The live behavior is:

- use regions embedded in fresh tokens if available
- otherwise restore cached regions from defaults
- clear cached regions on sign-out

That is a small but important runtime seam because region-aware launch and settings
flows rely on it.

## Shell Boot And Hydration Runtime

Shell boot is not the same as auth completion. After full auth, the app still has
to decide whether to restore cached shell state, refresh the library, defer route
publication, and prefetch artwork.

### Shell Boot Control Plane

The live owners are:

- `AppShellBootCoordinator`
- `ShellBootstrapController`
- `LibraryController`

`AppShellBootCoordinator.beginShellBootHydrationIfNeeded(...)` orchestrates the
decision. It consults:

- whether the shell is currently suspended for streaming
- whether the user is authenticated
- whether caches should be restored before the boot run

It can restore:

- library disk caches
- achievement disk caches
- profile/social cache

Then it asks `LibraryController.makeShellBootHydrationPlan(...)` for the next step.

### Shell Bootstrap Phase

`ShellBootstrapController` publishes the shell boot gate through:

- `.idle`
- `.hydrating(statusText:deferRoutePublication:)`
- `.ready`

That controller exists to hold the visible boot/hydration gate, not to own the
network refresh itself. Its `beginHydrationIfNeeded(...)` method runs whichever
action the plan requires:

- network refresh
- cached prefetch

It also enforces a minimum visible duration for the loading gate so the shell does
not flicker through intermediate startup states too quickly.

This split is worth preserving in the docs because it explains why shell startup
feels unified in the UI even though the work is distributed across several
controllers and workflows.

## Library Runtime

`LibraryController` owns the catalog-facing runtime state. It is responsible for:

- sections and indexes
- product details
- last hydrated timestamps
- error state
- artwork prefetch state
- home merchandising
- persistence-backed hydration

### Refresh Path

The public runtime entry is:

- `LibraryController.refresh(forceRefresh:reason:deferInitialRoutePublication:)`

That method:

1. skips work entirely if hydration is suspended for streaming
2. logs the request reason and cache age
3. skips work when the unified snapshot is still fresh unless forced
4. deduplicates concurrent refreshes through `TaskRegistry`
5. runs either an injected refresh workflow or the default
   `LibraryHydrationRefreshWorkflow`

The controller also builds explicit `LibraryHydrationRequest` values. Those values
carry runtime rules such as:

- whether cache restore is allowed
- whether persistence writes are allowed
- whether delta refresh is preferred
- whether initial route publication should be deferred

That request object is the runtime contract between controller-level intent and
the hydration pipeline.

### Hydration Runtime Shape

The detailed hydration stack is covered in [HYDRATION.md](HYDRATION.md), but the
runtime summary is:

- `LibraryController` decides when hydration should happen
- the planner and worker build a concrete hydration plan
- repository-backed persistence restores and writes the unified snapshot
- publication happens back through controller state

After a successful library load, the controller can also warm adjacent surfaces:

- current-user profile
- social people
- artwork prefetch

That is why the library runtime influences more than just the browse grid.

## Profile And Social Runtime

`ProfileController` owns three closely related but distinct surfaces:

- current user profile
- current user presence
- social people

The controller exposes separate loading and error state for presence and social
because those surfaces do not always succeed or refresh together.

### Runtime Entry Points

Primary entry points:

- `refresh(force:)`
- `loadCurrentUserProfile(force:)`
- `loadCurrentUserPresence(force:)`
- `loadSocialPeople(force:maxItems:)`
- `setCurrentUserPresence(isOnline:)`

The controller deduplicates profile, presence, and social requests independently
with task IDs, so a social refresh does not automatically imply a profile reload.

### Dependency Boundary

The controller depends on profile/session-facing credentials supplied by its
dependency interface, then fans that out to the correct client:

- `XboxWebProfileClient`
- `XboxWebPresenceClient`
- `XboxSocialPeopleClient`

It also persists one small piece of runtime capability state:

- whether presence writes are supported in the current environment

That allows the UI to fall back to read-only status behavior when the environment
does not support presence updates.

### Streaming Suspension

Like several other controllers, `ProfileController` can suspend itself for
streaming. During suspension it cancels in-flight tasks and avoids refreshing shell
surfaces that should stay stable while a stream is active.

## Console Runtime

`ConsoleController` is intentionally smaller than the library and profile
controllers. Its job is to load and publish remote consoles for xHome launching.

The runtime flow is:

1. ask dependencies for authenticated console tokens
2. build an `XCloudAPIClient` with xHome host/token
3. call `getConsoles()`
4. publish the resulting `RemoteConsole` array

Like the other controllers, it:

- deduplicates refreshes
- carries loading and last-error state
- can suspend itself for streaming

It is a separate controller because console discovery has its own auth host, its
own refresh cadence, and a different runtime audience than the main cloud library.

## Streaming Runtime

The stream lane is covered in detail in [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md),
but the runtime summary belongs here because it is one of the repo’s major flows.

### Controller Layer

`StreamController` owns:

- active stream state
- reconnect state
- overlay visibility
- runtime phase
- launch artwork
- shell-restoration flags

It delegates launch work to:

- `StreamLaunchWorkflow`
- `StreamCloudLaunchWorkflow`
- `StreamHomeLaunchWorkflow`

It delegates runtime bind/unbind work to:

- `StreamRuntimeAttachmentService`

It delegates reconnect policy to:

- `StreamReconnectCoordinator`

It delegates stop/teardown to:

- `StreamStopWorkflow`

### Runtime Layer

`StreamingSession` is the main-actor facade the app reads.

`StreamingRuntime` is the actor that owns:

- signaling
- SDP/ICE
- data-channel startup
- negotiated dimensions
- input flush telemetry
- lifecycle publication back to the session

The app target then attaches the resulting tracks through `StreamView`,
`RenderSurfaceCoordinator`, and `RendererAttachmentCoordinator`.

That layered split is the main runtime truth to keep in mind:

- controller intent
- workflow preparation
- runtime attachment
- actor-owned connect pipeline
- app-owned render surface

## Controller Input Runtime

`InputController` bridges system controllers and the active streaming session.

Its live responsibilities are:

- observe `GCController` connect/disconnect events
- build `GamepadHandler` instances for connected controllers
- apply current controller settings from `SettingsStore`
- route vibration reports from the stream runtime back to controllers
- inject synthetic frames into the active `InputQueue`
- interpret hold combinations for shell-level commands

### Hold Commands

The current live hold-command interpreter recognizes long holds such as:

- Start + Select
- L3 + R3

Those holds are used for higher-level commands like overlay toggling or synthetic
Nexus-style behavior without confusing the core input runtime with shell policy.

### Session Boundary

`InputController` does not own the input channel. The stream runtime owns the
channel. `InputController` owns the system-controller observation side and writes
into the active session’s `inputQueueRef`.

That boundary is important:

- `StreamingCore` owns the transport cadence and channel startup
- `InputBridge` owns queueing and packet shaping
- `InputController` owns the Apple-platform input side

## Foreground, Background, And Sign-Out Runtime

The runtime does not stop after startup. `AppLifecycleCoordinator` continues to
own foreground, background, and sign-out policy.

### Foreground Refresh

On app re-entry, `handleAppDidBecomeActive()` delegates to the foreground refresh
workflow. That workflow can:

- refresh stream tokens in background
- refresh the cloud library
- prefetch artwork

It also checks whether stream priority mode is active or a streaming session is
already present so the app does not fight the active stream for shell ownership.

### Background Refresh

`performBackgroundAppRefresh()` runs the background workflow and compares refreshed
library state against baseline state. That allows the coordinator to report whether
the background refresh actually changed coordinator-owned state.

### Sign-Out

Sign-out is a full graph reset, not just token deletion.

`AppLifecycleCoordinator.handleSessionDidSignOut()` runs the sign-out workflow,
which resets and clears:

- consoles
- library state and library caches
- shell bootstrap state
- achievements and achievement cache
- profile and social cache
- stream state
- input state

That full reset is what makes the repo safe to treat sign-out as a real return to
anonymous state rather than a shallow auth toggle.

## Boundary Rules That Matter At Runtime

Several runtime rules are worth calling out explicitly:

- the app target owns SwiftUI composition and the concrete WebRTC bridge
- packages own controllers, workflows, networking, and persistence
- `LibraryController`, `ProfileController`, and `ConsoleController` can suspend
  themselves for streaming so the shell stays stable while a session is active
- `StreamingCore` depends on `WebRTCBridge`, not the vendored framework
- controller state is main-actor observable; heavy runtime mechanics are pushed
  into actors or lower-level services

These are not just style choices. They explain why the repo remains testable while
still running a complex Apple TV stream runtime.

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [OBSERVATION.md](OBSERVATION.md)
- [HYDRATION.md](HYDRATION.md)
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md)
- [TESTING.md](TESTING.md)
