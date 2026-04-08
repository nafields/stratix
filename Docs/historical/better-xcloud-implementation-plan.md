# Historical Note

This file is a historical implementation-planning artifact and not the current source of truth for the live repo.

Use [BETTER_XCLOUD.md](../BETTER_XCLOUD.md), [FEATURE_INVENTORY.md](../FEATURE_INVENTORY.md), [PACKAGE_GUIDE.md](../PACKAGE_GUIDE.md), and [DESIGN_DECISIONS.md](../DESIGN_DECISIONS.md) for the current implementation shape.

The file-path and type references below were preserved from the original planning pass and should be treated as historical reference material, not as a current repo map.

# Better xCloud Integration Plan for Stratix (tvOS)

This implementation plan translates the priorities in `better-xcloud-features.md` into
concrete changes across Stratix packages and app layers as they were understood during the
original planning pass. The narrative is still useful for feature intent, but its file paths
and hook-point references are not maintained as live source-of-truth documentation.

---

## Goals

- Bring high-impact Better xCloud capabilities to native tvOS without browser-only hacks.
- Keep architecture boundaries intact (`XCloudAPI` for transport/API, `StreamingCore` for
  WebRTC/session mechanics, `DiagnosticsKit` for metrics, app target for UI/settings).
- Deliver incrementally with low-risk milestones that can be tested independently.

---

## Current State Audit

Understanding what is already partially wired prevents duplicating work.

### Already exists — needs wiring or extension

| Capability | What exists today | Gap |
|---|---|---|
| Wait time display | `WaitTimeResponse` in `GreenlightModels/Models.swift:149`; `StreamLifecycleState.waitingForResources(estimatedWaitSeconds:)` case at line 395 | No API call to the `/waittime/` endpoint; the estimated seconds value is never populated |
| Loading game art | `StreamStatusOverlay.connectingBackgroundArtwork` in `HomeStreamView.swift:205` already renders `overlayInfo.imageURL` with a gradient overlay | Art only shows if the title is already in the library cache (`coordinator.cloudLibraryItem(titleId:)` in `StreamView.swift:38`); no on-demand fetch at launch time |
| Stats HUD (overlay) | `StreamStatusOverlay.statsCard` at `HomeStreamView.swift:368` shows FPS, Bitrate, RTT from `session.stats` | Only 3 metrics; no jitter, decode time, packets lost, or region; shown only inside the full overlay, not as a persistent heads-up |
| Vibration | `GamepadHandler.sendHaptics(from:)` in `GamepadHandler.swift:153` fires CoreHaptics events | No intensity scaling; `ControllerSettings` (`Models.swift:473`) has `deadzone`, `invertY`, `swapAB`, `triggerSensitivity` but no `vibrationIntensity` |
| Resolution tiers | `StreamSettings.osName` in `XCloudAPIClient.swift:605` is hardcoded `"windows"` | Not exposed to user; no enum to select `720p`/`1080p`/`1080p-hq` |
| Locale preference | `XCloudAPIClient.startStream(type:targetId:locale:)` at line 157 accepts a locale string | Always called with the default `"en-US"`; no user setting persists and passes it through |
| Server region | `XCloudLibraryConfig.defaultLibraryHost` in `AppCoordinator.swift` is hardcoded to `eus` | Login response region list is not surfaced; no user preference |
| Controller shortcuts | Shortcut row in `StreamStatusOverlay` at `HomeStreamView.swift:378` is static text | No chord recognizer; `GamepadHandler.readFrame` in `GamepadHandler.swift:41` reads buttons but has no multi-button detection |
| Telemetry blocking | `XCloudAPIClient` uses `URLSession.shared` for all requests | No host filtering; telemetry and analytics requests go out freely |

### Deferred — not in scope for these milestones

- **Video sharpening (CAS/Clarity Boost):** requires a Metal compute pass on decoded video
  frames; significant GPU profiling needed on Apple TV hardware before committing.
- **Region restriction bypass (`X-Forwarded-For`):** legal/compliance review required before
  implementation.
