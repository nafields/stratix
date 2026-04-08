# Performance Guide

This guide covers how to measure and optimize Stratix performance — from startup time and library loading to streaming frame delivery and input latency.

**When to use this doc vs. TESTING.md:** [`TESTING.md`](TESTING.md) tells you which validation lane to run to prove correctness. This doc tells you how to measure whether something is *fast*. Use this when you are profiling, investigating a user-reported slowness, or working on the streaming renderer.

The target metrics below are the baselines the repo is designed around. If you are seeing numbers worse than these on a clean build, something may have regressed.

---

How to measure, understand, and optimize Stratix for low latency, high throughput, and responsive UI.

---

## Target Performance Metrics

| Metric | Target | Notes |
|--------|--------|-------|
| App startup time | < 2 s | Cold start on device with cached library |
| Sign-in flow | < 10 s | Device code + poll + XSTS + gsToken exchange |
| Stream connection time | < 10 s | 9-step sequence: SDP/ICE + WebRTC connect |
| Input latency (local) | < 20 ms | Controller → packet send (local processing only) |
| Input round-trip | < 100 ms | Controller → server → game response (network dependent) |
| First video frame | < 500 ms | After WebRTC connected state |
| Memory (idle, library) | < 100 MB | Library hydrated, no stream |
| Memory (streaming) | < 250 MB | Steady-state during 1080p 60 FPS stream |
| Memory (streaming + guide) | < 300 MB | Overlay visible |
| CPU (idle stream, steady state) | < 10% | Background frame decode only |

---

## Profiling Tools

### Xcode Instruments

Launch via **Product → Profile** (⌘I) or the `Stratix-Profile` or `Stratix-MetalProfile` scheme:

| Instrument | Use for |
|------------|---------|
| **System Trace** | CPU usage, thread scheduling, main-thread blocking |
| **Allocations** | Heap growth, object lifecycle, retain cycles |
| **Leaks** | Memory leaks — use after stream disconnect |
| **Time Profiler** | CPU hotspots in the call tree |
| **Metal GPU Debugger** | GPU frame capture for `MetalVideoRenderer` |
| **Core Animation** | View rendering, dropped frames, offscreen rendering |
| **Network** | HTTP request timing, DNS, TLS |

> Use the `Stratix-MetalProfile` scheme for GPU work — it enables Metal frame capture without other debug overhead.

### Console.app

Key log streams during performance analysis:

```bash
# Stream logs from a connected Apple TV:
xcrun devicectl device syslog --device <UDID> | grep -E "(\[AudioStats\]|\[InputChannel\]|\[VideoRenderer\]|\[Stream\])"

# Simulator:
log stream --predicate 'processImagePath contains "Stratix"' --level info
```

Key log patterns:

| Log pattern | What it tells you |
|-------------|-------------------|
| `[AudioStats] playoutRate=100%` | Audio pipeline healthy |
| `[AudioStats] playoutRate=50%` | Stereo/mono mismatch bug (see AUDIO_ARCHITECTURE.md §6) |
| `[AudioStats] throughput=48000/s (100.0%)` | CoreAudio I/O thread running at full speed |
| `[WebRTC][tvOS] playout PCM callback=...avgAbs=NNN` | Audio unit active; `avgAbs > 0` = non-silent |
| `[InputChannel] first binary input packet send` | Input pipeline confirmed live |
| `[StreamView] attaching video track handler` | Stream surface is reattaching the renderer to a live session |
| `[Stream] lifecycle: .connected` | WebRTC connected |

### WebRTC Stats HUD and Live Diagnostics Polling

Enable via the guide overlay → Diagnostics → "Show Stream Stats". The stats HUD reads from `StreamingStatsSnapshot` and displays in real-time:

| HUD field | Source | Meaning |
|-----------|--------|---------|
| Bitrate (kbps) | `videoBitrate` | Negotiated video bitrate |
| Frame rate | `framesPerSecond` | Current visible stream frame rate |
| RTT (ms) | `roundTripTime` | Server round-trip latency |
| Packet loss (%) | `packetsLost / packetsSent` | Network quality |
| Input / output resolution | Stream + renderer diagnostics | Current negotiated and processed resolution path |
| Upscaler / renderer | Active renderer path | `metalCAS`, `sampleBuffer`, or a renderer diagnostic mode |
| Render delay | Surface latency telemetry | Current render latency reported by the renderer surface model |
| Renderer diagnostics | Runtime and surface telemetry | Input flush rate, frame loss, video drops, rung failures, and similar live diagnostics when populated |

