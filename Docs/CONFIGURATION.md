# Configuration Reference

This document is a reference for every configurable value in Stratix — UserDefaults keys, compiler flags, stream defaults, debug toggles, Keychain keys, and how each one behaves.

**How to use this doc:** This is primarily a reference, not a sequential read. If you are debugging a specific behavior and want to know whether it is controlled by a setting, search for the relevant keyword. If you are adding a new setting, the [How to Add a New Setting](#how-to-add-a-new-setting) section at the bottom tells you exactly where to add it.

**Which settings apply immediately vs. on restart:** Not every setting takes effect the moment you change it. Some stream settings only apply when a new stream session starts. The [How Settings Are Applied](#how-settings-are-applied) section explains which categories take effect immediately and which require a stream or app restart.

All runtime settings are stored in `UserDefaults.standard` and managed by `SettingsStore` at `Packages/StratixCore/Sources/StratixCore/SettingsStore.swift`. Settings are organized into 6 categories exposed as typed `SettingsStore` sections.

---

## Table of Contents

- [Build Configuration](#build-configuration)
- [Compiler Flags](#compiler-flags)
- [Shell Settings](#shell-settings)
- [Library Settings](#library-settings)
- [Stream Settings](#stream-settings)
- [Controller Settings](#controller-settings)
- [Accessibility Settings](#accessibility-settings)
- [Diagnostics and Debug Settings](#diagnostics-and-debug-settings)
- [Debug-Only Keys (InputChannel)](#debug-only-keys-inputchannel)
- [Internal Keys](#internal-keys)
- [How Settings Are Applied](#how-settings-are-applied)
- [Hardcoded Constants](#hardcoded-constants)
- [Keychain Keys](#keychain-keys)
- [Protocol Constants](#protocol-constants)
- [Streaming Defaults & SDP Configuration](#streaming-defaults--sdp-configuration)
- [Timing Constants](#timing-constants)
- [Image, Artwork & Persistence Cache Configuration](#image-artwork--persistence-cache-configuration)
- [How to Add a New Setting](#how-to-add-a-new-setting)
- [Resetting to Defaults](#resetting-to-defaults)

---

## Build Configuration

| Setting | Value |
|---------|-------|
| Swift version | `6.2` (hard constraint) |
| Concurrency checking | `complete` |
| tvOS deployment target | `26.0` |
| WebRTC compile flag | `-DWEBRTC_AVAILABLE` |

The workspace has 8 schemes. See [TESTING.md](TESTING.md) for what each scheme validates.

---

## Compiler Flags

These are set in Xcode Build Settings → Swift Compiler → Custom Flags.

| Flag | Default | Effect |
|------|---------|--------|
| `-DWEBRTC_AVAILABLE` | **Set** in the committed app-target configurations | Enables `WebRTCClientImpl` (real WebRTC). When absent, `MockWebRTCBridge` is used for UI-only or WebRTC-free builds. |
| `DEBUG` | Set in Debug configuration | Enables `#if DEBUG` blocks: `#Preview` macros, debug overlays, and verbose logging shortcuts |

### `#if` Conditional Compilation

| Condition | Where Used | Purpose |
|-----------|-----------|---------|
| `WEBRTC_AVAILABLE` | `WebRTCClientImpl.swift`, `MetalVideoRenderer.swift`, `StreamView.swift` | Gates real WebRTC import and Metal video rendering |
| `os(tvOS)` | `WebRTCClientImpl.swift`, `StreamView.swift` | tvOS-specific audio session, Metal config, GameController |
| `canImport(UIKit)` | `StreamView.swift`, `WebRTCClientImpl.swift` | UIKit-dependent rendering code |
| `canImport(Metal)` | `MetalVideoRenderer.swift`, `StreamView.swift` | Metal shader and render pipeline |
| `canImport(AVFoundation)` | `WebRTCClientImpl.swift`, `StreamView.swift` | Audio session configuration |
| `DEBUG` | `#Preview` macros, debug overlays, theme inspector | Development-only UI and logging |

---

## Shell Settings

Shell settings control the app's outer navigation and appearance.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `guide.profile_name` | String | `"Player"` | Display name shown in profile UI (overridden by Xbox profile on auth) |
| `guide.profile_image_url` | String | `""` | Profile avatar URL (overridden by Xbox profile on auth) |
| `guide.profile_presence_override` | String | `"Auto"` | Presence status override: `"Auto"`, `"Online"`, `"Offline"` |
| `guide.remember_last_section` | Bool | `true` | Restore last-viewed section (Home, Library, etc.) on app launch |
| `stratix.shell.lastDestination` | String | `"home"` | Last-viewed section identifier (persisted automatically) |
| `stratix.settings.lastCategory` | String | `"playback"` | Last-viewed settings category in the guide |
| `guide.quick_resume_tile` | Bool | `true` | Show "Quick Resume" tile on Home rail for recently played games |
| `guide.focus_glow_intensity` | Double | `0.85` | Intensity of the focus ring glow effect (0.0–1.0) |
| `guide.guide_translucency` | Double | `0.82` | Translucency of the guide overlay background (0.0–1.0) |

---

## Library Settings

Library settings control game library data management.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `guide.library_auto_refresh_enabled` | Bool | `true` | Automatically refresh library data when stale |
| `guide.library_auto_refresh_ttl_hours` | Double | `12.0` | Hours before library data is considered stale |
| `guide.focus_prefetch_enabled` | Bool | `true` | Prefetch game metadata when tiles receive focus (improves perceived load time) |

---

## Stream Settings

Stream settings control video, audio, and network behavior during active streaming sessions.

| Key | Type | Default | Valid Values | Description |
|-----|------|---------|-------------|-------------|
| `guide.stream_quality` | String | `"Balanced"` | `"Low Data"`, `"Balanced"`, `"High Quality"`, `"Competitive"` | Quality preset (adjusts resolution, bitrate, latency trade-offs) |
| `guide.codec_preference` | String | `"H.264"` | `"H.264"`, `"H.265"` | Video codec preference (H.265 may not be supported by all xCloud regions) |
| `guide.client_profile_os_name` | String | `"Auto"` | `"Auto"`, `"android"`, `"windows"`, `"tizen"` | Device spoofing for resolution tier — see [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) ADR-009 |
| `guide.preferred_resolution` | String | `"1080p"` | `"720p"`, `"1080p"`, `"1440p"` | Preferred stream resolution. Highest server tier still depends on `osName`; `tizen` maps to the `p1080HQ` / 2160p path. |
| `guide.preferred_fps` | String | `"60"` | `"30"`, `"60"` | Preferred frame rate |
| `guide.bitrate_cap_mbps` | Double | `0.0` | 0.0 = unlimited | Maximum bitrate cap in Mbps (0 = no cap) |
| `guide.hdr_enabled` | Bool | `true` | — | Request HDR stream if available |
| `guide.low_latency_mode` | Bool | `true` | — | Optimize for low latency over visual quality |
| `guide.show_stream_stats` | Bool | `false` | — | Show real-time stream statistics HUD overlay |
| `guide.auto_reconnect` | Bool | `true` | — | Automatically reconnect on stream disconnect |
| `guide.packet_loss_protection` | Bool | `true` | — | Enable FEC (Forward Error Correction) for packet loss resilience |
| `guide.region_override` | String | `"Auto"` | `"Auto"`, `"US East"`, `"US West"`, `"EU West"`, `"EU North"`, etc. | Override xCloud region selection (Auto = nearest) |
| `guide.upscaling_enabled` | Bool | `true` | — | Enables the upscale-friendly render path preference used by the current video pipeline and its migration logic |
| `guide.renderer_mode` | String | `"metalCAS"` | `"auto"`, `"sampleBuffer"`, `"metalCAS"` | Video renderer mode. `metalCAS` = custom Metal CAS path; `sampleBuffer` = `AVSampleBufferDisplayLayer` fallback |
| `guide.sharpness` | Double | `0.0` | 0.0–1.0 | Sharpening strength for the Metal/CAS render path |
| `guide.saturation` | Double | `1.0` | 0.0–2.0 | Saturation adjustment for the current rendering stack |
| `guide.audio_boost` | Double | `3.0` | 0.0–10.0 | Audio volume boost multiplier (1.0 = no boost, 3.0 = 3× amplification) |
| `guide.color_range` | String | `"Auto"` | `"Auto"`, `"Full"`, `"Limited"` | Video color range (Full = 0–255, Limited = 16–235) |
| `guide.safe_area` | Double | `100.0` | 80.0–100.0 | Safe area percentage for video display (adjusts for TV overscan) |
| `guide.stereo_audio` | Bool | `false` | — | Force stereo audio output. Requires xcframework built with patch 0011; enabling without it causes the octave-low bug |
| `guide.chat_channel` | Bool | `false` | — | Enable the chat data channel for text communication |
| `stratix.stream.locale` | String | `"en-US"` | BCP 47 locale | Stream locale for server-side content localization |
| `stratix.stream.preferIPv6` | Bool | `false` | — | Prefer IPv6 for WebRTC connections |
| `stratix.stream.preferredRegionId` | String | `""` | Region ID string | Preferred xCloud region ID (empty = auto) |
| `stratix.stream.statsHUDPosition` | String | `"topRight"` | `"topLeft"`, `"topRight"`, `"bottomLeft"`, `"bottomRight"` | Position of the stream statistics HUD |

---

## Controller Settings

Controller settings affect gamepad input mapping and haptics. See [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md) for the full input pipeline.

| Key | Type | Default | Range | Description |
|-----|------|---------|-------|-------------|
| `guide.enable_vibration` | Bool | `true` | — | Enable controller vibration/haptic feedback |
| `guide.invert_y_axis` | Bool | `false` | — | Invert both thumbstick Y axes |
| `guide.controller_deadzone` | Double | `0.10` | 0.0–1.0 | Radial thumbstick deadzone radius |
| `guide.trigger_sensitivity` | Double | `0.50` | 0.0–1.0 | Trigger pull fraction for max output (0.5 = half-pull = full output) |
| `guide.trigger_interpretation_mode` | String | `"Auto"` | `"Auto"`, `"Compatibility"`, `"Analog"` | Maps to `ControllerSettings.TriggerInterpretationMode` (`.auto`, `.digitalFallback`, `.analogOnly`) |
| `guide.swap_ab_buttons` | Bool | `false` | — | Swap A and B button outputs (Nintendo-style) |
| `guide.sensitivity_boost` | Double | `0.0` | 0.0–1.0 | Additional thumbstick sensitivity multiplier |
| `stratix.controller.vibrationIntensity` | Double | `1.0` | 0.0–1.0 | Vibration intensity scaling factor |

---

## Accessibility Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `guide.reduce_motion` | Bool | `false` | Reduce UI animations (respects system preference as fallback) |
| `guide.large_text` | Bool | `false` | Increase text size throughout the UI |
| `guide.closed_captions` | Bool | `false` | Persisted accessibility preference. End-to-end stream caption behavior still depends on server/runtime support. |
| `guide.high_visibility_focus` | Bool | `false` | Use higher-contrast focus ring for visibility |

---

## Diagnostics and Debug Settings

These settings control logging, debugging, and internal diagnostics.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `guide.debug_host_info` | Bool | `true` | Show host/server info in stream stats overlay |
| `guide.log_network_events` | Bool | `false` | Log all network requests/responses (verbose) |
| `stratix.privacy.blockTracking` | Bool | `false` | Block analytics/tracking events |
| `debug.stream.verbose_logs` | Bool | `false` | Enable verbose streaming session logs |
| `debug_use_rtc_mtl_video_renderer` | Bool | `false` | Use `RTCMTLVideoView` instead of custom Metal renderer (debugging) |
| `debug_stream_frame_probe` | Bool | `false` | Log every decoded video frame (very verbose — performance impact) |
| `debug.audio_resync_watchdog_enabled` | Bool | `true` | Enable audio resync watchdog (detects and corrects audio drift) |
| `debug.controller.startup_haptics_probe` | Bool | `true` | Test haptic engines on controller connection |

---

## Debug-Only Keys (InputChannel)

These keys are read directly by `InputChannel` and `GamepadHandler` without going through `SettingsStore`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `debug.input.verbose_logs` | Bool | `false` | Log every input packet send (very verbose) |
| `debug.input.warning_logs` | Bool | `false` | Log cadence/scheduler warnings for input timing |

---

## Internal Keys

These keys are managed automatically and should not be modified manually:

| Key | Type | Description |
|-----|------|-------------|
| `stratix.migrations.guide_show_stream_stats.v1` | Bool | Migration flag for legacy stats HUD key |
| `stratix.migrations.guide_upscaling_enabled.v1` | Bool | Migration flag for guide upscaling defaults |
| `stratix.presence.write_supported` | Bool | Cached capability probe for Xbox presence write support |

---

## How Settings Are Applied

### SettingsStore Architecture

`SettingsStore` is a `@MainActor @Observable` type that:

1. **Reads** all UserDefaults keys on initialization via `register(defaults:)` and typed read functions
2. **Stores** 6 settings categories as typed section properties: `shell`, `library`, `stream`, `controller`, `accessibility`, `diagnostics`
3. **Observes** `UserDefaults.didChangeNotification` to detect external changes (e.g., from the guide UI)
4. **Persists** changes back to UserDefaults via `didSet` observers on each section value or dedicated mutation path

### Settings Categories → Structs

| Category | Struct | Snapshot Function |
|----------|--------|-------------------|
| Shell | `ShellSettings` | `SettingsStore.snapshotShell()` |
| Library | `LibrarySettings` | `SettingsStore.snapshotLibrary()` |
| Stream | `StreamSettings` | `SettingsStore.snapshotStream()` |
| Controller | `ControllerSettings` | `SettingsStore.snapshotController()` |
| Accessibility | `AccessibilitySettings` | `SettingsStore.snapshotAccessibility()` |
| Diagnostics | `DiagnosticsSettings` | `SettingsStore.snapshotDiagnostics()` |

Snapshot functions are `nonisolated` and can be called from any context to get a frozen copy of the current settings.

### When Settings Take Effect

| Setting Category | When Applied |
|-----------------|-------------|
| Shell | Immediately (UI observes observable state) |
| Library | Next library refresh |
| Stream | **Next stream session** (not mid-stream for most settings) |
| Controller | Before stream start + after guide changes (via `InputController.updateControllerSettings(from:)`) |
| Accessibility | Immediately (UI observes observable state) |
| Diagnostics | Varies — some immediate (logging), some next session (renderer mode) |

### Changing Settings

Settings can be changed via:
1. **In-stream guide UI** — the guide overlay presents settings organized by category
2. **Programmatically** — `UserDefaults.standard.set(value, forKey: key)`
3. **Xcode debug console** — during development: `expr UserDefaults.standard.set(false, forKey: "guide.stereo_audio")`

---

## Hardcoded Constants

These values are compiled into the source and cannot be changed at runtime. A code edit and rebuild are required.

### Microsoft OAuth / Authentication

| Constant | Value | Source File |
|----------|-------|-------------|
| Client ID | `1f907974-e22b-4810-a9de-d9647380c97e` | `MicrosoftAuthService.swift` |
| OAuth Scope | `xboxlive.signin openid profile offline_access` | `MicrosoftAuthService.swift` |
| LPT Scope | `service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN` | `MicrosoftAuthService.swift` |
| Device Code URL | `https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode` | `MicrosoftAuthService.swift` |
| Token URL | `https://login.microsoftonline.com/consumers/oauth2/v2.0/token` | `MicrosoftAuthService.swift` |
| Live Token URL | `https://login.live.com/oauth20_token.srf` | `MicrosoftAuthService.swift` |
| Xbox User Auth URL | `https://user.auth.xboxlive.com/user/authenticate` | `MicrosoftAuthService.swift` |
| XSTS Auth URL | `https://xsts.auth.xboxlive.com/xsts/authorize` | `MicrosoftAuthService.swift` |
| Auth Relying Party | `http://auth.xboxlive.com` | `MicrosoftAuthService.swift` |
| GSSV Relying Party | `http://gssv.xboxlive.com/` | `MicrosoftAuthService.swift` |
| Web Relying Party | `http://xboxlive.com` | `MicrosoftAuthService.swift` |

> The Client ID is a **public** identifier used by Xbox web clients. It is not a secret.

### WebRTC Handshake

| Constant | Value | Source File |
|----------|-------|-------------|
| Handshake ID | `be0bfc6d-1e83-4c8a-90ed-fa8601c5a179` | `MessageChannel.swift` |
| Client App Install ID | `c97d7ee0-73b2-4239-bf1d-9d805a338429` | `MessageChannel.swift` |
| Control Auth Access Key | `4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E` | `ControlChannel.swift` |

### Device Spoofing (osName → Resolution Tier)

The `guide.client_profile_os_name` setting maps to resolution tiers on Microsoft's servers:

| osName | Resolution Signal | Quality Tier |
|--------|------------------|-------------|
| `android` | 720p | Standard |
| `windows` | 1080p | Standard |
| `tizen` | `p1080HQ` / 3840×2160 signal | Highest quality (Samsung Smart TV tier) |
| `"Auto"` (default) | No explicit override — resolution profile governs | Depends on selected resolution |

See [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) ADR-009 for the rationale.

### Stream Session Body

| Field | Default Value | Description |
|-------|--------------|-------------|
| `nanoVersion` | `"V3;WebrtcTransport.dll"` | Protocol version identifier |
| `sdkType` | `"web"` | SDK type identifier |
| `enableOptionalDataCollection` | `false` | Telemetry opt-in |
| `enableTextToSpeech` | `false` | TTS opt-in |
| `highContrast` | `0` | High contrast mode |
| `useIceConnection` | `false` | ICE mode flag |

---

## Keychain Keys

All authentication tokens are stored in the tvOS Keychain via `TokenStore` (`Packages/XCloudAPI/Sources/XCloudAPI/Auth/TokenStore.swift`). These persist across app launches and are cleared on sign-out.

| Key | Type | Description |
|-----|------|-------------|
| `stratix.msa_token` | String | Microsoft Account access token |
| `stratix.refresh_token` | String | MSA refresh token (rotates on use) |
| `stratix.lpt_token` | String | Limited Purpose Token for cloud `/connect` |
| `stratix.lpt_expiry` | String | LPT expiry timestamp stored as Unix-seconds string |
| `stratix.xhome_token` | String | xHome gsToken for console streaming |
| `stratix.xhome_host` | String | xHome base URI |
| `stratix.xcloud_token` | String | xCloud gsToken for cloud streaming |
| `stratix.xcloud_host` | String | xCloud base URI |
| `stratix.xcloud_f2p_token` | String | Free-to-play xCloud gsToken |
| `stratix.xcloud_f2p_host` | String | Free-to-play xCloud base URI |
| `stratix.web_token` | String | XSTS web token for Xbox Live APIs |
| `stratix.web_token_uhs` | String | User Hash from XSTS (for `Authorization: XBL3.0 x={uhs};{token}`) |

> Compatibility note: `TokenStore` still reads older `greenlight.*` entries and migrates them forward to `stratix.*` on access so existing local auth state upgrades cleanly.

---

## Protocol Constants

### Data Channel Labels

| Channel | Label | Version | Purpose |
|---------|-------|---------|---------|
| Control | `controlV1` | 1–3 | Auth, gamepad add/remove, video preference, keyframe requests |
| Input | `1.0` | 1–9 | Binary gamepad frames at the current 125 Hz transport cadence |
| Message | `messageV1` | 1 | JSON handshake, system UI config, disconnect handling |
| Chat | `chatV1` | 1 | Text chat (currently unused — `guide.chat_channel` defaults to `false`) |

### Input Binary Frame Constants

| Constant | Value | Description |
|----------|-------|-------------|
| Header length | 14 bytes | Packet header (report-type bitmask, sequence, uptime timestamp) |
| Gamepad block prefix | 1 byte | Frame count prefix before packed gamepad frames |
| Gamepad frame length | 23 bytes | One packed gamepad state snapshot |
| Metadata block prefix | 1 byte | Timing-frame count prefix when metadata is present |
| Metadata frame length | 28 bytes | One packed timing metadata frame |
| Button field width | 16 bits | `GamepadButtons` OptionSet (little-endian UInt16) |
| Axis precision | Int16 | Stick axes are packed to signed 16-bit integers |
| Trigger precision | UInt16 | Trigger values are packed to unsigned 16-bit integers |
| Poll interval | 8 ms | 125 Hz gamepad polling cadence |
| Send interval | 8 ms | 125 Hz packet send cadence |

See [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md) for the full packet layout.

### Keepalive & Session Timing

| Constant | Value | Source |
|----------|-------|--------|
| Keepalive interval | 30 seconds | `StreamSession.startKeepalive` |
| Device code poll interval | 5 seconds | `MicrosoftAuthService.pollForMSAToken` |
| Device code expiry | 900 seconds (15 min) | Server-provided via `expires_in` |
| SDP poll interval | 1 second | `StreamSession.exchangeSDP` |
| ICE poll interval | 1 second | `StreamSession.exchangeICE` |
| State poll interval | 1 second | `StreamSession.waitForStates` |

---

## Streaming Defaults & SDP Configuration

### SDP Offer Configuration

Sent as part of the SDP offer body to negotiate data channel versions:

```json
{
  "chatConfiguration": {
    "bytesPerSample": 2,
    "expectedClipDurationMs": 20,
    "format": { "codec": "opus", "container": "webm" },
    "numChannels": 1,
    "sampleFrequencyHz": 24000
  },
  "chat": { "minVersion": 1, "maxVersion": 1 },
  "control": { "minVersion": 1, "maxVersion": 3 },
  "input": { "minVersion": 1, "maxVersion": 9 },
  "message": { "minVersion": 1, "maxVersion": 1 }
}
```

### Video Preference Defaults

Sent on the control channel after connection:

| Field | Default | Notes |
|-------|---------|-------|
| Width | Varies by resolution | 1280 (720p), 1920 (1080p), 2560 (1440p), 3840 (`p1080HQ`) |
| Height | Varies | 720, 1080, 1440, 2160 |
| Max FPS | 60 | Frame rate cap |
| Color Range | `"limited"` | `"limited"` or `"full"` based on `guide.color_range` |

---

## Timing Constants

From `Packages/StratixCore/Sources/StratixCore/StratixConstants.swift`:

| Constant | Value | Description |
|----------|-------|-------------|
| Focus settle debounce | 60 ms | Delay before committing focus-based navigation |
| Focus target debounce | 90 ms | Delay before triggering focus target actions |
| Visible prefetch debounce | 140 ms | Delay before triggering visible-item prefetch |
| Shell boot fallback timeout | 20 seconds | Max wait for shell bootstrap before fallback |
| Achievement refresh interval | 120 seconds | Refresh rate while streaming |
| Library cache capacity | 5 hot details | In-memory hot detail cache (most recently focused) |
| Combined home TTL | 6 hours (production) | Time before home data is considered stale |
| Combined home TTL (testing) | 60 seconds | TTL override for test lanes |
| Visible home artwork prefetch limit | 14 items | Max concurrent artwork prefetches |
| Visible carousel items | 5 | Items in the featured carousel |
| Visible home row items | 4 | Items per home rail row |
| Visible home rows | 3 | Number of home rail rows |

### From SettingsStore and DiagnosticsKit

| Constant | Value | Location | Description |
|----------|-------|----------|-------------|
| Library auto-refresh TTL | 12 hours | `SettingsStore` | Default `guide.library_auto_refresh_ttl_hours` |
| Image disk cache max | Bounded (LRU) | `ArtworkCacheService` | LRU-evicted artwork cache |
| Audio resync watchdog period | ~2.4 s | `voice_processing_audio_unit.mm` | PCM throughput logging interval |
| Audio stall gap threshold | 40 ms | `voice_processing_audio_unit.mm` | Consecutive callback gap triggering stall log |
| Keyframe request interval | Periodic | `ControlChannel` | `keyframeIntervalSeconds` config |

---

## Image, Artwork & Persistence Cache Configuration

This section covers three different caching layers that are easy to conflate:

1. **Decoded UI image caching** in the app target for already-decoded `UIImage` instances.
2. **Artwork byte caching** in `StratixCore` for poster, hero, gallery, trailer, and avatar image data.
3. **Persisted product and library state** in `StratixCore`, where the unified library snapshot now uses SwiftData and some smaller domain caches still use JSON files.

The short version is:

- **Yes, Stratix uses SwiftData**, but only for the persisted unified library hydration snapshot.
- **No, image caching is not SwiftData-backed**. Remote artwork is still handled by the `RemoteImagePipeline` actor plus the lower-level `ArtworkPipeline` memory/disk cache.

### Decoded Image Runtime Cache

The SwiftUI image views do not decode every image from scratch on each render. The app target owns a `RemoteImagePipeline` actor that keeps a decoded `UIImage` cache and deduplicates in-flight image requests.

| Layer | Implementation | Storage | Persistence | Purpose |
|------|----------------|---------|-------------|---------|
| Decoded image cache | `RemoteImagePipeline` | `NSCache<NSString, UIImage>` | In-memory only | Reuses already-decoded `UIImage` instances for SwiftUI views |
| In-flight dedupe | `RemoteImagePipeline` | Actor-owned `[String: Task<UIImage?, Never>]` map | In-memory only | Prevents duplicate fetch/decode work when multiple views request the same artwork |

Key characteristics:

- The decoded cache is **not** written to disk.
- It is tuned for runtime presentation performance, not durable persistence.
- It sits above the lower-level `ArtworkPipeline`, which is responsible for fetching and storing raw artwork bytes.

### Artwork Data Cache

The actual artwork data cache lives in `Packages/StratixCore/Sources/StratixCore/Artwork/ArtworkPipeline.swift`.

| Cache Aspect | Live Repo Behavior | Notes |
|-------------|--------------------|-------|
| Memory cache | `NSCache<NSString, NSData>` | Fast reuse of raw image bytes during the current app session |
| Disk cache root | `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]/stratix.artwork/` | Persistent across launches until the system purges caches or the pipeline prunes them |
| Disk organization | Per-artwork-kind folders (`poster`, `hero`, `gallery`, `trailer`, `avatar`) | Cache keys are content-addressed from request URLs |
| Pruning policy | Size/file-count based | Controlled by `ArtworkDiskCachePolicy` |
| Prefetch behavior | On-focus / proactive | Driven by library prewarm and `guide.focus_prefetch_enabled` |
| Sources | Xbox catalog / asset hosts | Includes product art, hero art, gallery frames, and avatar-like assets |

Important corrections versus older docs:

- Artwork bytes are cached under the app **Caches** directory, not `Documents`.
- The artwork cache is **persistent but disposable**. It is appropriate for re-downloadable assets, not user-authored data.
- There is no SwiftData layer involved in artwork caching.

### Persisted Library Hydration Cache (SwiftData)

The unified library hydration snapshot is the part that now uses SwiftData. This persistence lives in `SwiftDataLibraryRepository`.

| Cache Aspect | Live Repo Behavior | Notes |
|-------------|--------------------|-------|
| Persistence technology | SwiftData | Backed by `ModelContainer` / `ModelContext` |
| Store owner | `SwiftDataLibraryRepository` actor | Isolated persistence boundary inside `StratixCore` |
| Stored record type | `UnifiedLibraryCacheRecord` | Single-row model keyed by `unified_sections_snapshot` |
| Payload shape | Encoded `LibrarySectionsDiskCacheSnapshot` JSON payload inside SwiftData | Keeps the persisted schema small while preserving the current snapshot model |
| Contents | Unified cloud-library sections, home merchandising, discovery data, metadata, freshness timestamps | This is the authoritative persisted startup-restore snapshot |
| Persistence timing | Immediate on save | `flushUnifiedSectionsCache()` is a no-op because SwiftData writes are committed as part of each save |

This is the cache layer documented in more detail in [HYDRATION.md](HYDRATION.md). When the app says it can restore a fresh library state on launch, this SwiftData-backed snapshot is the primary mechanism.

### Other Persisted JSON Caches

Not every persisted cache moved to SwiftData. Smaller domain-specific caches still use file-backed JSON snapshots managed by `MetadataCacheStore`.

`MetadataCacheStore` resolves these files into the app's `Application Support/stratix/` directory and transparently migrates legacy copies from the old caches directory when present.

| Cache | Storage | Migration / Lifetime | Notes |
|------|---------|----------------------|-------|
| Social people cache | `Application Support/stratix/stratix.socialPeople.json` | Legacy caches directory copies are moved forward automatically | Version-gated via `currentSocialCacheVersion`; stale versions are discarded |
| Achievement cache | `Application Support/stratix/stratix.titleAchievements.json` | Legacy caches directory copies are moved forward automatically | Version-gated via `currentCacheVersion`; stale versions are discarded |
| Library details / metadata snapshots | `Application Support/stratix/...json` | Depends on the specific snapshot file | Used for smaller persisted metadata fragments outside the unified SwiftData snapshot |

The reason this is mixed today is pragmatic:

- the **unified library snapshot** benefits from a dedicated persistence boundary and now lives in SwiftData;
- **artwork** benefits from cache-directory semantics and eviction-friendly storage;
- **smaller JSON caches** remain simple file snapshots because they are lightweight, versioned, and already isolated behind focused controllers or persistence helpers.

---

## How to Add a New Setting

1. **Choose a key name** following the naming convention:
   - User-facing: `guide.{category}_{setting_name}` (e.g., `guide.stream_quality`)
   - Internal: `stratix.{domain}.{setting}` (e.g., `stratix.stream.locale`)
   - Debug: `debug.{domain}.{setting}` (e.g., `debug.input.verbose_logs`)

2. **Add to `SettingsStore.swift`**:
   - Add a stored property with the default value
   - Add the key + default to `registeredDefaults`
   - Add the value to the appropriate settings struct (e.g., `StreamSettings`)
   - Update the snapshot function (e.g., `snapshotStream()`)

3. **Wire the UI** (if user-visible):
   - Add a control in the appropriate guide settings section
   - The guide reads/writes via `SettingsStore` section bindings

4. **Document the key** in this file under the appropriate category

5. **Test**: Add a test case in `SettingsStoreTests.swift` verifying the default value and round-trip persistence

---

## Resetting to Defaults

To reset all settings to their defaults:

```swift
// In Xcode debug console or a test:
let defaults = UserDefaults.standard
[
    "guide.stream_quality",
    "guide.preferred_resolution",
    "guide.controller_deadzone",
    "guide.show_stream_stats",
    "guide.renderer_mode",
    "guide.stereo_audio"
].forEach { defaults.removeObject(forKey: $0) }
```

Or reset an individual setting:
```swift
UserDefaults.standard.removeObject(forKey: "guide.stream_quality")
// Next read returns the registered default: "Balanced"
```

Registered defaults are defined inside `SettingsStore` and applied via `defaults.register(defaults:)`. They are intentionally an internal implementation detail rather than a public reset API.

---

## Related Docs

- [GETTING_STARTED.md](GETTING_STARTED.md) — quick-reference settings table for development
- [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md) — controller settings detail
- [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md) — `guide.stereo_audio` and the octave-low bug
- [XCLOUD_PROTOCOL.md](XCLOUD_PROTOCOL.md) — protocol constants and API endpoints
- [../SECURITY.md](../SECURITY.md) — Keychain and token handling policy
