# Streaming Architecture

This document explains how game streaming actually works in Stratix — from the moment a user taps a title to the point where video is on screen and controller input is flowing. It is organized by layer so you can understand each piece independently before seeing how they connect.

**The short version:** You tap a game. The app resolves your auth, sends a session creation request to Microsoft's servers, waits for the server to get ready, and then establishes a WebRTC peer connection. Once the peer connection is up, video streams to a Metal renderer and your controller inputs go back at 125 Hz over a data channel. The whole thing is orchestrated across four layers — the app's SwiftUI surface, `StratixCore`'s controller layer, `StreamingCore`'s runtime, and the `XCloudAPI` HTTP layer beneath.

If you are debugging a streaming problem, [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) has the specific failure modes. If you want to understand the WebRTC boundary specifically, [`WEBRTC_GUIDE.md`](WEBRTC_GUIDE.md) goes deeper on the custom build. If you want the input side, see [`CONTROLLER_INPUT.md`](CONTROLLER_INPUT.md).

---

This document explains the live streaming stack in Stratix as it exists in the
current repository. It is not a historical overview and it does not describe
planned architecture. The goal here is to make the active layers clear:

- where stream launch starts
- which package owns each step
- how signaling and runtime startup are separated
- how the app target attaches WebRTC and rendering
- how reconnect, teardown, and shell recovery fit around the runtime

The important correction relative to older docs is that streaming is no longer a
single flat flow owned by one controller. The live design is layered:

1. the app target owns the visible stream scene and the concrete WebRTC bridge
2. `StratixCore` owns main-actor controller orchestration and launch workflows
3. `StreamingCore` owns the actor-isolated runtime, signaling, channels, and
   session facade
4. `XCloudAPI` owns the HTTP clients and session endpoints used by the runtime

## Streaming At A Glance

```text
User selects a cloud title or remote console
        │
        ▼
StreamView + RenderSurfaceCoordinator.startStream(...)
        │
        ▼
StreamController.startCloudStream(...) / startHomeStream(...)
        │
        ▼
StreamLaunchWorkflow
        ├── StreamCloudLaunchWorkflow
        └── StreamHomeLaunchWorkflow
        │
        ├── resolve launch config + preferences off main actor
        ├── create XCloudAPIClient
        ├── create StreamingSession facade
        ├── attach runtime-facing observers and input bindings
        └── call session.connect(...)
                │
                ▼
        StreamingSession (@MainActor facade)
                │
                ▼
        StreamingRuntime (actor)
                │
                ├── start session on Microsoft service
                ├── wait for ready/provisioned state
                ├── xCloud-only connect auth if needed
                ├── create offer and process local SDP
                ├── exchange SDP
                ├── exchange ICE
                ├── wait for peer connection
                ├── bring up message/control/input/chat channels
                └── publish runtime snapshots back to session
                │
                ▼
        StreamView + WebRTCVideoSurfaceView
                │
                ├── onVideoTrack replay from StreamingSession
                ├── RenderSurfaceCoordinator policy
                └── RendererAttachmentCoordinator concrete UIKit renderer lifecycle
```

Two practical consequences follow from this split:

- `StreamController` is not the signaling runtime. It coordinates launch intent,
  state, reconnect policy, and shell-facing behavior.
- `StreamingSession` is not the whole engine either. It is the observable session
  facade SwiftUI reads while `StreamingRuntime` owns the actor-isolated connect
  and channel startup work.

## Entry Points And Target Split

The app enters streaming through `StreamView` and `RenderSurfaceCoordinator`, not
through a legacy `AppCoordinator.startCloudStream(...)` path and not through a
generic `StreamController.launch(title:)` API.

The two live public launch entry points are:

- `StreamController.startCloudStream(titleId:bridge:)`
- `StreamController.startHomeStream(console:bridge:)`

That split matters because cloud and home streams have different launch inputs:

- cloud streaming needs cloud-connect auth and a resolved xCloud host
- home streaming needs xHome host and token state, but does not perform the same
  `/connect` auth step