- **Software volume boost beyond system volume:** needs a custom audio graph inserted into the
  WebRTC audio pipeline; high risk of clipping on Apple TV speakers.
- **Catalog `sigls`-driven home curation:** useful quality-of-life feature but not required
  for stream quality or session UX wins in this phase.

---

## Scope

### Phase-in (from tvOS high-priority list)

1. Queue wait time display
2. Loading-screen game art (on-demand fetch)
3. Stream stats HUD (expanded metrics + persistent overlay)
4. IPv6 ICE preference
5. Target resolution selector (`720p` / `1080p` / `1080p-hq`)
6. Preferred stream locale
7. Server region picker
8. Vibration intensity setting
9. Controller shortcut combos
10. Telemetry blocking toggle

---

## Architecture Mapping

| Feature | Files changed | Nature of change |
|---|---|---|
| Queue wait time | `XCloudAPIClient.swift`, `AppCoordinator.swift`, `HomeStreamView.swift` | Add `getWaitTime(sessionPath:)` method; poll after provisioning; populate `waitingForResources` with real seconds; add countdown label to `connectingOverlay` |
| Loading game art | `XCloudAPIClient.swift`, `GamePassCatalogClient.swift`, `AppCoordinator.swift`, `StreamView.swift` | Add `getHeroArt(titleId:)` helper using existing `XboxComProductDetailsClient`; fetch at stream launch; pass result into `StreamOverlayInfo` |
| Stats HUD | `DiagnosticsKit/StatsCollector.swift`, `GreenlightModels/Models.swift`, `StreamingCore/WebRTCBridge.swift`, `HomeStreamView.swift`, `StreamView.swift` | Expand `StatsCollector.update(...)` signature; add new fields to `StreamingStatsSnapshot`; wire RTCStatisticsReport; add always-visible compact HUD layer in `StreamView` |
| IPv6 ICE preference | `StreamingCore/ICEProcessor.swift`, `XCloudAPIClient.swift` | Add `sortPreferringIPv6(_:)` method to `ICEProcessor`; flip `isPreferredOutboundICECandidate` selection when preference is enabled |
| Resolution + `1080p-hq` | `GreenlightModels/Models.swift`, `XCloudAPIClient.swift`, `AppCoordinator.swift`, `SettingsView.swift` | Add `StreamResolutionMode` enum; map to `osName`/`displayWidth`/`displayHeight` in `StreamSettings`; expose picker in `SettingsView` |
| Preferred locale | `AppCoordinator.swift`, `SettingsView.swift` | Read BCP-47 locale from `@AppStorage`; thread it through `startStream` call |
| Region picker | `XCloudAPIClient.swift`, `AppCoordinator.swift`, `SettingsView.swift` | Parse region list from `/v2/login/user` response; persist preferred region; use it as `baseHost` |
| Vibration intensity | `GreenlightModels/Models.swift`, `GamepadHandler.swift`, `AppCoordinator.swift`, `SettingsView.swift` | Add `vibrationIntensity: Float` to `ControllerSettings`; scale motor percentages in `sendHaptics(from:)` |
| Shortcut combos | `InputBridge/GamepadHandler.swift`, `AppCoordinator.swift`, `HomeStreamView.swift` | Add `ChordRecognizer` to `GamepadHandler`; emit `ShortcutAction` events; handle in `AppCoordinator` |
| Telemetry blocking | `XCloudAPIClient.swift` | Introduce `BlockingURLProtocol` registered on an opt-in `URLSessionConfiguration`; controlled by a `@AppStorage` flag |

---

## Milestone 1 — Session Controls & Network Foundations

**Objective:** unlock user-controlled stream negotiation with minimal UI work.

### 1.1 Resolution tier model and `osName` mapping

**File:** `Packages/GreenlightModels/Sources/GreenlightModels/Models.swift`

Add after the existing `StreamKind` enum:

```swift
public enum StreamResolutionMode: String, CaseIterable, Sendable, Codable {
    case auto       // osName = "android", 1280×720
    case p720       // osName = "android", 1280×720
    case p1080      // osName = "windows", 1920×1080
    case p1080HQ    // osName = "tizen",   3840×2160 display hint

    public var osName: String {
        switch self {
        case .auto, .p720: return "android"
        case .p1080:       return "windows"
        case .p1080HQ:     return "tizen"
        }
    }

    public var displayWidth: Int {
        switch self {
        case .auto, .p720: return 1280
        case .p1080:       return 1920
        case .p1080HQ:     return 3840
        }
    }

    public var displayHeight: Int {
        switch self {
        case .auto, .p720: return 720
        case .p1080:       return 1080
        case .p1080HQ:     return 2160
        }
    }
}
```

Also add the remaining preference types:

```swift
public struct StreamPreferences: Sendable, Equatable {
    public var resolution: StreamResolutionMode = .p1080
    public var locale: String = "en-US"         // BCP-47
    public var preferIPv6: Bool = false
    public var preferredRegionId: String? = nil  // nil = use server default
    public init() {}
}
```

**File:** `Packages/XCloudAPI/Sources/XCloudAPI/XCloudAPIClient.swift`

Change `startStream` to accept a `StreamPreferences`:

```swift
public func startStream(
    type: StreamKind,
    targetId: String,
    preferences: StreamPreferences = StreamPreferences()
) async throws -> StreamSessionStartResponse
```

Update `StreamSettings` (line 596) to be initialized from preferences instead of using
hardcoded values. The `osName`, `locale`, and the display dimensions in `makeDeviceInfo`
should all derive from `preferences.resolution`.

The existing `makeDeviceInfo(locale:)` static method at line 121 builds a JSON string with
hardcoded `"windows"` and `1920×1080`. Extend it to accept `resolution: StreamResolutionMode`
so it can emit the right `os.name` and `displayInfo` block for each tier. This is important
because the Xbox backend checks both the `settings.osName` in the POST body **and** the
`X-MS-Device-Info` header.

### 1.2 Login region parsing and region selection

**File:** `Packages/XCloudAPI/Sources/XCloudAPI/XCloudAPIClient.swift`

The `/v2/login/user` response (handled in `MicrosoftAuthService.swift`) returns a `gsToken`
and a list of available regions. Add a `LoginRegion` model and expose the region list from
`MicrosoftAuthService.exchangeGSSVToken(...)`:

```swift
public struct LoginRegion: Codable, Sendable, Equatable {
    public let name: String
    public let baseUri: String
    public let isDefault: Bool
}
```

Expose a `preferredRegion(from regions: [LoginRegion], preference: String?) -> LoginRegion`
helper that returns the user-pinned region if available, otherwise the default from the server.

**File:** `Packages/GreenlightCore/Sources/GreenlightCore/AppCoordinator.swift`

After authentication, store the available regions and update `XCloudAPIClient.baseHost`
according to `StreamPreferences.preferredRegionId`. Expose `availableRegions: [LoginRegion]`
as a `@Published` property so `SettingsView` can display a picker.

### 1.3 IPv6 ICE preference

**File:** `Packages/StreamingCore/Sources/StreamingCore/ICEProcessor.swift`

The current `ICEProcessor` (`expandCandidates`) expands Teredo addresses but does not sort
outbound candidates. The outbound preference is currently in `XCloudAPIClient`'s
`isPreferredOutboundICECandidate` (line 534), which filters to IPv4 UDP.

Add a `preferIPv6` flag to `ICEProcessor`:

```swift
public struct ICEProcessor: Sendable {
    public var preferIPv6: Bool = false
    // ...
}
```

Add a `sortCandidates(_ candidates: [IceCandidatePayload]) -> [IceCandidatePayload]` method
that, when `preferIPv6` is true, moves IPv6 candidates before IPv4 within the same transport
type. When false, the existing IPv4-first behaviour is preserved.

In `XCloudAPIClient.sendICECandidates`, pass the sorted+filtered list through before
encoding, and thread the `preferIPv6` setting from `StreamPreferences`.

