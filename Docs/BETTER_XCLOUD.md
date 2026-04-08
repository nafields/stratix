# Better xCloud Alignment

This document maps Better xCloud browser-extension features to their native Stratix equivalents, explains the device-spoofing tiers in detail, and documents which Better xCloud features are not applicable to tvOS.

Better xCloud is a browser userscript that enhances the xCloud web client. Stratix is a native tvOS app. They solve the same problem — a better xCloud streaming experience — but through entirely different mechanisms. This document is a gap-analysis and alignment reference, not a port tracker.

---

## Feature Alignment Table

### Implemented in Stratix (Native Equivalents)

| Better xCloud Feature | Stratix Equivalent | Location |
|----------------------|-------------------|---------|
| Device info / `osName` spoofing for resolution | `XCloudAPIClient` builds `x-ms-device-info` header | `Packages/XCloudAPI` |
| Target resolution setting (`720p`/`1080p`/`1080p-hq`) | `guide.preferred_resolution` plus `guide.client_profile_os_name` | `SettingsStore.StreamSettings` |
| Region-aware login + region override | `guide.region_override` + `stratix.stream.preferredRegionId` through `StreamLaunchConfigurationService` and region-selection policy | `Packages/StratixCore`, `Packages/XCloudAPI` |
| Stream quality preferences (bitrate cap, codec) | `SettingsStore.StreamSettings` — bitrate cap, codec preference | `Packages/StratixCore` |
| Stream stats HUD (frame rate, bitrate, RTT, packet loss, renderer diagnostics) | `StreamMetricsPipeline` + in-stream diagnostics overlay | `Packages/DiagnosticsKit`, `Apps/Stratix/Sources/Stratix/Features/Guide/` |
| Video sharpening (CAS) | `MetalVideoRenderer` with AMD CAS shader | `Apps/Stratix/Sources/Stratix/Integration/WebRTC/MetalVideoRenderer.swift` |
| Sharpness / saturation adjustments | `guide.sharpness`, `guide.saturation` UserDefaults keys | `SettingsStore.StreamSettings` |
| Controller vibration routing | `InputChannel` parses `VibrationReport`; `GamepadHandler` maps it into GC haptics | `Packages/StreamingCore`, `Packages/InputBridge` |
| Title media enrichment (hero art, trailers, screenshots) | `XboxComProductDetailsClient` → `CloudLibraryMediaAsset` pipeline | `Packages/XCloudAPI` |
| Loading screen game art | `LibraryHydrationCatalogShapingWorkflow` enriches all titles at hydration time | `Packages/StratixCore` |
| Controller button combos → in-app actions | `ChordRecognizer` + `ShortcutAction` in `GamepadHandler` | `Packages/InputBridge` |
| Stream locale preference | `stratix.stream.locale` override | `SettingsStore.StreamSettings` |
| Low-latency mode | `guide.low_latency_mode` UserDefaults key | `SettingsStore.StreamSettings` |
| Frame rate cap | `guide.preferred_fps` UserDefaults key | `SettingsStore.StreamSettings` |
| Keyframe interval | Derived from `guide.low_latency_mode` in `StreamConfigBuilder` (not a standalone user setting) | `Packages/StratixCore` |
| IPv6 ICE preference | `stratix.stream.preferIPv6` UserDefaults key | `SettingsStore.StreamSettings`, `XCloudAPIClient` |
| SDP codec ordering + bitrate injection | `SDPProcessor` — H.264 ordering + `b=AS:` injection | `Packages/StreamingCore` |

### Mixed Status

| Better xCloud Feature | Stratix Status | Notes |
|----------------------|---------------|-------|
| Queue wait time display | Implemented | The live stream path already calls the wait-time endpoint and surfaces estimated wait seconds through the stream lifecycle / overlay path. |
| `1080p-hq` tier unlock (`tizen` OS name) | Configurable via `guide.client_profile_os_name` plus the current resolution/profile settings | See device spoofing table below |
| Volume boost beyond system max | Implemented | `guide.audio_boost` is exposed in current settings and threaded into the live stream configuration path. |
| Vibration intensity setting (0–100% scale) | Implemented | Shared models, settings, and controller settings UI all include vibration intensity today. |
| Region restriction bypass (X-Forwarded-For) | Not started | `LibraryHostResolver` handles region selection but not geographic spoofing |
| Game Pass gallery UUIDs (Most Popular, Recently Added) | Not started | `catalog.gamepass.com/sigls/` endpoints; would enrich home merchandising rails |

### Not Applicable to tvOS

| Better xCloud Feature | Reason Not Applicable |
|----------------------|----------------------|
| Touch controller (virtual gamepad) | Apple TV has no touchscreen |
| Mouse & keyboard (MKB) mode | No cursor or keyboard support in tvOS |
| Screen capture | tvOS has no screen recording API for this use case |
| Device vibration (phone/tablet) | No equivalent actuator on Apple TV hardware |
| Microphone input | Patched out of the WebRTC build (Patch 0002/0008) |
| Browser DOM patches | Require a live web DOM; meaningless in native SwiftUI |
| Splash video skip | Different mechanism — xCloud web splash is browser-only |
| UI scrollbar hiding / page layout overrides | Browser rendering concerns only |
| Telemetry blocking via URL intercept | Network layer is native; no `XMLHttpRequest` to intercept. Could implement via URLSession filtering at `XCloudAPIClient` level if desired. |
| Feature gate overrides (`emerald.xboxservices.com/xboxcomfd/experimentation`) | Not fetched by native app |
| X-Forwarded-For geographic bypass | Not implemented |