The app-side `StreamContext` preserves that distinction all the way to the
controller layer. `RenderSurfaceCoordinator.startStream(...)` prepares or reuses
the concrete `WebRTCClientImpl` bridge, then dispatches to the correct controller
entrypoint based on whether the user is launching a catalog title or a remote
console.

## App-Side Ownership

The app target owns the visible stream experience and the concrete framework
integration boundary.

Primary app-owned files:

- `Apps/Stratix/Sources/Stratix/Features/Streaming/StreamView.swift`
- `Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RenderSurfaceCoordinator.swift`
- `Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RendererAttachmentCoordinator.swift`
- `Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/WebRTCVideoSurfaceView.swift`
- `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImpl.swift`
- `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplBridge.swift`

`StreamView` is the composition root for the full-screen stream scene. It owns:

- the first-frame artwork fallback
- overlay and HUD placement
- dismissal wiring
- the `WebRTCVideoSurfaceView`
- hidden runtime-status markers used by UI harnesses

`RenderSurfaceCoordinator` owns stream-surface policy rather than the renderers
themselves. It decides when to start a stream, how to reset surface state on
session changes, when diagnostics polling should be active, and how explicit exit
differs from ordinary disappearance. It also attaches the session’s `onVideoTrack`
callback once per session identity and routes renderer telemetry back into
`StreamSurfaceModel`.

`RendererAttachmentCoordinator` owns the concrete UIKit renderer lifecycle. It is
responsible for:

- installing the container view
- binding the sample-buffer renderer
- creating and managing the Metal renderer
- selecting floors and fallbacks with `RenderLadderPlanner`
- tracking renderer telemetry, first-frame events, and decode failures

This separation is deliberate. The visible stream scene, render policy, and
concrete renderer lifecycle are distinct responsibilities.

## StratixCore: Controller And Workflow Layer

`StratixCore` owns the main-actor streaming controller and the workflow layer
wrapped around the session runtime.

Primary controller and workflow files:

- `Packages/StratixCore/Sources/StratixCore/StreamController.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamLaunchWorkflow.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamCloudLaunchWorkflow.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamHomeLaunchWorkflow.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamRuntimeAttachmentService.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamStopWorkflow.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamReconnectCoordinator.swift`

`StreamController` is `@Observable` and `@MainActor`. It owns the user-facing
stream state:

- active session reference
- runtime phase
- overlay visibility
- reconnect state
- launch artwork URL
- achievement snapshot state
- shell-restoration flags

The controller does not inline the whole connect sequence. Instead it composes
several dedicated collaborators:

- `StreamLaunchWorkflow` gates duplicate starts
- `StreamCloudLaunchWorkflow` runs cloud-specific launch work
- `StreamHomeLaunchWorkflow` runs home-specific launch work
- `StreamRuntimeAttachmentService` binds the observable session to controller input
  and lifecycle observation
- `StreamStopWorkflow` handles teardown
- `StreamReconnectCoordinator` schedules and performs reconnect relaunches

### Launch Workflow Responsibilities

Both cloud and home launch workflows follow the same high-level shape:

1. validate that no session is already active
2. enter stream priority mode
3. prepare video capabilities and controller settings
4. record reconnect launch context
5. clear stale stream-facing state
6. stop any overlay refresh that should not survive a new launch
7. resolve the launch configuration off the main actor
8. create an `XCloudAPIClient`
9. create a `StreamingSession`
10. attach runtime observation and input routing
11. call `session.connect(...)`

The workflows differ where the platform/service contract differs.

#### Cloud Launch

`StreamCloudLaunchWorkflow` additionally:

- obtains `SessionController.CloudConnectAuth`
- validates that an xCloud token exists
- resolves the current xCloud host from the launch configuration service
- passes the cloud connect user token into `session.connect(type:.cloud, ...)`

#### Home Launch

`StreamHomeLaunchWorkflow`:

- resolves home launch configuration from the current environment
- builds the client using the xHome host and token
- calls `session.connect(type:.home, targetId:..., msaUserToken:nil)`

### Runtime Attachment Is A Separate Step

One of the biggest places older docs drifted was skipping over session attachment.
The current code attaches the session to controller-owned observers before the
runtime connect sequence starts.

