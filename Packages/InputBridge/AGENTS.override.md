# AGENTS.override.md — Packages/InputBridge/

InputBridge handles gamepad input capture and queuing for transmission to the streaming session.

**Modernization contract reference:** If input-bridge work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Files

| File | Role |
|------|------|
| `GamepadHandler.swift` | Captures GCController input and translates to input packets. |
| `InputPacket.swift` | Value type representing a single input snapshot. |
| `InputQueue.swift` | FIFO queue of input packets for transmission. |

---

## Tests

`Tests/InputBridgeTests/`:
- `ChordRecognizerTests.swift` — button chord detection
- `GamepadHandlerTests.swift` — input capture
- `InputPacketTests.swift` — packet serialization

---

## Rules

1. No UIKit, no SwiftUI. Input capture is GCController-based (GameController framework).
2. `InputQueue` must be concurrency-safe. If it holds mutable state accessed from both the input capture thread and the stream transmission thread, it must be an actor.
3. `InputPacket` must be `Sendable` (it crosses thread boundaries during transmission).
4. Do not add streaming logic here. InputBridge produces packets; StreamingCore consumes them via the input channel.