The important current behavior is that these stats are **not** polled forever in the background. The live repo enables diagnostics polling only while the overlay or HUD actually needs live stream data:

- `RenderSurfaceCoordinator.syncDiagnosticsPolling(...)` turns polling on when either the overlay or the HUD is visible
- `StreamingSessionStatsPoller` publishes one immediate snapshot and then continues on a 2-second cadence
- `StreamingSessionMetricsSupport` merges the raw bridge stats with runtime and renderer telemetry before publishing the visible snapshot

That merged snapshot is why the current HUD can represent more than just raw network transport. It also carries runtime dimensions, renderer mode, and input flush health.

### A Practical Profiling Loop

The current repo is easiest to profile if you treat a stream as a sequence of checkpoints rather than one monolithic "performance run":

1. Launch and browse.
2. Start a stream.
3. Wait for connected state.
4. Wait for first frame.
5. Open the overlay and HUD.
6. Dismiss them again.
7. Disconnect and confirm shell recovery.

That maps directly onto the live instrumentation model:

- app-shell and browse responsiveness are tracked through app-side performance logging
- startup and transport milestones flow through `StreamingSession`, `StreamingRuntime`, and `StreamMetricsPipeline`
- renderer attachment, first-frame, and mode changes are tracked separately from raw network stats
- audio health is tracked by its own counters and watchdog path instead of being inferred from video success

This matters because many regressions in the current app are phase-specific. A problem that appears only after the overlay opens is usually a HUD publication or main-actor overlay issue, not a generic “streaming is slow” problem.

---

## Key Performance Bottlenecks

### 1. Input Latency — 125 Hz Loop

**Location:** `Packages/StreamingCore/Sources/StreamingCore/Channels/InputChannel.swift`

The current input channel runs a `Task` polling at **125 Hz** with an **8 ms** loop interval. This is the live cadence in the repo and is the source of truth over older docs that described a `250 Hz / 4 ms` loop.

Local input processing latency should still remain <10 ms in the steady-state path because the runtime coalesces latest input, warns on delayed sends, and keeps the loop light.

**Measurement:**
1. Enable verbose input logs: `debug.input.verbose_logs = true` in UserDefaults
2. Check Console.app for `[InputChannel]` send timestamps
3. Compare against controller event timestamps

**If polling loop is delayed:**
- Check for any `await` call or dispatch hop that causes the loop to miss the current 8 ms cadence
- Verify `InputChannel` is not starved by main-thread work
- `flush()` returning `nil` means no input — confirm controller is connected
- Check warning logs for send-duration, scheduler-gap, and coalescing warnings before assuming the problem is network-only

### 2. WebRTC Connection Time

The 9-step `StreamingSession.connect()` sequence typically completes in 5–10 seconds. `StreamMetricsPipeline` records milestones with timestamps — export the metrics via the preview export tool to measure each step.

**Typical timing breakdown:**

```
Step 1: POST /v2/sessions/{type}             ~300–500 ms
Step 2: Poll for ReadyToConnect              ~1–3 s   (server queue time)
Step 3: MSAL auth (xCloud only)             ~200 ms
Step 4: Poll for Provisioned                ~500–1500 ms
Step 5–6: WebRTC offer + SDP exchange       ~500–1000 ms
Step 7: ICE exchange                        ~500 ms
Step 8–9: Wait for connected + channels     <1 s
Total                                        ~5–10 s
```

**What drives the variance:**
- Step 2 (server queue) is the largest variable — can be 10s+ during peak load
- Network RTT to Xbox servers affects steps 1–7
- ICE gather timeout is capped at 5 seconds — on fast networks, all candidates arrive in <1 s

**Optimization opportunities:**
- Pre-warm the session by starting earlier in the launch flow (before the loading animation)
- LPT fetch (xCloud) can be parallelized with the `Provisioned` poll in step 4

### 3. Memory Usage

Expected steady-state ranges:

| State | Expected memory |
|-------|-----------------|
| Cold launch (before library load) | ~50 MB |
| Library hydrated, browsing | ~100 MB |
| Stream connected, 1080p 60 FPS | ~220 MB |
| Stream connected + guide open | ~280 MB |