### 1.4 Settings persistence

All new preferences read and write through `@AppStorage` using well-defined keys. Suggested
key space:

| Key | Type | Default |
|---|---|---|
| `stratix.stream.resolution` | `String` (raw value of `StreamResolutionMode`) | `"p1080"` |
| `stratix.stream.locale` | `String` | `"en-US"` |
| `stratix.stream.preferIPv6` | `Bool` | `false` |
| `stratix.stream.preferredRegionId` | `String` | `""` (empty = use server default) |
| `stratix.controller.vibrationIntensity` | `Double` | `1.0` |
| `stratix.controller.shortcutsEnabled` | `Bool` | `true` |
| `stratix.privacy.blockTracking` | `Bool` | `false` |

**AppCoordinator** reads these at startup and builds a `StreamPreferences` value to pass into
every `startStream` call, so no SwiftUI preference state leaks into the session layer.

### Milestone 1 acceptance criteria

- Changing resolution in `SettingsView` alters the `osName` and display dimensions in the
  next `startStream` POST body (verify with Charles or `OSLog` at the `post` call site).
- The region list is populated after sign-in and the user-pinned region is used as `baseHost`.
- When `preferIPv6` is on, ICE candidate sort puts IPv6 UDP before IPv4 UDP in outbound list.
- Unit tests cover:
  - `StreamResolutionMode.osName` mapping for all four cases.
  - `ICEProcessor.sortCandidates` ordering under both `preferIPv6 = true` and `false`.
  - `preferredRegion(from:preference:)` returns pinned region when available, default otherwise.

---

## Milestone 2 — Launch Experience (Wait Time + Art)

**Objective:** improve pre-stream UX while the allocation queue is running.

### 2.1 Wait-time polling

**File:** `Packages/XCloudAPI/Sources/XCloudAPI/XCloudAPIClient.swift`

Add:

```swift
/// GET {region}/v1/waittime/{titleId}
/// Returns WaitTimeResponse. Returns nil when the endpoint returns 404/204 (title not queued).
public func getWaitTime(sessionPath: String, titleId: String) async throws -> WaitTimeResponse?
```

`WaitTimeResponse` is already defined in `GreenlightModels/Models.swift:149`:

```swift
public struct WaitTimeResponse: Codable, Sendable, Equatable {
    public let estimatedTotalWaitTimeInSeconds: Int?
}
```

**File:** `Packages/GreenlightCore/Sources/GreenlightCore/AppCoordinator.swift`

In the session provisioning loop (currently polling `getSessionState`), add a parallel
`Task` that polls `getWaitTime` every 5 seconds while the lifecycle is
`.waitingForResources`. On each successful response, update the lifecycle to
`.waitingForResources(estimatedWaitSeconds: response.estimatedTotalWaitTimeInSeconds)`.

The `StreamLifecycleState.waitingForResources(estimatedWaitSeconds:)` associated value is
already declared at `Models.swift:395` — it just needs to be populated.

### 2.2 Loading screen countdown

**File:** `Apps/AppleTVGreenlight/Sources/AppleTVGreenlight/Views/HomeStreamView.swift`

`StreamStatusOverlay.connectingOverlay` (line 181) currently shows a `ProgressView` and
`stateLabel`. Extend `stateLabel` to include the estimated wait duration when the lifecycle
case has a non-nil value:

```swift
private var stateLabel: String {
    switch session.lifecycle {
    // ...
    case .waitingForResources(let secs):
        if let secs, secs > 0 {
            return "Queue: ~\(secs)s"
        }
        return "Waiting for server..."
    // ...
    }
}
```

Additionally, add a countdown `Text` view below the `ProgressView` in `connectingOverlay`
that displays a progress bar or ring when wait time is known, degrading to a plain spinner
when the endpoint returns nothing.

### 2.3 On-demand hero art fetch

**Gap identified:** `StreamView.swift:38` calls `coordinator.cloudLibraryItem(titleId:)`
which returns a `CloudLibraryItem` if the title is already in the cached library. If the
user deep-links to a title that hasn't been loaded yet (e.g., via MRU or search), the art
is nil and the loading screen shows the gradient fallback.

