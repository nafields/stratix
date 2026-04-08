# Historical Note

This file is a historical feature and endpoint reference derived from Better xCloud and is not the current source of truth for the live Stratix implementation.

Use [BETTER_XCLOUD.md](../BETTER_XCLOUD.md), [FEATURE_INVENTORY.md](../FEATURE_INVENTORY.md), [DESIGN_DECISIONS.md](../DESIGN_DECISIONS.md), and [XCLOUD_PROTOCOL.md](../XCLOUD_PROTOCOL.md) for current-state guidance.

# Better xCloud — Feature & Endpoint Reference

Source: https://github.com/redphx/better-xcloud (v6.7.7)

This document catalogues every API endpoint, setting, and feature from the Better
xCloud userscript, annotated for relevance to Stratix (tvOS). Use as a gap-analysis
and roadmap reference.

---

## 1. API Endpoints

### Authentication / Token Exchange

| Endpoint | Method | What It Gets |
|----------|--------|--------------|
| `http://gssv.xboxlive.com/` | — | Relying-party claim for GSSV tokens stored in `localStorage('xboxcom_xbl_user_info')` |
| `https://xhome.gssv-play-prod.xboxlive.com/v2/login/user` | POST | Exchanges GSSV token for xHome `gsToken` + region list. Body: `{ offeringId: "xhome", token }` |
| `https://*.core.gssv-play-prod.xboxlive.com/v2/login/user` | POST | Same for xCloud. Returns `gsToken` + region list. Better xCloud also injects `X-Forwarded-For` here to bypass region locks. |

### Remote Play / xHome

| Endpoint | Method | What It Gets |
|----------|--------|--------------|
| `{region.baseUri}/v6/servers/home?mr=50` | GET | Lists up to 50 home consoles. Auth: `Bearer {XHOME_TOKEN}`. Returns `{ results: [...] }` |
| `{region}/sessions/home/...` (relayed) | various | All xHome session sub-endpoints — same shape as xCloud but routed through the working Remote Play server |
| `{region}/inputconfigs` | POST | Returns `supportedInputTypes` per title. Used to detect native touch support. xHome-specific. |

### xCloud Session Lifecycle

| Endpoint | Method | What It Gets / What Is Patched |
|----------|--------|-------------------------------|
| `{region}/sessions/cloud/play` | POST | Starts a cloud session. Better xCloud modifies the body: sets `settings.osName` (`windows`=1080p, `android`=720p, `tizen`=1080p-hq) and `settings.locale`. |
| `{region}/sessions/cloud/{id}/configuration` | GET | Returns `clientStreamingConfigOverrides`. Better xCloud patches the response to force-enable vibration, touch input, microphone, and MKB. |
| `{region}/sessions/{id}/ice` | GET | WebRTC ICE candidates. Better xCloud rewrites these to prefer IPv6 and inject console IP:port pairs (from the `/configuration` response) as additional candidates. |
| `{region}/.../waittime/{titleId}` | GET | Returns `{ estimatedAllocationTimeInSeconds, estimatedTotalWaitTimeInSeconds }` — used to show a queue timer on the loading screen. |
| `{region}/v2/titles` | GET/POST | Cloud-enabled game list including `supportedInputTypes` per title. |
| `{region}/v2/titles/mru` | GET | Most-recently-used titles — same shape. |
| `{region}/v1/waittime/{id}` | GET | Per-title queue wait time (alternate endpoint used by xcloud-api.ts). |

### Game Pass Catalog

| Endpoint | Method | What It Gets |
|----------|--------|--------------|
| `https://catalog.gamepass.com/v3/products?market={m}&language={l}&hydration=RemoteHighSapphire0` | POST | Batch product detail lookup. Body: `{ Products: [storeId] }`. Returns hero/tile image URLs + store metadata. Used for loading-screen art. |
| `https://catalog.gamepass.com/sigls/{UUID}` | GET | Game list by gallery type (see Gallery UUIDs below). Response is intercepted by Better xCloud to inject extra title IDs. |

### Microsoft / Feature Gates

| Endpoint | Method | What It Gets |
|----------|--------|--------------|
| `https://displaycatalog.mp.microsoft.com/v7.0/products/lookup?...&alternateIdType=XboxTitleId` | GET | Xbox title product data by `XboxTitleId`. |
| `https://emerald.xboxservices.com/xboxcomfd/experimentation` | GET | Feature gate flags. Better xCloud intercepts and modifies these before the page sees them (e.g. force-enable Remote Play, MKB). |

### Telemetry — Blocked by Better xCloud