**If memory grows beyond these ranges:**
1. Profile with Xcode Instruments → Allocations
2. Check for growing `RTCVideoFrame` allocations — video frame buffers not being returned to pool
3. Verify `StreamingSession.disconnect()` is called and frees all resources
4. Check for closures capturing large objects (artwork cache, library sections)

### 4. Rendering Frame Rate

Two renderer paths are available:

| Path | Setting | When used |
|------|---------|-----------|
| `MetalVideoRenderer` (CAS) | `guide.renderer_mode = "metalCAS"` or `"auto"` with sharpness/saturation active | Custom Metal CAS path with image processing |
| `SampleBufferDisplayLayer` | `guide.renderer_mode = "sampleBuffer"` or `"auto"` at neutral settings | Default `AVSampleBufferDisplayLayer` |

**Performance comparison:**
- `SampleBufferDisplayLayer` has lower CPU/GPU overhead — best for battery life
- `MetalVideoRenderer` adds CAS (Contrast Adaptive Sharpening) and saturation processing — small GPU cost but higher perceived quality

**If frames are dropping:**
1. Switch renderer to `sampleBuffer` via guide → Diagnostics to isolate whether it's a Metal rendering issue
2. Check Instruments → Metal GPU Debugger for GPU utilization
3. Lower resolution: 1080p → 720p reduces decoder load
4. Check device temperature — Apple TV throttles CPU/GPU when hot

**Current repo-specific telemetry to watch:**
- `RenderSurfaceCoordinator` records the first-frame milestone separately from connection state
- `RendererAttachmentCoordinator` reports renderer mode changes, candidate failures, and decode failures
- the merged `StreamingStatsSnapshot` includes negotiated dimensions, input flush cadence, and renderer telemetry in addition to raw WebRTC stats

### 5. First-Frame Regressions

The current repo treats "connected" and "first frame" as distinct milestones for a reason. Several failure classes can happen after the peer connection is technically up:

- the video track arrives late
- the renderer attaches to the wrong or stale session identity
- the renderer candidate is chosen but cannot draw
- the overlay/HUD path changes UI state before the first drawable frame arrives

In practice:

- if `.connected` happens quickly but the screen stays black, inspect renderer-attachment and first-frame telemetry before blaming signaling
- if first frame only appears after some extra UI event, inspect `RenderSurfaceCoordinator` session attachment and diagnostics publication
- if first frame appears and then disappears on shell/route changes, inspect duplicate attach or stale-session handling

The log line `[StreamView] attaching video track handler` is useful because it tells you the stream surface is wiring itself to a real active session, not just that the transport layer says “connected.”

---

## Network Performance

### Bandwidth Requirements

| Resolution | Target bitrate |
|------------|---------------|
| 720p 30 FPS | ~5 Mbps |
| 1080p 30 FPS | ~10 Mbps |
| 1080p 60 FPS | ~15–20 Mbps |

### Reading WebRTC Stats

`StreamingStatsSnapshot` (available via `WebRTCBridge.collectStats()`) surfaces:

```swift
// Key fields in StreamingStatsSnapshot:
snapshot.videoBitrate        // kbps — actual negotiated bitrate
snapshot.framesDecoded       // frames/sec from decoder
snapshot.packetsLost         // cumulative lost packets
snapshot.roundTripTime       // ms — RTT to server
snapshot.jitterBufferDelay   // ms — video jitter buffer state
```

### Interpreting RTT

| RTT | Network quality | Stream quality impact |
|-----|-----------------|-----------------------|
| < 30 ms | Excellent | Minimal input lag |
| 30–80 ms | Good | Acceptable input lag |
| 80–150 ms | Fair | Noticeable input lag |
| > 150 ms | Poor | Input feels sluggish; reduce resolution |

### Interpreting Packet Loss

| Packet loss | Impact |
|-------------|--------|
| 0% | No impact |
| < 0.5% | Minimal — NetEQ handles naturally |
| 0.5–2% | Occasional video artifacts, possible audio stutter |
| > 2% | Significant degradation — switch to wired network |

---

## Code Optimization Patterns

### Async/Await Over Closures

```swift
// ✗ Closure-based — hard to cancel, error-prone
client.fetchTitles { result in
    switch result {
    case .success(let titles): // ...
    case .failure(let error): // ...
    }
}

// ✓ Async/await — compiler enforces error handling, easy to cancel
do {
    let titles = try await client.fetchTitles()
} catch {
    // handle error
}
```

