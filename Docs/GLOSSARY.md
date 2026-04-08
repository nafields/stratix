# Glossary

This glossary is here because Stratix spans several domains that each come with their own vocabulary — WebRTC signaling, tvOS audio sessions, Xbox authentication, Swift concurrency. When you encounter a term in another doc and it is not immediately clear, check here first.

The terms are grouped by domain so related concepts appear together. If you are new to the project, the [Streaming](#streaming) and [WebRTC and Streaming](#webrtc-and-streaming) sections are the most likely to have unfamiliar terms.

---

## App and Architecture

**Stratix**
The tvOS app target and the current project name for the repo.

**StratixCore**
The package that owns app lifecycle, controllers, hydration, stream launch workflows, and shell recovery. It has no SwiftUI views.

**StratixModels**
The leaf package for shared model types. It should not depend on other packages.

**CloudLibrary**
The primary authenticated app surface for browsing cloud titles, profile/settings overlays, and stream launch entry.

**Shell**
The authenticated app container around the CloudLibrary and related overlays.

**Route**
A navigation destination or presentation state such as browse, detail, settings, or profile.

**Presentation store**
The app-owned cache/projection layer that shapes route-ready view state for rendering.

## Streaming

**xCloud**
Microsoft’s cloud-streaming service used for title streaming.

**xHome**
Console remote-play support from a personal Xbox.

**StreamingSession**
The app-facing observable streaming facade in `StreamingCore`.

**StreamingRuntime**
The lower-level runtime boundary under the observable session facade.

**StreamController**
The `StratixCore` controller that owns app-facing stream state and launch orchestration.

**Stream kind**
The distinction between cloud streaming and home-console streaming.

**SDP**
Session Description Protocol. The offer/answer format used during WebRTC negotiation.

**ICE**
Interactive Connectivity Establishment. Candidate exchange and connectivity checks for WebRTC.

**Data channel**
A WebRTC side channel used for message, control, input, and chat traffic.

## Rendering and Audio

**RendererAttachmentCoordinator**
The app-owned coordinator that attaches the active render path and handles fallback.

**RenderSurfaceCoordinator**
The app-owned policy layer that decides how the visible streaming surface is composed.

**Metal renderer**
The app render path that uses Metal-backed video output.

**Sample buffer renderer**
The render path built around `AVSampleBufferDisplayLayer`.

**Frame probe**
An optional diagnostics surface for frame-level instrumentation.

## Controllers and Input

**InputBridge**
The package that owns controller input capture, frame buffering, and binary packet shaping.

**InputQueue**
The queue that holds the most recent controller frames before they are serialized and sent.

**InputPacket**
The binary payload sent over the input data channel.

**Trigger interpretation mode**
The setting that decides how trigger input is interpreted for different controller capabilities.

## Docs and Validation

**Workspace-first validation**
The repo’s testing posture where app proof is driven from `Stratix.xcworkspace` and scheme/script lanes, not from one standalone project target.

**Package sweep**
The package validation lane run by `bash Tools/dev/run_package_sweep.sh`.

**Shell UI checks**
The shell route/focus regression lane run by `bash Tools/dev/run_shell_ui_checks.sh`.

**Runtime safety**
The simulator regression lane for runtime and WebRTC-adjacent behavior run by `bash Tools/dev/run_runtime_safety.sh`.

## Hydration and Persistence

**LibraryHydrationOrchestrator**
The `@MainActor` struct in `StratixCore` that coordinates the three hydration flows: startup restore, live refresh, and post-stream delta.

**LibraryHydrationLiveRefreshWorkflow**
The workflow that fetches fresh xCloud titles and kicks off catalog shaping. Part of the live refresh flow.

**LibraryHydrationCatalogShapingWorkflow**
The workflow that enriches raw title data with Xbox.com product details (artwork, descriptions, trailers, genres).

**LibraryHydrationPersistenceStore**
The persistence abstraction within the hydration layer. Backed by `SwiftDataLibraryRepository`.

**LibraryHydrationSnapshots**
Crash-recovery snapshot data produced during hydration workflows.

**SwiftDataLibraryRepository**
The `actor` that wraps a SwiftData `ModelContainer`. Stores a single `UnifiedLibraryCacheRecord` keyed by `"unified_sections_snapshot"`.

**LibraryHydrationPostStreamDeltaWorkflow**
The targeted refresh that updates recently-played titles after a stream ends.

**LibraryMRUDeltaFetcher**
Fetches "most-recently-used" title deltas for the post-stream update — only fetches affected titles, not the full catalog.

**HomeMerchandising**
The featured home content (hero art, promotional rails). Refreshed separately from the title catalog on a ~6 hour TTL.

**LibraryHomeMerchandisingCoordinator**
Coordinates home merchandising discovery via SIGL. Decides whether to use cached discovery or fetch fresh aliases.

**HomeMerchandisingRefreshWorkflow**
The workflow that fetches merchandising section aliases and product IDs from the SIGL service.

**LibraryPostLoadWarmupCoordinator**
Preloads the top 5 recently-viewed product detail pages into memory after library load to reduce detail view latency.

## State and Observation

**SettingsStore**
`@MainActor @Observable` settings hub in `StratixCore`. Owns 6 typed category structs backed by UserDefaults. Provides snapshot functions for cross-actor reads.

**AppCoordinator**
The composition root in `StratixCore` that creates and wires all controllers. In extraction-only mode — no new permanent responsibilities.

**TaskRegistry**
Task lifecycle management registry used by controllers to track and cancel in-flight async tasks.

**CloudLibraryRouteState**
The `@Observable` route state owned locally by the CloudLibrary shell. Tracks the active primary route and detail state.

**CloudLibraryFocusState**
The `@Observable` focus state owned locally by the CloudLibrary shell. Tracks focus position within the shell surfaces.

**CloudLibraryPresentationStore**
The `@Observable` modal presentation state for the CloudLibrary shell.

**StratixConstants**
Static constants for timing, focus settle debounce, and other cross-cutting values. Example: `StratixConstants.UI.focusSettleDebounceNanoseconds = 60_000_000` (60 ms).

## WebRTC and Streaming

**WebRTCClientImpl**
The concrete `WebRTCBridge` implementation surface in `Apps/Stratix/Sources/Stratix/Integration/WebRTC/`. This bridge is split across multiple `WebRTCClientImpl*` files that import `WebRTC` only when `-DWEBRTC_AVAILABLE` is set.

**MockWebRTCBridge**
A no-op `WebRTCBridge` implementation used for UI development, unit tests, and other non-WebRTC or harness-friendly surfaces. It is not the default path for normal simulator builds in the current workspace, because the app target now compiles with `-DWEBRTC_AVAILABLE`.

**StreamingSessionFacade**
The bridge between the observable `StreamingSession` (main actor) and the off-main `StreamingSessionRuntime`.

**StreamingSessionRuntime**
The off-main-actor runtime that performs WebRTC operations (SDP, ICE, channel management). Publishes state back to `StreamingSession` via `StreamingSessionFacade`.

**SDPProcessor**
Applies 3 transforms to local SDP before sending: H.264 codec ordering, bitrate injection, device-spoofing headers.

**ICEProcessor**
Handles Xbox ICE quirks: strips `a=` prefix from candidates, expands Teredo IPv6 addresses.

**LPT (Long Play Token)**
A short-lived (~5 min) token required for the xCloud `/connect` step. Fetched from `login.live.com/oauth20_token.srf`.

**gsTokens / StreamTokens**
The stream tokens returned by the xCloud login endpoint. Used as auth for all xCloud API calls.

**XSTS**
Xbox Secure Token Service. Exchanges MSA tokens for Xbox-specific tokens used by Xbox Live APIs.

**Device spoofing**
Sending Windows/Chrome values in `User-Agent` and `x-ms-device-info` HTTP headers so the xCloud server assigns the 1080p resolution tier.

## Diagnostics and Metrics

**GLogger**
The structured logging wrapper in `DiagnosticsKit`. Wraps `OSLog` with category-based filtering.

**StreamMetricsPipeline**
Ring-buffer metrics pipeline in `DiagnosticsKit`. Routes `StreamMetricsRecord` entries to registered `StreamMetricsSink` observers.

**StreamMetricsSnapshot**
Full export of all collected metrics for a stream session: milestone timestamps, stats snapshots, event counts, latency deltas.

**AudioStats**
Per-second diagnostic summary emitted during streaming: `playoutRate`, jitter buffer window, resync count, PCM throughput.

**playoutRate**
The fraction of expected audio frames that were extracted from NetEQ per second. `100%` = healthy. `50%` = stereo/mono mismatch bug (see AUDIO_ARCHITECTURE.md).

## Rendering

**RenderLadderPlan**
Resolved rendering strategy from `VideoRenderingKit`: active rung, source/display dimensions, eligible rungs, fallback floor.

**UpscaleStrategy**
Priority-ordered enum in `VideoRenderingKit`: Metal4FX Spatial, VT Super Resolution, VT Frame Interpolation, MetalFX Spatial, passthrough.

**MetalVideoRenderer**
The Metal CAS (Contrast Adaptive Sharpening) render path. Used when `guide.renderer_mode = "metalCAS"` or when sharpness/saturation is non-neutral.

**SampleBufferDisplayRenderer**
The `AVSampleBufferDisplayLayer`-based render path. Lower GPU overhead; used at neutral video settings or when `guide.renderer_mode = "sampleBuffer"`.

**CAS (Contrast Adaptive Sharpening)**
AMD's image sharpening algorithm applied post-decode in `MetalVideoRenderer`.

## Migration Terms

**Legacy `greenlight` compatibility key surface**
The remaining compatibility naming that still uses the old `greenlight` family, primarily legacy Keychain migration keys in auth/token storage. This is no longer a bundle-identifier story in the live project files.

**Docs_to_update**
Historical documentation source material. Useful as input, but not the current source of truth.

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md)
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [TESTING.md](TESTING.md)