`StreamRuntimeAttachmentService.attach(...)` does three things:

1. binds `StreamSessionLifecycleObserver` to the session
2. wires controller observation to `session.inputQueueRef`
3. installs the controller-owned vibration routing callback

It also publishes the stream actions that move controller state from detached to
attached session ownership.

That ordering matters because reconnect handling, controller input routing, and
session lifecycle observation must already be live by the time the runtime starts
signaling.

## StreamingSession: Main-Actor Facade

`StreamingSession` lives in `StreamingCore`, but it is the object the app and
controller layer actually observe.

Key file:

- `Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSession.swift`

`StreamingSession` is:

- `@Observable`
- `@MainActor`
- a `StreamingSessionFacade`

It publishes:

- `lifecycle`
- `stats`
- `disconnectIntent`

It also exposes:

- `inputQueueRef`
- `onLifecycleChange`
- `onVideoTrack`
- vibration handler registration

The important design point is that the session facade is not the same thing as
the runtime actor. `StreamingSession` wraps a `StreamingSessionModel`, delegates
connect and disconnect ownership to the runtime, and mirrors runtime-owned state
back into main-actor observable properties.

Two behaviors are especially important for the app layer:

- video and audio tracks are replayed to late subscribers, so `StreamView` does
  not miss a track just because it attached after the callback happened
- diagnostics polling is exposed as a session concern, but the decision to enable
  it remains app-owned through `RenderSurfaceCoordinator`

## StreamingRuntime: Actor-Isolated Signaling And Channel Bring-Up

The actual connect pipeline lives in `StreamingRuntime`, an actor in
`StreamingCore`.

Primary runtime files:

- `Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingRuntime.swift`
- `Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingSessionRuntime.swift`

The runtime owns:

- signaling session state
- SDP processing
- ICE processing
- message/control/input/chat channel startup
- negotiated dimensions
- input flush telemetry
- runtime snapshot publication

### Live Connect Sequence

The current connect sequence in `StreamingRuntime.connect(...)` is:

1. reset transient runtime state and publish a clean snapshot
2. call `apiClient.startStream(...)`
3. create a `StreamSession`
4. publish `.provisioning`
5. wait for the service state required by the stream kind
6. for cloud streams only, perform `/connect` auth when needed
7. publish `.connectingWebRTC`
8. ask the bridge to apply codec/data-channel preferences
9. create the offer
10. process the local SDP with bitrate, codec, and profile preferences
11. set local description
12. exchange SDP with the service
13. process and apply remote SDP
14. gather and send stable local ICE candidates
15. receive, expand, and apply remote ICE candidates
16. start keepalive
17. wait for the peer connection to become connected
18. publish `.connected`

Cloud streams have one additional nuance: after `waitUntilReadyOrProvisioned(...)`,
the runtime only performs the `/connect` auth step if the service actually paused
at `readyToConnect`. If the cloud session is already provisioned, the runtime
skips the redundant auth step instead of forcing an unnecessary retry path.

### Data-Channel Startup Is Deferred And Ordered

Peer connection success is not the end of startup. The runtime still has to bring
up the message, control, input, and chat channels in the order the service expects.

The current live order is:

1. `message` channel opens and performs the handshake immediately
2. `chat` channel may open immediately
3. `control` and `input` channels are configured when they open, but they do not
   fully start until the message handshake completes
4. once the handshake is complete:
   - `controlChannel.onOpen()` runs
   - queued gamepad connection state is flushed
   - `inputChannel.onOpen()` runs

This ordering is explicit in `startDeferredChannelsIfReady()`. Older flatter docs
described the data channels as if they all started together. That is not true in
the current runtime.

### Dimensions And Snapshot Publication

The runtime also tracks stream dimensions through two different paths:

- preferred dimensions prepared before startup
- negotiated dimensions received later via server metadata on the input channel

When server metadata arrives, the runtime updates the snapshot and may send a
post-handshake dimensions update over the message channel if the negotiated size
differs from the initial message-channel preference.

## Input Channel And Controller Cadence

The input channel is one of the biggest places older docs were wrong.

`InputChannel` currently runs at:

- `125 Hz`
- `8 ms` loop interval