| Endpoint | Notes |
|----------|-------|
| `https://arc.msn.com` | Microsoft ad/analytics |
| `https://browser.events.data.microsoft.com` | Browser telemetry |
| `https://dc.services.visualstudio.com` | Application Insights |
| `https://2c06dea3f26c40c69b8456d319791fd0@o427368.ingest.sentry.io` | Sentry error reporting |
| `https://mscom.demdex.net` | Adobe audience manager |

### Social Features — Optionally Blocked

| Endpoint | Method | What It Gets |
|----------|--------|--------------|
| `https://peoplehub.xboxlive.com/users/me/people/social` | GET | Friends list with presence |
| `https://peoplehub.xboxlive.com/users/me/people/recommendations` | GET | Suggested friends |
| `https://notificationinbox.xboxlive.com/` | GET | Notification inbox |
| `https://xblmessaging.xboxlive.com/network/xbox/users/me/inbox` | GET | Chat inbox |
| `https://accounts.xboxlive.com/family/memberXuid` | GET | Family member XUIDs |

---

## 2. catalog.gamepass.com Gallery UUIDs

Used with `catalog.gamepass.com/sigls/{UUID}`:

| Gallery | UUID |
|---------|------|
| ALL | `29a81209-df6f-41fd-a528-2ae6b91f719c` |
| ALL_WITH_BYOG | `ce573635-7c18-4d0c-9d68-90b932393470` |
| LEAVING_SOON | `393f05bf-e596-4ef6-9487-6d4fa0eab987` |
| MOST_POPULAR | `e7590b22-e299-44db-ae22-25c61405454c` |
| NATIVE_MKB | `8fa264dd-124f-4af3-97e8-596fcdf4b486` |
| RECENTLY_ADDED | `44a55037-770f-4bbf-bde5-a9fa27dba1da` |
| TOUCH | `9c86f07a-f3e8-45ad-82a0-a1f759597059` |
| ALL_BYOG_V3 | `e78d9a61-5ef4-43af-b400-edba1250b18e` |
| FRESNO_F2P | `d8f4afcd-882a-49e3-86b3-f61fa0172b75` |
| FRESNO_MAIN | `51f14e5d-bdcb-4e04-b9cb-76e5057702df` |

---

## 3. Feature Gates Overridden on experimentation Endpoint

Better xCloud modifies the `emerald.xboxservices.com/xboxcomfd/experimentation` response before the page processes it:

| Flag | Forced Value |
|------|-------------|
| `EnableRemotePlay` | true |
| `EnableConsoles` | true |
| `EnableMouseAndKeyboard` | true / false (based on `nativeMkb.mode` setting) |
| `EnableGuideChatTab` | false (when chat blocking is active) |
| `EnableFriendsAndFollowers` | false (when friends blocking is active) |
| `PwaPrompt`, `EnableWifiWarnings`, `EnableUpdateRequiredPage`, `ShowForcedUpdateScreen`, `EnableTakControlResizing`, `EnableLazyLoadedHome` | all overridden in base object |

---

## 4. Device Info Injected (`x-ms-device-info` Header)

Set on all xhome and xcloud session requests:

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

OS name per resolution target:
- `1080p-hq` → `tizen` (Samsung Smart TV — unlocks highest quality tier)
- `1080p` → `windows`
- `720p` / `auto` → `android`

---

## 5. Browser API Patches (web-only context)

| API | Patch |
|-----|-------|
| `RTCPeerConnection.setLocalDescription()` | Reorder H.264 codec profiles in SDP; apply `b=AS:` bitrate limits |
| `RTCRtpTransceiver` | Check codec support; manipulate codec preference ordering |
| `AudioContext` constructor | Force `latencyHint: 0`; insert gain node for volume boost |
| `HTMLMediaElement.play()` | Skip splash video; initialize stream player |
| `Element.requestPointerLock()` | Custom pointer-lock state management for MKB mode |
| `HTMLCanvasElement.getContext()` | Reduce antialiasing; force low-power GPU for touch overlays |

---

## 6. Bypass Server IPs (X-Forwarded-For injection)

Injected on `/v2/login/user` to spoof geographic location:

| Code | Country | IP |
|------|---------|-----|
| `br` | Brazil | `169.150.198.66` |
| `kr` | Korea | `121.125.60.151` |
| `jp` | Japan | `138.199.21.239` |
| `pl` | Poland | `45.134.212.66` |
| `us` | United States | `143.244.47.65` |

---

## 7. User-Agent Profiles

| Profile | UA |
|---------|----|
| `windows-edge` | Windows 10 + Chrome/Edge |
| `macos-safari` | macOS + Safari 16.5 |
| `smarttv-generic` | Current UA + "Smart-TV" appended |
| `smarttv-tizen` | Samsung Tizen 7.0 Smart TV |
| `vr-oculus` | Current UA + "OculusBrowser VR" appended |
| `default` | Unmodified |
| `custom` | User-defined string |