**Fix:** add a `fetchHeroArt(titleId:) async -> URL?` method to `AppCoordinator` that:
1. Checks the cached `cloudLibraryItem(titleId:)` first (zero cost for the common case).
2. Falls back to `XboxComProductDetailsClient.fetchProductDetails(titleId:)` which is
   already implemented in `XboxComProductDetailsClient.swift`.
3. Caches the result so repeat launches don't re-fetch.

Call this method at the start of `startCloudStream` and write the result into a
`@Published var launchHeroURL: URL?` property on `AppCoordinator`. `StreamView`
reads `coordinator.launchHeroURL` and passes it into `StreamOverlayInfo.imageURL`.

`connectingBackgroundArtwork` at `HomeStreamView.swift:205` already handles an optional
`imageURL` and renders a gradient fallback — no structural changes needed there.

### Milestone 2 acceptance criteria

- When the server allocates a queue slot, the countdown is visible and updates every poll.
- If the wait-time API returns 404 or an empty value, the loading screen degrades gracefully
  with a spinner (no visible error; the `Task` is swallowed with a structured logger warning).
- Loading art appears for known titles within the first poll cycle.
- For unknown titles, art appears as soon as the `fetchProductDetails` response arrives.
- For completely unknown titles with no artwork, the gradient fallback is shown.

---

## Milestone 3 — In-Stream Visibility & Control

**Objective:** add diagnostics and quick actions comparable to Better xCloud utility.

### 3.1 Expanded stats model

**File:** `Packages/GreenlightModels/Sources/GreenlightModels/Models.swift`

Extend `StreamingStatsSnapshot` (line 278) with additional fields:

```swift
public struct StreamingStatsSnapshot: Sendable, Equatable {
    public let timestamp: Date
    // Existing
    public let bitrateKbps: Int?
    public let framesPerSecond: Double?
    public let roundTripTimeMs: Double?
    // New
    public let jitterMs: Double?
    public let decodeTimeMs: Double?
    public let packetsLost: Int?
    public let framesLost: Int?
    public let activeRegion: String?
    // ...
}
```

**File:** `Packages/DiagnosticsKit/Sources/DiagnosticsKit/StatsCollector.swift`

Expand `update(...)` to accept the full set:

```swift
public func update(
    bitrateKbps: Int?,
    framesPerSecond: Double?,
    roundTripTimeMs: Double?,
    jitterMs: Double?,
    decodeTimeMs: Double?,
    packetsLost: Int?,
    framesLost: Int?,
    activeRegion: String?
) { ... }
```

**File:** `Packages/StreamingCore/Sources/StreamingCore/WebRTCBridge.swift`

The WebRTC framework emits `RTCStatisticsReport` on a configurable interval. Parse the
inbound-rtp and outbound-rtp stats entries and call `StatsCollector.update(...)` with the
extracted values. The relevant RTCStatistics keys are:
- `inbound-rtp` → `bytesReceived`, `framesPerSecond`, `packetsLost`, `jitter`, `framesDecoded`
- `candidatePair` → `currentRoundTripTime`

### 3.2 Persistent stats HUD

**File:** `Apps/AppleTVGreenlight/Sources/AppleTVGreenlight/Views/StreamView.swift`

Add a compact HUD overlay to `StreamView.body` (the `ZStack` at line 27) that is always
visible during live streaming and is separate from the full menu overlay. It should:

- Read from `session.stats` on a 1-second `Timer` publish.
- Show 4–6 values in a single horizontal strip (FPS, bitrate, RTT, jitter, packets lost).
- Use `GamePassTheme` colours: white text, dark translucent background, top-right position.
- Be controlled by a `@AppStorage("stratix.stream.showStatsHUD") var showStatsHUD: Bool`.
- Be toggleable by the controller shortcut (see §3.4).

