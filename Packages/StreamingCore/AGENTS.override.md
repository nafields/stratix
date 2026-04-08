# AGENTS.override.md — Packages/StreamingCore/

StreamingCore owns the WebRTC session abstraction, data channel protocols, SDP/ICE processing, and stream lifecycle management. It does not contain Metal, UIKit, or WebRTC binary imports — those live in `Integration/WebRTC/` in the app target.

**Modernization contract reference:** For modernization work in this package, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with the modernization plan, monolith breakdown, and file matrix.

---

## What lives here

```
StreamingCore/Sources/StreamingCore/
├── Session/           ← StreamingSession, StreamingSessionFacade
├── Runtime/           ← StreamingRuntime, delegate protocols
├── Channels/          ← Chat, control, input, message channel implementations
├── Rendering/         ← Telemetry support (no Metal)
├── Metrics/           ← Session-level metrics
├── Replay/            ← Track replay for stream state restoration
├── WebRTCBridge.swift ← Protocol defining the WebRTC client interface
├── SDPProcessor.swift ← SDP offer/answer processing
└── ICEProcessor.swift ← ICE candidate processing
```

---

## WebRTCBridge.swift — the key seam

`WebRTCBridge.swift` defines the protocol interface that `Integration/WebRTC/WebRTCClientImpl` conforms to in the app target. This is the architectural seam that allows StreamingCore to be tested and used without the WebRTC binary.

Do not add WebRTC framework imports to StreamingCore. The protocol must remain binary-free.

---

## Rules

1. No `import` of WebRTC framework types. Use only the protocol interface defined in `WebRTCBridge.swift`.
2. No Metal, no AVFoundation rendering types. Rendering telemetry (frame counts, latency) is fine; rendering implementation is not.
3. `SDPProcessor` and `ICEProcessor` are pure transformation functions — no async, no state. Keep them that way.
4. Channel implementations (`Channels/`) handle data channel message encoding/decoding. They must be `Sendable`-safe — data channels fire on WebRTC's internal thread pool.
5. Swift Async Algorithms (Execution Contract): the stream event pipeline in `Runtime/` is a candidate for replacement with a typed async sequence pipeline using merge/debounce operators.

---

## Tests

Package-level tests in `Tests/StreamingCoreTests/` cover: SDP processing, ICE processing, channel encode/decode, session lifecycle state machines.