---

## 8. Settings — Full Reference

### Global Settings

#### Network / Server
| Key | Type | Purpose |
|-----|------|---------|
| `server.region` | string | Preferred xCloud server region |
| `server.bypassRestriction` | string | Country code to spoof via X-Forwarded-For (`br/jp/kr/pl/us`) |
| `server.ipv6.prefer` | boolean | Prefer IPv6 ICE candidates for xCloud |
| `xhome.ipv6.prefer` | boolean | Prefer IPv6 ICE candidates for Remote Play |

#### Stream Quality
| Key | Type | Values |
|-----|------|--------|
| `stream.video.resolution` | StreamResolution | `720p`, `1080p`, `1080p-hq`, `auto` |
| `stream.video.codecProfile` | CodecProfile | `default`, `low`, `normal`, `high` |
| `stream.video.maxBitrate` | number | Max video bitrate (kbps) |
| `stream.video.combineAudio` | boolean | Combine audio+video into one stream (fixes audio lag) |
| `stream.video.preventResolutionDrops` | boolean | Prevent auto resolution drops under decode pressure |
| `stream.locale` | StreamPreferredLocale | Override stream audio/UI locale |
| `xhome.video.resolution` | StreamResolution | Resolution for Remote Play sessions |

#### Remote Play
| Key | Type | Purpose |
|-----|------|---------|
| `xhome.video.resolution` | StreamResolution | 720p or 1080p |
| `xhome.ipv6.prefer` | boolean | Prefer IPv6 for ICE |

#### Privacy / Blocking
| Key | Type | Purpose |
|-----|------|---------|
| `block.tracking` | boolean | Block all telemetry / analytics requests |
| `block.features` | BlockFeature[] | Block: `chat`, `friends`, `notifications-invites`, `notifications-achievements`, `remote-play` |

#### Loading Screen
| Key | Type | Purpose |
|-----|------|---------|
| `loadingScreen.gameArt.show` | boolean | Show game hero art background while loading |
| `loadingScreen.waitTime.show` | boolean | Show estimated queue wait time |
| `loadingScreen.rocket` | string | `show`, `hide`, `hide-queue` |

#### UI
| Key | Type | Purpose |
|-----|------|---------|
| `ui.controllerFriendly` | boolean | Controller-friendly navigation mode |
| `ui.layout` | UiLayout | `tv`, `normal`, `default` |
| `ui.hideScrollbar` | boolean | Hide page scrollbar |
| `ui.hideSections` | UiSection[] | Hide: `all-games`, `friends`, `most-popular`, `native-mkb`, `news`, `touch`, `byog`, `recently-added`, `leaving-soon`, `genres` |
| `ui.gameCard.waitTime.show` | boolean | Show wait time on game cards |
| `ui.streamMenu.simplify` | boolean | Simplify in-stream system menu |
| `ui.feedbackDialog.disabled` | boolean | Disable post-stream feedback dialog |
| `ui.splashVideo.skip` | boolean | Skip intro splash video |
| `ui.reduceAnimations` | boolean | Reduce UI animations |
| `ui.theme` | UiTheme | `default`, `dark-oled` |

#### Audio (Global)
| Key | Type | Purpose |
|-----|------|---------|
| `audio.mic.onPlaying` | boolean | Auto-enable mic when stream starts |
| `audio.volume.booster.enabled` | boolean | Enable volume booster (>100%) |

#### Game-Specific
| Key | Type | Purpose |
|-----|------|---------|
| `game.fortnite.forceConsole` | boolean | Force Fortnite console mode |
| `nativeMkb.forcedGames` | string[] | Title IDs forced into native MKB |

---

### Per-Stream Settings

#### Video
| Key | Type | Values |
|-----|------|--------|
| `video.player.type` | StreamPlayerType | `default` (HTML video), `webgl2`, `webgpu` |
| `video.player.powerPreference` | VideoPowerPreference | `default`, `low-power`, `high-performance` |
| `video.processing` | StreamVideoProcessing | `usm` (Unsharp Mask), `cas` (AMD FidelityFX CAS) |
| `video.processing.sharpness` | number | Sharpness intensity |
| `video.maxFps` | number | Frame rate cap |
| `video.ratio` | VideoRatio | `16:9`, `16:10`, `18:9`, `21:9`, `4:3`, `fill`, etc. |
| `video.brightness` | number | Brightness adjustment |
| `video.contrast` | number | Contrast adjustment |
| `video.saturation` | number | Saturation adjustment |
| `video.position` | VideoPosition | `center`, `top`, `top-half`, `bottom`, `bottom-half` |

#### Audio (Per-Stream)
| Key | Type | Purpose |
|-----|------|---------|
| `audio.volume` | number | Stream volume (supports boost beyond 100%) |