This is a **new** overlay layer; the existing `StreamStatusOverlay.statsCard` inside the
menu panel (which already works) is retained for the full overlay view.

### 3.3 Stats HUD in settings

**File:** `Apps/AppleTVGreenlight/Sources/AppleTVGreenlight/Views/SettingsView.swift`

The "Streaming" card (line 53) already has `settingsLine(title: "Stats Overlay", ...)` as a
read-only label. Replace it with an interactive toggle `Toggle("Stats HUD", isOn: $showStatsHUD)`.

Also add a "Position" picker (top-left / top-right / bottom-left) stored in
`@AppStorage("stratix.stream.statsHUDPosition")`.

### 3.4 Controller shortcut chord recognizer

**File:** `Packages/InputBridge/Sources/InputBridge/GamepadHandler.swift`

Add a `ShortcutAction` enum and a `ChordRecognizer` struct:

```swift
public enum ShortcutAction: Sendable, Equatable {
    case toggleStatsHUD
    case toggleStreamMenu
    case disconnectStream
    case muteToggle
}

public struct ChordDefinition: Sendable {
    public let buttons: GamepadButtons  // buttons that must all be pressed simultaneously
    public let holdDurationMs: Int      // 0 = instant, >0 = must be held
    public let action: ShortcutAction
}
```

`ChordRecognizer` tracks the current `GamepadButtons` bitmask and the timestamp of when the
current combination was first seen. When a combination matches a registered `ChordDefinition`
and the hold duration has elapsed, it fires the corresponding `ShortcutAction`.

Default bindings:

| Chord | Hold | Action |
|---|---|---|
| LB + RB | 0 ms | `toggleStatsHUD` |
| View + Menu | 800 ms | `toggleStreamMenu` |
| L3 + R3 | 800 ms | `disconnectStream` |

The existing `GamepadHandler.readFrame` already detects View + Menu to emit `.nexus`
(line 68). The chord recognizer should be an additional layer that runs after the frame is
built, checking for combinations that shouldn't be forwarded to the game as input.

**File:** `Packages/GreenlightCore/Sources/GreenlightCore/AppCoordinator.swift`

`AppCoordinator` owns the input polling loop. Add a `ChordRecognizer` instance and call
`recognizer.process(frame:)` each poll cycle. Map emitted `ShortcutAction` values to
published tokens (similar to the existing `streamOverlayRequestToken` pattern):

```swift
@Published public private(set) var statsHUDToggleToken: Int = 0
@Published public private(set) var streamMenuToggleToken: Int = 0
```

**File:** `Apps/AppleTVGreenlight/Sources/AppleTVGreenlight/Views/StreamView.swift`

`.onChange(of: coordinator.statsHUDToggleToken)` flips `showStatsHUD`.
`.onChange(of: coordinator.streamMenuToggleToken)` flips `showOverlay` (same pattern as the
existing `streamOverlayRequestToken` handler at line 96).

### 3.5 Vibration intensity

**File:** `Packages/GreenlightModels/Sources/GreenlightModels/Models.swift`

Add `vibrationIntensity: Float = 1.0` to `ControllerSettings` (line 473). Range 0.0–1.0.

**File:** `Packages/InputBridge/Sources/InputBridge/GamepadHandler.swift`

In `sendHaptics(from report:)` at line 153, scale each motor intensity by
`settings.vibrationIntensity` before creating the `CHHapticEvent`. The `VibrationReport`
motor percentages are already 0–1 floats, so a simple multiplication suffices:

```swift
let scaled = intensity * settings.vibrationIntensity
```

**File:** `Apps/AppleTVGreenlight/Sources/AppleTVGreenlight/Views/SettingsView.swift`

Add a "Vibration Intensity" slider (0–100%) to the Streaming card, backed by
`@AppStorage("stratix.controller.vibrationIntensity")`.

### Milestone 3 acceptance criteria

- Stats HUD appears at the configured corner during live streaming without opening the menu.
- HUD updates every second and shows all 6+ metrics.
- LB + RB toggles the HUD on/off without any input being sent to the game.
- L3 + R3 held for 800 ms triggers the disconnect prompt.
- Vibration intensity slider visibly affects haptic strength on a connected controller.