It does not run the old `250 Hz / 4 ms` loop described in earlier documentation.

On open, the current input channel:

1. sends client metadata immediately
2. starts a high-frequency loop
3. flushes `InputQueue`
4. coalesces or sends pending packets
5. emits flush telemetry back to the runtime

Inbound input-channel messages currently matter for two live behaviors:

- vibration reports
- server metadata reporting stream dimensions

The controller-side meaning of button holds and shell commands lives above the raw
channel in the input and controller layers, but the runtime still owns the channel
that actually sends the binary input stream to Microsoft’s service.

## WebRTC Boundary

The concrete framework-backed WebRTC implementation remains app-owned.

Package code depends on `WebRTCBridge`, not on the vendored `WebRTC.xcframework`.
That is the repo’s key boundary for testability and portability.

Current shape:

- `StreamingCore` talks only to `WebRTCBridge`
- the app target provides `WebRTCClientImpl` when `WEBRTC_AVAILABLE` is active
- the app target can also use `MockWebRTCBridge` for non-framework paths

`WebRTCClientImplBridge.applyH264CodecPreferences()` sets up the active live
transceivers and data-channel bundle before offer creation. On tvOS, the current
audio and video transceiver posture is receive-oriented for the stream path, not a
generic two-way media-session setup.

This boundary lets the packages describe stream runtime mechanics without importing
UIKit, Metal, or the concrete WebRTC framework.

## Reconnect, Disconnect, And Exit

Reconnect policy is not buried inside the runtime actor. It is controller-owned.

`StreamController.handleLifecycleEvent(...)` forwards lifecycle changes to
`StreamReconnectCoordinator`, which decides whether reconnect is allowed based on:

- current disconnect intent
- auto-reconnect setting
- reconnect attempt count
- whether the last launch target and bridge are still known

When reconnect is allowed, the coordinator:

1. publishes reconnect state
2. waits for the retry delay
3. disconnects and detaches the current session through
   `StreamRuntimeAttachmentService`
4. relaunches the last known cloud title or home console using the same bridge

Explicit exit follows a different path. `RenderSurfaceCoordinator.requestExit(...)`
disables diagnostics polling, hides the overlay, asks the controller to stop
streaming, exits stream priority mode, and dismisses the surface. Non-explicit
disappearance uses `handleDisappear(...)`, which performs the same teardown steps
without treating the disappearance as an already-confirmed user exit.

`StreamStopWorkflow` then performs the controller-side cleanup:

- stop overlay presentation refresh
- reset reconnect state
- clear achievement and artwork state
- detach runtime attachment
- disconnect the session
- exit priority mode

## Source Map

Use this map when you need the live code behind one part of the stream stack.

### App Target

- `Apps/Stratix/Sources/Stratix/Features/Streaming/StreamView.swift`
- `Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RenderSurfaceCoordinator.swift`
- `Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RendererAttachmentCoordinator.swift`
- `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImpl.swift`
- `Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplBridge.swift`

### StratixCore

- `Packages/StratixCore/Sources/StratixCore/StreamController.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamLaunchWorkflow.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamCloudLaunchWorkflow.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamHomeLaunchWorkflow.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamRuntimeAttachmentService.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamStopWorkflow.swift`
- `Packages/StratixCore/Sources/StratixCore/Streaming/StreamReconnectCoordinator.swift`

### StreamingCore

- `Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSession.swift`
- `Packages/StreamingCore/Sources/StreamingCore/Session/StreamingSessionFacade.swift`
- `Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingRuntime.swift`
- `Packages/StreamingCore/Sources/StreamingCore/Runtime/StreamingSessionRuntime.swift`
- `Packages/StreamingCore/Sources/StreamingCore/Channels/InputChannel.swift`
- `Packages/StreamingCore/Sources/StreamingCore/WebRTCBridge.swift`

### Related Docs

- [RUNTIME_FLOW.md](RUNTIME_FLOW.md)
- [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md)
- [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md)
- [WEBRTC_GUIDE.md](WEBRTC_GUIDE.md)
- [WEBRTC_CAPABILITIES.md](WEBRTC_CAPABILITIES.md)