---

## Device Spoofing Detail

Stratix injects `x-ms-device-info` on xCloud session start to request a specific resolution tier from the xCloud server:

### Device Info Payload

```json
{
  "clientAppVersion": "26.1.97",
  "sdkVersion": "10.3.7",
  "browserName": "chrome",
  "browserVersion": "140.0.3485.54",
  "displayWidth": 4096,
  "displayHeight": 2160
}
```

### OS Name Resolution Tiers

The `osName` field in the session start body determines the resolution tier assigned by the xCloud server:

| `osName` value | Resolution tier | Notes |
|----------------|----------------|-------|
| `windows` | 1080p standard | Default Stratix production tier |
| `android` | 720p | Lower quality, useful for bandwidth-constrained connections |
| `tizen` | 1080p HQ | Samsung Smart TV tier — highest quality available. Mirrors Better xCloud’s `1080p-hq` |

The effective spoofed device profile is driven by the current `SettingsStore.StreamSettings` values, especially `guide.client_profile_os_name` and `guide.preferred_resolution`. The session start body is serialized in `XCloudAPIClient` before the POST to `{region}/sessions/cloud/play`.

### User-Agent Spoofing

The current repo truth is narrower than some older notes suggest:

- Stratix explicitly sends `X-MS-Device-Info` from `XCloudAPIClient`.
- Stratix does **not** currently maintain a dedicated spoofed `User-Agent` override in `XCloudAPIClient`.
- Device-profile selection in the live app is therefore primarily driven by the xCloud device-info payload and the stream preference model, not by a separate browser-header shim.

---

## Region Selection Detail

The live region story is split across two flows:

1. `LibraryHostResolver` still resolves candidate hosts for library and login-era host discovery.
2. `StreamLaunchConfigurationService` and the stream region-selection policy compute the launch-time region preference that is passed into cloud-stream startup.

Current persisted knobs are:

- `guide.region_override` for a user-facing region override choice
- `stratix.stream.preferredRegionId` for the resolved preferred region identifier used by the launch configuration path

The current app does expose region override UI, but it is not yet a fully dynamic picker built from arbitrary returned region metadata. The visible settings surfaces are still curated around a constrained region list and diagnostics messaging.

---

## Game Pass Catalog Gallery UUIDs

Better xCloud uses `catalog.gamepass.com/sigls/{UUID}` to fetch curated game lists. These UUIDs could supplement Stratix’s home merchandising rails with categories like "Most Popular" or "Recently Added":

| Gallery | UUID |
|---------|------|
| All titles | `29a81209-df6f-41fd-a528-2ae6b91f719c` |
| Leaving soon | `393f05bf-e596-4ef6-9487-6d4fa0eab987` |
| Most popular | `e7590b22-e299-44db-ae22-25c61405454c` |
| Recently added | `44a55037-770f-4bbf-bde5-a9fa27dba1da` |
| Touch titles | `9c86f07a-f3e8-45ad-82a0-a1f759597059` |

`LibraryHomeMerchandisingCoordinator` uses `GamePassSiglClient` to discover merchandising aliases — the SIGL UUID approach is already the mechanism. Extending it to include the curated categories above is the natural path for enriching home rails.

---

## Useful Repo Surfaces

| Feature area | Primary file |
|-------------|-------------|
| Device spoofing + session start | `Packages/XCloudAPI/Sources/XCloudAPI/XCloudAPIClient.swift` |
| Region selection | `Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHostResolver.swift`, `Packages/StratixCore/Sources/StratixCore/Streaming/StreamLaunchConfigurationService.swift` |
| Stream settings | `Packages/StratixCore/Sources/StratixCore/SettingsStore.swift` |
| SDP processor (bitrate + codec) | `Packages/StreamingCore/Sources/StreamingCore/SDPProcessor.swift` |
| ICE processor (IPv6 preference) | `Packages/StreamingCore/Sources/StreamingCore/ICEProcessor.swift` |
| Stats HUD | `Apps/Stratix/Sources/Stratix/Features/Guide/` |
| Metal CAS sharpening | `Apps/Stratix/Sources/Stratix/Integration/WebRTC/MetalVideoRenderer.swift` |
| Home merchandising SIGL | `Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHomeMerchandisingCoordinator.swift` |

---

## Related Docs

- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [XCLOUD_PROTOCOL.md](XCLOUD_PROTOCOL.md)
- [CONFIGURATION.md](CONFIGURATION.md)
- [XBOX_ACHIEVEMENTS_AND_MEDIA.md](XBOX_ACHIEVEMENTS_AND_MEDIA.md)
- [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md)
