# Controller Input Pipeline

When you press a button on a controller while streaming a game on Stratix, a lot has to happen very quickly. The button press is captured from GameController, normalized into a `GamepadInputFrame`, queued and serialized into a binary packet, and sent over a WebRTC data channel to the Xbox server — all within a 8ms window at 125 Hz.

This document explains how that pipeline works and where each piece lives in the codebase. If you are debugging input problems (buttons not responding, wrong deadzone behavior, input not registering), [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) has the specific failure modes. If you want to understand how `InputBridge` fits into the broader package architecture, [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md) has the ownership context.

---

This document describes the live controller-input path in Stratix: how Apple TV
controller events become `GamepadInputFrame` values, how those frames are queued
and serialized, and how they are transported to the active stream session.

Older docs in this repo flattened these responsibilities and documented stale
transport details. The current runtime is split across three layers:

- `StratixCore` owns controller observation, shortcut interpretation, and session
  binding
- `InputBridge` owns queueing, frame shaping, and binary packet encoding
- `StreamingCore` owns the input data channel and its transport cadence

## Input Flow At A Glance

```text
Physical controller / GameController event
        │
        ▼
InputController.attachController(...)
        │
        ├── reads current controller state
        ├── applies hold-combo / overlay shortcut rules
        ├── asks GamepadHandler to build a GamepadInputFrame
        └── writes frame into InputQueue
                │
                ▼
InputChannel.onOpen()
        │
        ├── sends client metadata packet once
        └── starts 125 Hz transport loop
                │
                ▼
InputQueue.flush()
        │
        ├── coalesced live gamepad frames
        ├── injected one-shot frames
        └── optional timing metadata
                │
                ▼
InputPacket.gamepadPacket(...)
        │
        ▼
WebRTCBridge.send(channelKind: .input, data:)
        │
        ▼
Xbox streaming service
```

The key corrections relative to older docs are:

- the transport loop is `125 Hz`, not `60 Hz` and not `250 Hz`
- controller observation is owned by `InputController`, not by `AppCoordinator`
- the outbound packet format is variable-sized, not a fixed old 82-byte shape
- shell shortcuts are interpreted partly above raw input transport, not only as a
  low-level button-to-button mapping problem

## Ownership

### StratixCore

`Packages/StratixCore/Sources/StratixCore/InputController.swift`

Owns:

- observing `GCController`
- binding controller state to the active session’s `InputQueue`
- disabling conflicting tvOS system gestures
- interpreting hold commands and overlay shortcuts
- routing vibration back to physical controllers
- injecting synthetic pause and neutral frames

### InputBridge

Primary files:

- `Packages/InputBridge/Sources/InputBridge/GamepadHandler.swift`
- `Packages/InputBridge/Sources/InputBridge/InputQueue.swift`
- `Packages/InputBridge/Sources/InputBridge/InputPacket.swift`

Owns:

- converting GameController state into `GamepadInputFrame`
- controller settings such as deadzone, invert Y, A/B swap, and trigger handling
- queue coalescing rules
- binary packet building and parsing

### StreamingCore

Primary file:

- `Packages/StreamingCore/Sources/StreamingCore/Channels/InputChannel.swift`

Owns:

- the WebRTC input data channel
- initial client metadata send
- the `125 Hz` transport loop
- inbound vibration and server-metadata parsing
- transport telemetry back to the stream runtime

This split matters because the controller pipeline is not just “read input and send
bytes.” It has separate Apple-platform, protocol, and transport concerns.

## Session Binding

The active `InputQueue` belongs to the active streaming session, not to the input
controller itself.

When a new session is attached, `StreamRuntimeAttachmentService` asks the input
environment to:

- `setupControllerObservation(session.inputQueueRef)`
- install vibration routing

That means `InputController` does not own its own long-lived queue. It binds to the
queue exposed by the current `StreamingSessionFacade`, and it can clear that binding
when streaming stops or sign-out happens.

This is why `InputController.clearStreamingInputBindings()` and
`resetForSignOut()` are important runtime operations. The input controller is a
bridge into the active session, not a permanent transport owner.

## Controller Observation

`InputController.setupControllerObservation(inputQueue:)` does the live controller
registration work.

It:

1. stores the active `InputQueue`
2. immediately attaches all already-connected extended controllers
3. installs `GCControllerDidConnect` and `GCControllerDidDisconnect` observers once

When a controller connects, `attachController(_:)`:

- ignores non-extended profiles for the main gameplay path
- disables tvOS system gestures where possible
- creates a `GamepadHandler`
- stores per-controller state keyed by `ObjectIdentifier`
- installs a `valueChangedHandler`
- tells the current streaming session that gamepad index `0` is connected

When a controller disconnects:

- the handler and combo interpreter are removed
- startup haptics probe state is cleared for that controller
- the session is told whether any extended controller remains connected

So the controller layer is aware of connection topology, but it is still the
session/runtime layer that ultimately transports the resulting input state.