---

## Milestone 4 — Privacy Controls

**Objective:** provide optional telemetry hardening at the transport layer.

### 4.1 Telemetry host blocklist

**New file:** `Packages/XCloudAPI/Sources/XCloudAPI/BlockingURLProtocol.swift`

Implement a `URLProtocol` subclass that intercepts requests whose hosts match a static blocklist
and fails them immediately with a `URLError(.cancelled)`. This is the same mechanism used by
content blockers on iOS.

Blocked hosts (from `better-xcloud-features.md` §1, Telemetry section):

```swift
static let blockedHosts: Set<String> = [
    "arc.msn.com",
    "browser.events.data.microsoft.com",
    "dc.services.visualstudio.com",
    "o427368.ingest.sentry.io",
    "mscom.demdex.net"
]
```

**File:** `Packages/XCloudAPI/Sources/XCloudAPI/XCloudAPIClient.swift`

Add a factory method:

```swift
public static func makeBlockingSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [BlockingURLProtocol.self] + (config.protocolClasses ?? [])
    return URLSession(configuration: config)
}
```

`AppCoordinator` creates the `XCloudAPIClient` with `makeBlockingSession()` when
`blockTracking` is enabled, otherwise `URLSession.shared` (current behaviour).

**Note:** the blocking session should only be used for API calls that do not require
streaming-level performance. The WebRTC native stack uses its own transport and is not
affected.

### 4.2 Settings toggle

**File:** `Apps/AppleTVGreenlight/Sources/AppleTVGreenlight/Views/SettingsView.swift`

Add a "Privacy" settings card with a `Toggle("Block Telemetry", isOn: $blockTracking)`
(`@AppStorage("stratix.privacy.blockTracking")`). Explain in a subtitle that enabling this
blocks analytics and error reporting requests, not Xbox gameplay data.

Changing this preference takes effect on the next app launch (the `URLSession` instance is
created once in `AppCoordinator.init`). Warn the user of this in the UI with a caption:
"Change takes effect after restart."

### 4.3 Debug counters

**File:** `Packages/DiagnosticsKit/Sources/DiagnosticsKit/Logger.swift`

Add a `blockedRequestCount` counter (increment inside `BlockingURLProtocol`) readable from
`DiagnosticsKit.Logger.shared.blockedRequestCount`. Log this value to the stats HUD in
`#if DEBUG` builds only.

### Milestone 4 acceptance criteria

- Enabling tracking block prevents HTTP requests to all five telemetry hosts (verify by
  injecting a `URLProtocol` test double in unit tests that asserts no requests escape).
- Core auth (`/v2/login/user`), library (`/v2/titles`), and streaming (ICE/SDP) APIs
  continue functioning while blocking is active.
- Turning the setting off (and restarting) restores requests to telemetry hosts.

---

## Data Model Additions (summary)

All new types live in `Packages/GreenlightModels/Sources/GreenlightModels/Models.swift`:

| New type | Purpose |
|---|---|
| `StreamResolutionMode` | `.auto`, `.p720`, `.p1080`, `.p1080HQ` with `osName`/dimension helpers |
| `StreamPreferences` | Composite preference bag: resolution, locale, IPv6, region, block-tracking |
| `LoginRegion` | Region entry from `/v2/login/user` (name, baseUri, isDefault) |

Extended types:

| Existing type | Extension |
|---|---|
| `StreamingStatsSnapshot` | Add jitter, decode time, packets/frames lost, active region |
| `ControllerSettings` | Add `vibrationIntensity: Float` |

New types in `Packages/InputBridge/Sources/InputBridge/`:

| New type | Purpose |
|---|---|
| `ShortcutAction` | Enum of in-app actions a chord can trigger |
| `ChordDefinition` | Button mask + hold duration + action |
| `ChordRecognizer` | Stateful recognizer called per input frame |

---

## Testing Strategy

### Unit tests

