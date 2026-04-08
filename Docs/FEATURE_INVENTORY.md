# Feature Inventory

> Current feature matrix for the live Stratix repo. This document is intentionally product-facing and capability-focused: it describes what is actually present in `Apps/Stratix/` and the supporting packages today, where behavior is partial, and which high-value items are still absent.

> For architecture and subsystem boundaries, start with [ARCHITECTURE.md](ARCHITECTURE.md), [UI_ARCHITECTURE.md](UI_ARCHITECTURE.md), [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md), and [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md). This file answers a different question: “what can the current product and repo actually do?”

---

## Table of Contents

- [Status Values](#status-values)
- [Authentication](#authentication)
- [Cloud Library and Browse](#cloud-library-and-browse)
- [Streaming](#streaming)
- [Controller Input](#controller-input)
- [Audio](#audio)
- [Video Rendering](#video-rendering)
- [UI and Navigation](#ui-and-navigation)
- [Xbox Social Features](#xbox-social-features)
- [In-Stream Guide](#in-stream-guide)
- [Settings and Configuration](#settings-and-configuration)
- [Diagnostics](#diagnostics)
- [Better xCloud-Inspired and Protocol-Adjacent Support](#better-xcloud-inspired-and-protocol-adjacent-support)
- [xHome Local Console Streaming](#xhome-local-console-streaming)
- [Build and Development](#build-and-development)
- [Known Open Follow-Up](#known-open-follow-up)
- [Not Started Priority Candidates](#not-started-priority-candidates)

---

## Status Values

- `Implemented`: present in the live tree and wired into a real user or operator path
- `Partial`: present, but with a known limitation, reduced scope, or incomplete UX surfacing
- `Not Started`: intentionally absent from the live product

This inventory is intentionally stricter than a marketing feature list. A capability is only marked `Implemented` here when the live repo contains:

- the model and runtime support
- the user- or operator-facing entry point
- enough surrounding behavior that the feature is meaningfully usable in the current product

That is why some areas stay `Partial` even when lower-level API work already exists. Queue wait-time support is the clearest example: the API path and model are real, but the polished user-facing launch surface is still incomplete.

---

## Authentication

Authentication is fully based on Microsoft device-code sign-in and Xbox token exchange. The repo does not treat sign-in as a one-time onboarding hack; it has a real token lifecycle in `XCloudAPI`, persistent storage, refresh behavior before launch, and explicit sign-out.

In practical terms, the live auth stack is a chain rather than a single login token:

- device-code approval yields Microsoft account credentials
- refresh-capable Microsoft auth is used to derive Xbox-facing credentials
- Xbox user / XSTS / stream-facing tokens are refreshed as needed for cloud launch and supporting web APIs

That layered posture matters because the repo uses Xbox credentials for more than just "start stream." The same auth surface also underpins profile, presence, social, achievements, and library-refresh behavior.

| Feature | Status | Notes |
|---------|--------|-------|
| Microsoft device-code sign-in | Implemented | Full device-code flow is present in the signed-out shell. |
| Token refresh before launch | Implemented | Stream launch refreshes auth state before continuing rather than trusting stale cached stream tokens. |
| Secure token persistence | Implemented | Token persistence lives in `XCloudAPI/Auth/TokenStore.swift`. |
| Legacy-token migration | Implemented | `TokenStore` migrates older `greenlight.*` storage keys forward to the current `stratix.*` family. |
| Sign out | Implemented | Clears auth state and returns the app to the signed-out flow. |
| Xbox web credentials | Implemented | The repo supports Xbox web credentials for profile, presence, social, and achievements APIs, not just cloud-stream launch. |
| Multi-account support | Not Started | Current product flow assumes one active Microsoft/Xbox account at a time. |

---

## Cloud Library and Browse

The CloudLibrary feature is more than a static catalog grid. The live repo includes home rails, full-library browsing, search, title detail, image caching, route-level presentation, and hydration persistence. The app-local `Data/CloudLibrary/` layer keeps data shaping pure and testable while `StratixCore` owns side effects and persistence.

| Feature | Status | Notes |
|---------|--------|-------|
| Cloud library fetch | Implemented | The catalog and entitlement-driven browse content are present. |
| Home rails | Implemented | Home route renders categorized rails for recent, curated, and library-derived surfaces. |
| Full library grid | Implemented | A dedicated library route exists for broad title browsing. |
| Search | Implemented | Search route supports query-driven filtering across the live library model. |
| Title detail screen | Implemented | Detail route includes media projection, description, metadata, and launch actions. |
| Artwork loading | Implemented | Shared image pipeline loads and caches artwork for browse, detail, and shell contexts. |
| Artwork caching | Implemented | The repo has a real shared artwork pipeline rather than one-off `AsyncImage` usage everywhere. |
| Bounded artwork prefetch | Implemented | Prefetch behavior exists to warm likely-nearby browse art instead of waiting for every focus move. |
| Hydration persistence | Implemented | Library hydration metadata and persistence coordination live in `StratixCore`. |
| Status and error views | Implemented | Loading, error, and empty-state surfaces are part of the live shell. |
| Quick-resume style surfacing | Implemented | The shell includes “continue”/recent-title affordances rather than treating every launch as a cold browse action. |
| Focus-driven browse state | Implemented | Focus, route, and presentation state are all first-class in the current CloudLibrary model. |

---

## Streaming

Streaming is the repo’s main product value. The current codebase includes cloud-stream startup, xHome startup, signaling, renderer attachment, stream stop/recovery, shell restoration, and stream diagnostics. xCloud is the primary path and the most battle-tested one. xHome exists as a real launch path, but some surrounding UX and metadata surfaces are still narrower than the cloud path.

One current-repo detail worth keeping explicit: cloud launch is deliberately conservative about auth freshness. The app refreshes stream-facing auth before launch instead of trusting old cached cloud credentials, which is one reason the launch path is more reliable than a simplistic “reuse whatever token is lying around” design.

| Feature | Status | Notes |
|---------|--------|-------|
| xCloud session creation | Implemented | Full create → provision → connect → stream → disconnect path is present. |
| WebRTC offer/answer exchange | Implemented | SDP signaling is part of the live stream runtime. |
| ICE candidate exchange | Implemented | ICE exchange and candidate handling are present in the runtime. |
| Peer-connection establishment | Implemented | The app uses a real `RTCPeerConnection` bridge behind the app-owned WebRTC boundary. |
| Stream start from browse/detail surfaces | Implemented | Launch actions in the library experience feed the real stream startup workflows. |
| Clean disconnect | Implemented | Disconnect and shell recovery are explicit parts of the live runtime path. |
| Session keepalive | Implemented | Keepalive behavior is part of the stream-session management layer. |
| xHome launch flow | Implemented | The repo contains home-console streaming support in addition to xCloud. |
| Auto-reconnect | Partial | Recovery exists, but reconnect is still more conservative than a true seamless session resume. |
| Queue wait-time fetch | Partial | API and model support exist, but the wait-time number is not yet surfaced as a polished user-facing launch screen element. |
| Region override | Partial | Region override exists in current settings and config surfaces, but the UX is still simpler than a full server-driven region picker. |
| Multiple concurrent streams | Not Started | The live product supports one active stream at a time. |

---

## Controller Input

Controller support is not just a thin GameController wrapper. The repo has a dedicated `InputBridge` package, packed binary input packets, queueing and coalescing, cadence diagnostics, vibration handling, and user-facing controller tuning settings.

| Feature | Status | Notes |
|---------|--------|-------|
| Standard controller input | Implemented | `InputBridge` owns capture, queueing, and packet serialization. |
| Binary input protocol | Implemented | Gamepad frames are encoded in the packed binary format used by the live stream runtime. |
| High-frequency input transport | Implemented | Current transport cadence is `125 Hz` with an `8 ms` loop interval. |
| Shell navigation from controller input | Implemented | Controller focus/navigation works throughout the app shell, not only during gameplay. |
| Siri Remote fallback navigation | Implemented | The app remains navigable on Apple TV without a gamepad. |
| Haptics / vibration routing | Implemented | Runtime routes server vibration reports back to supported controllers. |
| Deadzone tuning | Implemented | Deadzone is user-configurable and persisted in the shared settings model. |
| Trigger sensitivity tuning | Implemented | Trigger sensitivity is a live user-facing setting. |
| Trigger interpretation modes | Implemented | Trigger handling can be configured for compatibility or analog-preferred behavior. |
| Invert Y | Implemented | User-configurable and persisted. |
| A/B swap | Implemented | Alternative confirm/cancel layout is exposed to the user. |
| Neutral frame injection around overlay transitions | Implemented | Input policy explicitly prevents stuck-button behavior during overlay transitions. |
| Guide / hold command support | Implemented | The current input policy includes explicit hold-command behavior such as Start+Select hold → Nexus tap and L3+R3 hold → guide overlay toggle. |
| Multi-controller product flow | Partial | The lower-level stack is not the main blocker, but the product still behaves as a one-controller-first experience. |
| Button remapping | Not Started | No general-purpose remap model or UI exists yet. |
| Keyboard and mouse gameplay input | Not Started | Not exposed as a productized streaming feature today. |

---

## Audio

Audio support on tvOS is a first-class engineering area in this repo. The live tree includes a patched WebRTC build, playback-focused audio-session behavior, stereo preference support, audio boost, audio diagnostics, and a tvOS audio resync watchdog.

| Feature | Status | Notes |
|---------|--------|-------|
| Opus decode | Implemented | WebRTC decode path is part of the live stream runtime. |
| Playback-oriented tvOS audio session | Implemented | The vendored WebRTC build and app bootstrap force a playback-safe tvOS posture. |
| RemoteIO output-only path | Implemented | The repo uses the tvOS-safe output-only AudioUnit path. |
| Stereo output preference | Implemented | Stereo is a real product setting backed by the current patched build. |
| Audio boost | Implemented | Audio boost is both persisted and applied live during active streams. |
| Audio resync watchdog | Implemented | A tvOS-specific resync policy monitors drift and can trigger corrective action. |
| Audio debug toggle | Implemented | Audio-specific verbose diagnostics can be enabled separately from generic logging. |
| Audio drift visibility | Implemented | The runtime surfaces jitter-buffer and playout-related audio metrics. |
| Surround-sound output | Not Started | Current product path is stereo/mono oriented, not a surround-specific feature surface. |

---

## Video Rendering

Video output is not tied to a single renderer. The app owns renderer attachment, fallback, telemetry, and first-frame milestones. That makes rendering a real subsystem instead of a single view implementation detail.

The important consequence is that renderer choice is policy-driven in the app, not a hardcoded framework side effect. `RendererAttachmentCoordinator`, `RenderLadderPlanner`, and the streaming telemetry model together decide which path is active, how fallback behaves, and what the HUD can report about failures or output-family changes.

| Feature | Status | Notes |
|---------|--------|-------|
| H.264 decode | Implemented | Hardware-backed decode path is part of the current stream runtime. |
| Sample-buffer render path | Implemented | Sample-buffer rendering remains the stable floor path. |
| Metal render path | Implemented | Metal-backed rendering is present in the app target. |
| Renderer fallback / ladder policy | Implemented | The app can adapt renderer choice rather than hardcoding one path forever; current behavior is shaped by the render ladder and runtime capability checks. |
| Contrast Adaptive Sharpening path | Partial | The Metal path includes processing features, but like any processed renderer path it has more moving parts than the sample-buffer floor. |
| Saturation adjustment | Implemented | Color-tuning support exists in the current stream settings/runtime path. |
| Safe-area adjustment | Implemented | Video safe-area controls are part of the live settings model. |
| HDR preference | Partial | HDR preference is wired, but real end-to-end output depends on the runtime, route, and display environment. |
| Frame probe / render diagnostics | Implemented | The repo includes renderer telemetry, first-frame tracking, failure counts, and a frame-probe path for debugging. |

---

## UI and Navigation

The shell is not a bare SwiftUI navigation demo. The current app includes side-rail and top-level shell composition, focus coordination, profile and utility overlays, accessibility-facing settings, and route-aware CloudLibrary presentation.

| Feature | Status | Notes |
|---------|--------|-------|
| Custom shell navigation | Implemented | The authenticated shell and CloudLibrary route model are current live product surfaces. |
| Focus-aware media browsing | Implemented | Focus state is central to the browse model, not bolted on. |
| Home, library, search, consoles routing | Implemented | The primary browse and utility routes are all present in the shell. |
| Detail presentation | Implemented | Title detail exists as a first-class route, not an ad hoc modal. |
| Profile overlay | Implemented | Signed-in profile presentation is part of the live shell. |
| Settings panes | Implemented | CloudLibrary settings and in-stream guide settings both exist. |
| Reduce Motion | Implemented | Accessibility-focused shell motion control is present. |
| Large Text | Implemented | Large-text support is part of the shared settings/accessibility model. |
| High Visibility Focus | Implemented | Accessibility-focused focus styling is present in the live settings model. |
| Remember last section behavior | Implemented | The shell persists and restores section context rather than always cold-starting one tab. |

---

## Xbox Social Features

The repo already includes more Xbox social/profile support than a simple avatar overlay. Profile, presence, friends/people, and achievements are all backed by real package clients and controllers.

| Feature | Status | Notes |
|---------|--------|-------|
| Xbox profile fetch | Implemented | Current-user profile information is loaded through the web profile client stack. |
| Profile overlay | Implemented | Signed-in profile presentation is live in the app shell. |
| Presence fetch | Implemented | Presence data is loaded and surfaced in the current profile flow. |
| Presence writeback | Partial | Presence update support exists, but the repo intentionally degrades to read-only behavior when the environment/API does not allow writes. |
| Friends / people fetch | Implemented | Social people support exists through `XboxSocialPeopleClient`. |
| Achievement history and summary | Implemented | Achievements are loaded, summarized, cached, and surfaced through the current controllers and API layer. |
| Achievement detail support | Implemented | Per-title achievement snapshots are part of the detail/hydration path. |
| Party / invite UX | Not Started | No finished party or invite flow exists in the app today. |
| Activity feed | Not Started | No productized activity feed exists in the current repo. |

---

## In-Stream Guide

The guide is a real product surface, not just a stop button. It exposes stream, controller, video/audio, interface, and diagnostics settings during active playback.

| Feature | Status | Notes |
|---------|--------|-------|
| Guide overlay | Implemented | Slide-in guide overlay is part of the current stream UX. |
| Stream quality controls | Implemented | Quality, codec, profile, resolution, frame rate, bitrate cap, low-latency mode, and upscaling are all represented in the guide/settings catalog. |
| Controller settings | Implemented | Deadzone, trigger sensitivity, trigger interpretation, A/B swap, invert Y, and vibration are guide-visible. |
| Video/audio settings | Implemented | Audio boost, stereo preference, safe area, HDR preference, and related settings are surfaced. |
| Diagnostics settings | Implemented | Region override, stream stats, upscaling floor, and audio watchdog-related settings are part of the current guide/diagnostics story. |
| Interface settings | Implemented | Reduce motion, large text, quick-resume badges, focus visibility, and guide translucency settings exist. |
| Settings persistence | Implemented | Guide changes persist through the shared settings store. |
| Reset-to-defaults UX | Partial | The model can be reset programmatically, but there is no polished user-facing reset-to-defaults flow yet. |

---

## Settings and Configuration

Settings are centralized rather than scattered across the app. This matters because stream, controller, accessibility, and diagnostics behavior all depend on the same stored configuration surfaces.

| Feature | Status | Notes |
|---------|--------|-------|
| Central settings store | Implemented | Shared settings live in `StratixCore/SettingsStore.swift`. |
| UserDefaults persistence | Implemented | Current settings are persisted with registered defaults. |
| Snapshot-based reads across isolation boundaries | Implemented | Snapshot accessors exist so non-main-actor code can consume stable value snapshots. |
| Legacy key migration | Implemented | The settings layer already contains migration behavior for older keys where needed. |
| External change observation | Implemented | The store listens for relevant defaults changes rather than assuming it is the only writer. |
| Programmatic reset | Implemented | Settings can be reset in code. |
| User-facing reset control | Partial | No polished general reset button exists in the current product. |

See [CONFIGURATION.md](CONFIGURATION.md) for the current key-level reference.

---

## Diagnostics

Diagnostics are not a side project in Stratix. The current repo has runtime stats, renderer telemetry, audio watchdog logging, input cadence warnings, and validation tooling that all support performance and bug triage.

| Feature | Status | Notes |
|---------|--------|-------|
| Stream stats HUD | Implemented | Live stream stats can be shown during playback. |
| Demand-driven diagnostics polling | Implemented | Stats polling is enabled when the overlay or HUD needs it, not as a permanent always-on background task. |
| Renderer telemetry | Implemented | Renderer mode, first-frame state, decode failures, and telemetry snapshots feed the current runtime model. |
| Audio diagnostics | Implemented | Audio playout rate, jitter-buffer delay, and resync behavior are all part of the live diagnostics story. |
| Input cadence warnings | Implemented | Input transport has warning and health telemetry behavior. |
| Navigation/performance tracking | Implemented | DiagnosticsKit and app-local trackers cover performance-sensitive surfaces. |
| Preview / diagnostics export support | Implemented | The repo includes preview/diagnostic export paths for validation and debugging. |
| Crash-reporting backend | Not Started | No external crash service is wired into the public repo. |
| Analytics backend | Not Started | There is no finished analytics backend configured in the public repo. |

---

## Better xCloud-Inspired and Protocol-Adjacent Support

The repo includes a number of xCloud-adjacent and Better xCloud-inspired capabilities, but not all of them are fully productized features yet.

| Feature | Status | Notes |
|---------|--------|-------|
| Device/profile spoofing for stream startup | Implemented | Client profile selection is part of the live stream settings/configuration path. |
| Gallery/category support | Implemented | The repo includes gallery and category support through the Game Pass SIGL surface and related browse projection. |
| Queue wait-time protocol support | Partial | The API path exists, but the product surface is still incomplete. |
| Region override | Partial | Region override is present today, but still simpler than a full dynamic region model. |
| Telemetry blocking | Not Started | Not a finished product feature in the current repo. |
| Region restriction bypass | Not Started | Not wired into the live product path. |
| Volume boost beyond current guide range | Not Started | Current audio boost exists, but the “beyond system max” style feature is not productized separately. |

---

## xHome Local Console Streaming

xHome deserves its own section because it is present in the repo, but it is not identical to the cloud path.

| Feature | Status | Notes |
|---------|--------|-------|
| Local console stream launch | Implemented | xHome launch exists in the current stream workflow set. |
| Local-network connectivity support | Implemented | The app includes local-console streaming posture and runtime support. |
| Stream overlay support for xHome | Implemented | xHome streams still participate in the stream overlay and runtime model. |
| xHome metadata parity with xCloud | Partial | Overlay and metadata surfaces are leaner than the xCloud path. |
| xHome achievements overlay parity | Partial | The current overlay explicitly notes that achievements are not yet available for xHome streams. |

---

## Build and Development

The repo includes dedicated validation and tooling lanes that support the shipping app and its packages.

| Feature | Status | Notes |
|---------|--------|-------|
| Package sweep lane | Implemented | `Tools/dev/run_package_sweep.sh` is part of the active validation posture. |
| Shell UI lane | Implemented | `Tools/dev/run_shell_ui_checks.sh` covers shell-focused regressions. |
| Runtime safety lane | Implemented | `Tools/dev/run_runtime_safety.sh` covers runtime/WebRTC-adjacent proof. |
| Validation build lane | Implemented | `Tools/dev/run_validation_build.sh` remains the broad closeout lane. |
| Hardware validation lane | Implemented | Hardware-focused validation scripts exist without the earlier personal-device leakage. |
| Shell visual regression tooling | Implemented | Visual-regression support remains part of the current tool/tooling surface. |

This section is included because the public repo is also part of the product surface now. A feature that only “exists” if one developer remembers a private local sequence is not stable enough to count as shipped infrastructure. The current repo does have named validation lanes, reusable shell tooling, and package sweeps that another contributor can actually run.

---

## Known Open Follow-Up

### Infra Debt

| Item | Detail | Effort to complete |
|------|--------|-------------------|
| Bundle identifiers | Live project files now use the `com.stratix.appletv.*` family | Remaining public-release work is signing, provisioning, and App Store Connect polish, not another in-repo rename pass |
| Symbol-level Swift commentary | File-header rollout is complete; inline symbol documentation is still being added in targeted passes | Incremental; no blocking dependency |

### Partial Feature Completion Paths

| Feature | What's Partial | What's Needed to Complete |
|---------|---------------|--------------------------|
| Auto-reconnect | Recovery exists but reconnect is conservative — no seamless resume across network interruptions | `StreamingSession` reconnect state machine needs a stronger resume path before falling back to full re-provision |
| Queue wait time display | API/model support exists but no polished user-facing wait-time screen exists | Surface `estimatedTotalWaitTimeInSeconds` in the launch/loading UX |
| `1080p-hq` tier | Accessible through the stream configuration path but still not surfaced cleanly as a named user-facing tier everywhere | Promote it into a clearer product-facing quality option |
| Region picker UX | Region override exists but the UX is still simpler than a full server-driven picker | Expose the complete region model and better explanatory UI |
| Vibration intensity | Vibration routing exists but there is no user-facing intensity control | Add intensity model/persistence and scale output before send |
| Multi-controller support | Product flow is still one-controller-first | Add per-controller queueing and merged packet UX/model work |
| Button remapping | No UI or data model exists | Add remap model, persistence, and application during input read |
| Party / invite UX | No finished product flow | Wire additional Xbox social APIs and design the user flow |

---

## Not Started Priority Candidates

These are explicit `Not Started` items that would likely have high user value relative to the current repo shape.

| Feature | Why Valuable | Primary Dependency |
|---------|-------------|-------------------|
| Queue wait time display | Users can see estimated wait before title starts | `/waittime/` endpoint in `XCloudAPIClient` plus launch-UX surfacing |
| Volume boost beyond the current guide range | Better audibility in noisy environments | Additional gain-policy work in the audio pipeline |
| IPv6 ICE preference | Potential latency and connectivity improvements on IPv6-capable networks | `ICEProcessor` preference policy |
| Region restriction bypass (`X-Forwarded-For`) | Could broaden unsupported-region access for advanced users | Header injection policy in `XCloudAPIClient` |
| Telemetry blocking | Reduce network overhead and Microsoft tracking | URLSession task filtering and product-facing controls |
| Richer curated gallery UUID surfacing | Better browse surfaces like “Most Popular” and “Recently Added” | `GamePassSiglClient` plus browse projection work |

---

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [UI_ARCHITECTURE.md](UI_ARCHITECTURE.md)
- [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md)
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [RUNTIME_FLOW.md](RUNTIME_FLOW.md)
- [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md)
- [PERFORMANCE.md](PERFORMANCE.md)
- [CONFIGURATION.md](CONFIGURATION.md)
- [BETTER_XCLOUD.md](BETTER_XCLOUD.md)
- [FUTURE_WORK.md](FUTURE_WORK.md)