## GamepadHandler: Turning GameController State Into Frames

`GamepadHandler.readFrame(from:settings:)` converts a `GCExtendedGamepad` snapshot
into a `GamepadInputFrame`.

The output model is defined in `StratixModels`:

- `GamepadButtons`
- `GamepadInputFrame`
- `ControllerSettings`

### Button Mapping

The frame builder maps face buttons, shoulders, thumbstick clicks, D-pad, Menu, and
Options into the Xbox-style `GamepadButtons` bitset.

Important button facts:

- Menu maps to `.menu`
- Options maps to `.view`
- the Xbox/Nexus button has its own bit in the model
- shoulders and stick-click buttons are first-class values, not custom overlays

The low-level frame builder still produces ordinary button state. Higher-level
shortcut behavior is layered on top by `InputController`.

### A/B Swap

`ControllerSettings.swapAB` swaps face-button output after the raw button read. This
is a transport-facing preference, not just a UI label change.

### Trigger Interpretation

The live trigger pipeline is richer than older docs suggested. It supports three
interpretation modes:

- `auto`
- `digitalFallback`
- `analogOnly`

`auto` mode learns whether a controller behaves like a real analog trigger or like
a digital trigger that only reports `isPressed`. That is important for controllers
whose hardware or driver does not expose meaningful analog travel.

After trigger interpretation, the values are scaled by `triggerSensitivity`. Lower
values make the triggers feel more hair-trigger-like by mapping a smaller physical
travel range to full protocol output.

### Thumbsticks, Deadzone, And Y Normalization

Stick input is shaped by:

- radial deadzone
- optional Y inversion
- browser-style Y normalization

The normalization order matters:

1. apply deadzone
2. flip GameController’s Y axis into the convention expected by the stream protocol
3. apply optional user invert-Y preference

That keeps the protocol aligned with the service expectations while still letting
the user choose an inverted camera/control scheme.

### Idle Frames

`GamepadHandler.idleFrame()` is used when the controller layer intentionally wants
to suppress gameplay input while still emitting a neutral state to the session. That
behavior shows up in overlay handling and hold-combo suppression.

## InputController Shortcut And Overlay Rules

The controller layer does more than pass raw gamepad state through.

### Hold Commands

`InputController` uses `HoldComboCommandInterpreter` for long-hold commands:

- Start + Select hold triggers a synthetic Nexus tap
- L3 + R3 hold toggles the stream overlay

These commands intentionally sit above raw button mapping. The app does not want
every simultaneous press to leak straight into gameplay when the intent is clearly a
shell or guide command.

### Chord Actions

`InputController` also uses `ChordRecognizer` for immediate chord-driven actions.
The currently active built-in chord is:

- `LB + RB` → toggle stats HUD

That action is evaluated against the current `GamepadInputFrame` before the frame is
enqueued for normal gameplay transport.

### Overlay-Specific Rules

When the stream overlay is visible, the controller layer changes behavior:

- `A` requests stream disconnect
- `B` closes the overlay
- gameplay input is suppressed by enqueueing an idle frame instead of the live frame

This is a deliberate separation of concerns. The overlay is not just a visual layer.
While it is active, controller input is temporarily treated as shell control rather
than gameplay input.

### Synthetic Injection Helpers

The input controller also owns synthetic frame helpers such as:

- `injectNeutralGamepadFrame(...)`
- `injectPauseMenuTap(...)`

Those helpers enqueue frames directly into the active queue so the app can:

- release held gameplay input safely
- send a short Menu tap for in-game pause

These are transport-visible actions, not just UI state changes.

## InputQueue: Coalescing And Flush Boundaries

`InputQueue` is the bridge between controller sampling and transport cadence.

It stores:

- coalesced live gamepad frames
- injected gamepad frames
- timing metadata frames
- the monotonically increasing outbound sequence number

### Coalesced Live Frames

`enqueueGamepadFrame(_:)` keeps only the most recent frame per `gamepadIndex`. That
matches the poll-style model used by the JS client lineage and prevents a flood of
obsolete intermediate frames from piling up between transport ticks.

### Injected Frames

`enqueueInjectedGamepadFrame(_:)` does not coalesce. These frames are deliberately
one-shot control actions such as pause taps or neutral releases and must be emitted
in the order the app requested them.

### Timing Metadata

`enqueueTimingFrame(_:)` lets the renderer/runtime piggyback client-side frame timing
information onto the next outbound input packet. This is one of the reasons the
outbound packet format is not a single old fixed layout anymore.

### Flush Behavior

`flush()`:

1. advances the outbound sequence number
2. captures current injected frames, coalesced live frames, and timing frames
3. clears the pending state
4. returns `nil` when nothing is pending
5. otherwise builds a packet through `InputPacket.gamepadPacket(...)`

The queue does not send anything itself. It only produces the next binary payload
for the transport layer.

## InputChannel: 125 Hz Transport