**`XCloudAPI`**
- `StreamResolutionMode.osName` returns correct string for all four cases.
- `StreamSettings` encoding with each resolution produces the expected JSON `osName` field.
- `preferredRegion(from:preference:)` returns pinned region when present, default otherwise.
- `getWaitTime` decodes a sample JSON response into `WaitTimeResponse` correctly.
- `BlockingURLProtocol` intercepts requests to each blocked host and passes non-blocked hosts.

**`StreamingCore`**
- `ICEProcessor.sortCandidates` places IPv6 UDP candidates before IPv4 UDP when `preferIPv6 = true`.
- `ICEProcessor.sortCandidates` produces stable IPv4-first output when `preferIPv6 = false`.
- Existing `ICEProcessorTests.swift` Teredo expansion tests continue to pass.

**`DiagnosticsKit`**
- `StatsCollector.update(...)` with all-nil fields produces an all-nil snapshot.
- `StatsCollector.update(...)` with all fields set produces matching snapshot values.
- Colour-threshold helper (good/warning/critical) for each metric type.

**`InputBridge`**
- `ChordRecognizer` fires action when all buttons in a chord are pressed simultaneously
  (instant trigger with `holdDurationMs = 0`).
- `ChordRecognizer` does not fire before the hold duration elapses.
- `ChordRecognizer` resets when any required button is released mid-hold.

### Preview / smoke tests

- `StreamStatusOverlay` with `waitingForResources(estimatedWaitSeconds: 45)` shows "Queue: ~45s".
- `StreamStatusOverlay` with `waitingForResources(estimatedWaitSeconds: nil)` shows spinner only.
- `StreamStatusOverlay` with an `imageURL` renders the image in the connecting background.
- Stats HUD at each position corner (top-left, top-right, bottom-left) in a `PreviewProvider`.

### Manual device validation

- Verify resolution tiers produce different stream quality by comparing start-stream POST
  payloads and observed frame dimensions for `p720`, `p1080`, and `p1080HQ`.
- Verify controller chord triggers are reliable at 60 Hz polling.
- Verify vibration intensity slider affects haptic strength on a Bluetooth controller.
- Verify tracking block does not break auth, library loading, or stream startup.

---

## Rollout & Risk Management

- **Resolution tiers:** ship `p720` and `p1080` in Milestone 1; gate `p1080HQ` behind a
  separate `@AppStorage("stratix.stream.enableHQTier")` flag that defaults to `false` until
  the quality difference has been validated on real Apple TV hardware.
- **IPv6:** off by default. If enabling it causes ICE failures (e.g., Xbox servers dropping
  IPv6-first candidates), turning it off restores the existing IPv4-first path with no code
  changes.
- **Telemetry blocking:** off by default. The `URLProtocol` intercept is isolated to the
  opt-in `URLSession`; `URLSession.shared` is completely unaffected.
- **Chord recognizer:** add structured logging around every fired shortcut action so
  accidental triggers are detectable from device logs during QA.
- **Vibration intensity:** if the `VibrationReport` amplitudes are already pre-scaled by the
  server, a double-scale might produce unpleasant behaviour. Log the raw motor percentages
  before and after scaling in debug builds during initial device validation.

---

## Suggested Execution Order (2-Week Sprints)

1. **Sprint 1 — Milestone 1:** Resolution model, `osName` mapping, locale threading, region
   parsing, IPv6 ICE preference, settings persistence. Unblocks all downstream features.
2. **Sprint 2 — Milestone 2:** Wait-time polling, countdown UI, on-demand hero art fetch.
   Depends on Milestone 1's `AppCoordinator` plumbing.
3. **Sprint 3 — Milestone 3:** Expanded stats model, persistent HUD layer, chord recognizer,
   vibration intensity. Depends on Milestone 1 for preference storage.
4. **Sprint 4 — Milestone 4:** Telemetry blocking, debug counters, integration hardening,
   full regression pass on device.

This sequence front-loads stream quality and session reliability improvements before advanced
rendering or heavy DSP work.