### Task Cancellation

Every `Task` in the streaming path must check `Task.isCancelled` or use structured concurrency:

```swift
// InputChannel polling loop:
pollingTask = Task { [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 8_000_000)  // 8 ms / 125 Hz
        guard let self, let packet = self.queue.flush() else { continue }
        try? await self.bridge?.send(channelKind: .input, data: packet)
    }
}

// Always cancel on cleanup:
func cancelInputChannel() {
    pollingTask?.cancel()
    pollingTask = nil
}
```

### Focus Update Debouncing

tvOS D-pad can generate rapid focus events. Debounce expensive operations:

```swift
private var focusUpdateTask: Task<Void, Never>?

func handleFocusChanged(to id: String) {
    focusUpdateTask?.cancel()
    focusUpdateTask = Task { @MainActor in
        // StratixConstants.UI.focusSettleDebounceNanoseconds = 60_000_000 (60 ms)
        try? await Task.sleep(nanoseconds: StratixConstants.UI.focusSettleDebounceNanoseconds)
        guard !Task.isCancelled else { return }
        updateArtwork(for: id)
    }
}
```

### Snapshot Pattern for Cross-Actor State Reads

`@Observable` controllers must not be read from off-main-actor code. Use snapshot functions:

```swift
// StratixCore controllers provide snapshot functions:
let config = settingsStore.snapshotStreamConfig()  // Returns Sendable StreamingConfig
// config is a pure value type — safe to pass across actor boundaries
```

### Avoid Main-Thread I/O

Never do file I/O, network decoding, or heavy computation on the main actor:

```swift
// ✗ Blocks main actor:
@MainActor
func loadTitles() {
    let data = try! Data(contentsOf: cacheURL)  // BLOCKS main thread
}

// ✓ Off-main-actor I/O:
@MainActor
func loadTitles() {
    Task {
        let data = try await readCacheData()  // Runs on background executor
        await MainActor.run { self.titles = decode(data) }
    }
}
```

### Recognizing Common Regression Shapes

The same failure signatures tend to recur in this repo. Calling them out explicitly makes triage faster:

| Symptom | Most likely area | Why |
|---------|------------------|-----|
| Stream connects, video renders, but audio is silent on device | tvOS WebRTC audio path | Usually a tvOS audio/bootstrap/reconcile issue, not signaling |
| Audio gradually drifts or feels late while video stays healthy | audio watchdog / resync path | The live repo has an explicit tvOS resync policy, so slow A/V drift is usually an audio-runtime issue, not a broad transport collapse |
| Input feels delayed while FPS looks normal | `InputChannel` cadence or send pressure | Input transport can regress independently from decode/render |
| Overlay open causes hitching | diagnostics polling or overlay-side main-actor work | Polling is demand-driven, so this transition is a common regression edge |
| Simulator-only failure on x86_64 | unsupported WebRTC simulator path | The active repo only treats arm64 simulator as a supported WebRTC path |
| Memory climbs after disconnect/reconnect cycles | teardown / retained track / renderer cleanup | Usually resource release, not expected steady-state growth |

---

## Optimization Checklist

Before shipping a change that touches the streaming or input path:

- [ ] Input latency: confirm `[InputChannel]` packets are being sent at the current 125 Hz cadence in Console.app
- [ ] Connection time: measure from stream launch tap to `[Stream] lifecycle: .connected` log
- [ ] First frame: verify first video frame arrives quickly after the connection reaches a usable state
- [ ] Memory: profile with Instruments → Allocations after a full connect/stream/disconnect cycle
- [ ] No frame drops: confirm 60 FPS in the stats HUD on device at 1080p
- [ ] Audio health: `[AudioStats] playoutRate=100%` during streaming
- [ ] Diagnostics gating: verify stats polling disables when the overlay and HUD are both off
- [ ] No main-thread blocking: Instruments → System Trace shows no >16 ms gaps on main thread
- [ ] Task cancellation: all streaming Tasks are cancelled on `disconnect()`
- [ ] No retain cycles: Instruments → Leaks shows no growing leaks after disconnect

---

## Related Docs

- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md) — the 9-step connection sequence
- [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md) — AudioStats interpretation
- [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md) — current 125 Hz input loop architecture
- [TESTING.md](TESTING.md) — performance test scheme (`Stratix-Perf`)
- [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md) — Metal renderer patches