`InputChannel` owns the WebRTC-side input transport.

The live loop cadence is:

- `125 Hz`
- `8 ms` sleep interval

This is explicitly documented in the code and is part of the current performance
tradeoff. It is fast enough for controller sampling while reducing scheduler
pressure relative to the older more aggressive loop assumptions.

### On Open

When the input data channel becomes active, `onOpen()`:

1. ensures startup is only performed once for the current lifecycle generation
2. sends a client metadata packet declaring `maxTouchPoints = 1`
3. marks the channel running
4. starts the loop task

### During The Loop

Each loop tick:

1. waits `8 ms`
2. records wake telemetry
3. calls `queue.flush()`
4. if a packet exists, schedules or performs the send
5. emits send-health telemetry periodically

So the input runtime is not a naive “flush then send” timer. It also tracks:

- scheduler stalls
- send duration
- send completion delay
- effective flush frequency
- jitter

That telemetry is surfaced back through the stream runtime and eventually the
session-facing stats path.

### Inbound Messages

The input channel also parses two important inbound report types:

- vibration (`128`)
- server metadata (`16`)

Vibration is routed back to the app-owned handler chain. Server metadata reports
the negotiated video dimensions and is used by the stream runtime for snapshot and
message-channel dimension updates.

## Packet Format

The current packet format is variable-sized and report-type-driven.

### Header

Every outbound packet starts with a 14-byte header:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 2 | `ReportType` bitmask (`UInt16`, little endian) |
| 2 | 4 | sequence number (`UInt32`, little endian) |
| 6 | 8 | timestamp in uptime milliseconds (`Double`, little endian) |

The timestamp is based on system uptime, not wall-clock Unix time.

### Report Types

The current bitmask includes values such as:

- `.metadata`
- `.gamepad`
- `.clientMetadata`
- `.serverMetadata`
- `.vibration`
- `.unreliableInput`
- `.unreliableAck`

Not every value is used on every packet, but the protocol is explicitly structured
to support combined report payloads.

### Client Metadata Packet

The initial metadata packet sent on channel open is small:

- header
- one byte for `maxTouchPoints`

That packet is the runtime’s declaration of client input capability.

### Gamepad Packet

`InputPacket.gamepadPacket(...)` can contain:

- metadata payload
- gamepad payload
- or both

Gamepad payload structure:

- 1 byte frame count
- 23 bytes per `GamepadInputFrame`

Per-frame values include:

- `gamepadIndex`
- button bitmask
- left/right stick axes as `Int16`
- left/right triggers as `UInt16`
- physicality markers used by the protocol

### Metadata Payload

Timing metadata is encoded separately:

- 1 byte count
- 28 bytes per timing frame

That payload carries renderer/runtime timing values such as first packet arrival,
decode, and render timestamps. It is not old padding or reserved junk. It is a live
part of the protocol surface.

### Inbound Reports

The current parser also understands:

- vibration reports
- server metadata reports

So `InputPacket` is not only an outbound encoder. It is also part of the inbound
control-feedback loop.

## Vibration And Haptics

Vibration flows the opposite direction:

```text
Server vibration report
        │
        ▼
InputChannel.onMessage(...)
        │
        ▼
InputPacket.parseVibration(...)
        │
        ▼
Streaming session vibration handler
        │
        ▼
InputController.routeVibration(...)
        │
        ▼
GamepadHandler.sendHaptics(...)
```

`GamepadHandler` keeps per-locality haptic engines alive so repeated pulses are more
reliable on supported hardware. `InputController` then applies user settings such as
vibration enablement and intensity before routing the report across all active
handlers.

The app also supports a startup haptics probe for diagnostics. When enabled, the
controller layer sends two short pulses to newly attached controllers so hardware
support can be verified early in a session.

## Siri Remote And Compatibility Notes

`GamepadHandler` still includes `readFrameFromMicroGamepad(_:)`, which translates
the Siri Remote micro gamepad into a minimal frame. That helper exists for
compatibility and experimentation, but the primary live stream path is based on
extended controllers observed through `GCController.extendedGamepad`.

For the main experience, the important compatibility work today is:

- trigger auto/fallback behavior
- button remapping via settings
- idle-frame suppression during overlay control
- startup haptics probing and vibration routing

## Source Map

- `Packages/StratixCore/Sources/StratixCore/InputController.swift`
- `Packages/InputBridge/Sources/InputBridge/GamepadHandler.swift`
- `Packages/InputBridge/Sources/InputBridge/InputQueue.swift`
- `Packages/InputBridge/Sources/InputBridge/InputPacket.swift`
- `Packages/StreamingCore/Sources/StreamingCore/Channels/InputChannel.swift`
- `Packages/StratixModels/Sources/StratixModels/Input/InputModels.swift`

## Related Docs

- [RUNTIME_FLOW.md](RUNTIME_FLOW.md)
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [PERFORMANCE.md](PERFORMANCE.md)