#### Controller
| Key | Type | Purpose |
|-----|------|---------|
| `controller.pollingRate` | number | Gamepad polling rate override |
| `controller.settings` | ControllerSettings | Deadzone, stick decay, button swap, sensitivity |
| `deviceVibration.mode` | DeviceVibrationMode | `on`, `auto`, `off` |
| `deviceVibration.intensity` | number | Vibration intensity 0–100 |

#### Stream Stats HUD
| Key | Type | Values |
|-----|------|--------|
| `stats.items` | StreamStat[] | `ping`, `jitter`, `resolution`, `fps`, `bitrate`, `decode-time`, `packets-lost`, `frames-lost`, `downloaded`, `uploaded`, `playtime`, `battery`, `clock` |
| `stats.showWhenPlaying` | boolean | Auto-show when stream starts |
| `stats.quickGlance.enabled` | boolean | Only show when system menu is open |
| `stats.position` | string | `top-left`, `top-center`, `top-right` |
| `stats.colors` | boolean | Conditional color formatting by quality thresholds |
| `stats.opacity.all` | number | Overall HUD opacity |
| `stats.opacity.background` | number | HUD background opacity |

#### Local Co-Op
| Key | Type | Purpose |
|-----|------|---------|
| `localCoOp.enabled` | boolean | Enable local co-op (virtual second controller slot) |

---

## 9. Controller Shortcut Actions

| Action | Purpose |
|--------|---------|
| `BETTER_XCLOUD_SETTINGS_SHOW` | Open settings |
| `STREAM_MENU_SHOW` | Show system menu |
| `CONTROLLER_XBOX_BUTTON_PRESS` | Simulate Xbox button |
| `STREAM_VIDEO_TOGGLE` | Toggle stream video |
| `STREAM_SCREENSHOT_CAPTURE` | Take screenshot |
| `STREAM_STATS_TOGGLE` | Toggle stats HUD |
| `STREAM_SOUND_TOGGLE` | Mute/unmute stream audio |
| `STREAM_MICROPHONE_TOGGLE` | Toggle mic |
| `STREAM_VOLUME_INC` / `DEC` | Volume up/down |
| `DEVICE_SOUND_TOGGLE` | Toggle system audio |
| `DEVICE_VOLUME_INC` / `DEC` | System volume up/down |
| `DEVICE_BRIGHTNESS_INC` / `DEC` | Screen brightness (mobile) |
| `TRUE_ACHIEVEMENTS_OPEN` | Open TrueAchievements for current game |

---

## 10. tvOS Applicability Summary

### Not Applicable to tvOS

| Category | Reason |
|----------|--------|
| Touch controller features | No touchscreen on Apple TV |
| Mouse & keyboard emulation (MKB) | No cursor, no keyboard |
| Device vibration (phone/tablet vibrate) | No equivalent on tvOS |
| Microphone | Already patched out of WebRTC build |
| Screenshot button UI | Not yet in scope |
| Browser DOM patches | Require a live web DOM |
| Splash video skip | Different mechanism on tvOS |
| UI scrollbar / page layout | Browser-only |

### High Priority — Add to Stratix

1. **Loading screen game art** — `catalog.gamepass.com/v3/products` hero image on the game launch screen
2. **Queue wait time display** — parse `/waittime/` → `estimatedTotalWaitTimeInSeconds`, show countdown
3. **Stream stats HUD** — FPS, bitrate, ping, decode time, packets/frames lost, server region (extend `DiagnosticsKit`)
4. **IPv6 ICE preference** — reorder ICE candidates in `ICEProcessor` to prefer IPv6 addresses
5. **Server region picker** — parse region list from `/v2/login/user` response; let user pin preferred region
6. **Target resolution setting** — expose `720p` / `1080p` / `1080p-hq` via `osName` in session start body
7. **Preferred stream locale** — allow locale override in session start body
8. **Vibration intensity setting** — expose 0–100% scale in `ControllerSettings`
9. **Video sharpening (Clarity Boost / CAS)** — Metal compute shader post-processing on the decoded video texture
10. **Software volume boost** — audio gain node override in WebRTC audio pipeline (beyond system volume)
11. **Block telemetry** — omit/ignore calls to arc.msn.com / AppInsights / Sentry at the URLSession level
12. **Controller shortcut combos** — map button combos to in-app actions (stats toggle, disconnect, etc.)
13. **`1080p-hq` tier unlock** — spoof `tizen` OS name to access the highest stream quality tier
14. **Bypass region restriction** — inject `X-Forwarded-For` on `/v2/login/user` for unsupported regions
15. **Game art on title cards** — use `sigls/` UUIDs with `catalog.gamepass.com` to fetch curated lists (Most Popular, Recently Added, Leaving Soon)
