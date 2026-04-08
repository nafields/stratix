# xCloud Protocol Reference

This document describes the xCloud protocol as implemented in Stratix — authentication
flow, session state machine, WebRTC configuration, SDP/ICE handling, binary input format,
and the cloud library API.

Reference implementations studied during development:
- [unknownskl/greenlight](https://github.com/unknownskl/greenlight) — session and signalling lifecycle
- [unknownskl/xbox-xcloud-player](https://github.com/unknownskl/xbox-xcloud-player) — WebRTC/channel/input protocol

> **Disclaimer:** The xCloud API is **undocumented and proprietary**. Endpoint paths,
> request formats, and token requirements may change without notice. This documentation
> reflects the protocol as reverse-engineered from open-source TypeScript clients and is
> provided for educational and interoperability purposes.

---

## Authentication Flow

Microsoft uses a **device code OAuth** flow for TV/console clients. No browser is required
on the Apple TV — the user enters a short code on a phone or PC.

### Step 1: Device Code Request

```
POST https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode
Content-Type: application/x-www-form-urlencoded

client_id=1f907974-e22b-4810-a9de-d9647380c97e
&scope=xboxlive.signin openid profile offline_access
```

Response includes:
- `device_code` — sent to the polling endpoint
- `user_code` — short code displayed to user (e.g. `AB1C2D3E`)
- `verification_uri` — short URL for manual entry (e.g. `https://microsoft.com/link`)
- `verification_uri_complete` — full URL with OTC — **encode this in the QR code** so the user's phone camera opens directly
- `expires_in` — code expires in 900 seconds (15 min)
- `interval` — poll every N seconds (typically 5)

### Step 2: Poll for MSA Token

```
POST https://login.microsoftonline.com/consumers/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:device_code
&device_code=<device_code>
&client_id=1f907974-e22b-4810-a9de-d9647380c97e
```

Poll every `interval` seconds until `authorization_pending` clears. On success, returns:
- `access_token` — MSA access token (~1 hour TTL)
- `refresh_token` — MSA refresh token (~90 day TTL, rotates on use)
- `id_token` — OpenID Connect identity token

### Step 3: Xbox Live Token (XSTS)

Exchange the OAuth access token for Xbox Live tokens in two steps:

**Step 3a: User authenticate**
```
POST https://user.auth.xboxlive.com/user/authenticate
Content-Type: application/json

{
  "Properties": {
    "AuthMethod": "RPS",
    "SiteName": "user.auth.xboxlive.com",
    "RpsTicket": "d=<access_token>"
  },
  "RelyingParty": "http://auth.xboxlive.com",
  "TokenType": "JWT"
}
```

Returns a user token (`t`) and user hash (`uhs`).

**Step 3b: XSTS authorize**
```
POST https://xsts.auth.xboxlive.com/xsts/authorize
Content-Type: application/json

{
  "Properties": {
    "SandboxId": "RETAIL",
    "UserTokens": ["<user_token>"]
  },
  "RelyingParty": "http://xboxlive.com",
  "TokenType": "JWT"
}
```

Returns:
- `Token` — XSTS token (used in `Authorization: XBL3.0 x={uhs};{token}` for Xbox Live REST APIs)
- `DisplayClaims.xui[0].uhs` — user hash

A separate XSTS request with `RelyingParty: "http://gssv.xboxlive.com/"` is needed for the gssv endpoints (xCloud/xHome).

### Step 4: Stream Tokens (gsTokens)

Exchange the XSTS gssv token for stream-specific session tokens:

```
POST https://xhome.gssv-play-prodz.xboxlive.com/v2/login/user    (xHome)
POST https://xgpuweb.gssv-play-prod.xboxlive.com/v2/login/user   (xCloud)
```

Returns:
- `gsToken` — used as the bearer token for all `/v2/sessions` calls
- `offeringId` — included in session start requests
- `webToken` / `webTokenUHS` — used for Xbox Live REST API calls (profile, presence, social)

### Step 5: Long Play Token (LPT) — xCloud only

Required for the `/v2/sessions/{id}/connect` call. Fetched using the refresh token:

```
POST https://login.live.com/oauth20_token.srf
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&refresh_token=<msa_refresh_token>
&client_id=1f907974-e22b-4810-a9de-d9647380c97e
&scope=service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN
```

Returns a short-lived (~5 min) Long Play Token. This is the `msalToken` sent in the `/connect` body.

xHome does **not** use LPT — the session proceeds directly from `WaitingForResources` to `ReadyToConnect` to WebRTC.

---

## Token Persistence

`TokenStore` (`Packages/XCloudAPI/Sources/XCloudAPI/Auth/TokenStore.swift`) persists tokens in the tvOS Keychain.

### Silent Re-authentication Tiers

On app launch, `SessionController` attempts silent re-authentication in order:

| Tier | Condition | Action |
|------|-----------|--------|
| 1 | Cached `gsTokens` present and valid (~1 hour) | Restore immediately, no network call |
| 2 | `gsTokens` expired but MSA refresh token valid (~90 days) | Call `refreshStreamTokens()` silently |
| 3 | Refresh token expired or missing | Navigate to device code sign-in screen |

Token rotation: the MSA refresh token rotates on each use. The new refresh token is immediately persisted to Keychain.

---

## Session State Machine

```
Client                                  Server
  │                                       │
  │── POST /v2/sessions/{type} ──────────>│  state: Provisioning
  │                                       │
  │<── GET /v2/sessions/{id}/state ───────│  polling...
  │       state: WaitingForResources      │
  │       state: ReadyToConnect           │
  │                                       │
  │── POST /v2/sessions/{id}/connect ────>│  send LPT (MSAL auth) [xCloud only]
  │                                       │  state: Provisioning (briefly)
  │                                       │  state: Provisioned
  │                                       │
  │── GET  /v2/sessions/{id}/sdp ────────>│  server SDP offer
  │── POST /v2/sessions/{id}/sdp ────────>│  client SDP answer
  │                                       │
  │── POST /v2/sessions/{id}/ice ────────>│  exchange ICE candidates
  │                                       │
  +── WebRTC connected ──────────────────>+
```

**Critical:** After sending the MSAL auth, poll for `Provisioned` (not `ReadyToConnect`). The server transitions directly to `Provisioned` after receiving MSAL credentials. `waitUntilProvisioned()` is used at this point.

### Session Types

| Type | Path | Description |
|------|------|-------------|
| xCloud | `/v2/sessions/cloud` | Stream from Microsoft's cloud servers |
| xHome | `/v2/sessions/home` | Stream from the user's own Xbox |

xHome skips steps 3 (MSAL auth) and 4 (wait for Provisioned). The session goes directly from `ReadyToConnect` to WebRTC.

---

## WebRTC Configuration

The peer connection is configured to match the JS reference client:

```swift
let config = RTCConfiguration()
config.sdpSemantics = .unifiedPlan
config.bundlePolicy = .maxBundle
config.rtcpMuxPolicy = .require
config.iceServers = []  // Microsoft provides candidates via HTTP signalling
```

### Transceivers

| Track Type | Direction | Reason |
|-----------|-----------|--------|
| Audio | `recvOnly` | Apple TV has no microphone — we only receive |
| Video | `recvOnly` | We receive the Xbox H.264 stream, never send |

### Data Channels (created by client, ordered)

| Label | Protocol | Purpose |
|-------|----------|---------|
| `control` | `controlV1` | Stream control commands, video preference |
| `input` | `1.0` | Gamepad input frames |
| `message` | `messageV1` | Game/overlay messages, handshake |
| `chat` | `chatV1` | Voice chat (not used on tvOS) |

---

## SDP Manipulation

Before sending the local SDP answer, Stratix applies three transformations in `SDPProcessor`:

### 1. H.264 Codec Ordering

Move H.264 High Profile (`4d`) to the top of the codec list, then Constrained High (`42e`), then Baseline (`420`). Xbox streams H.264; VP9/VP8/AV1 are deprioritized.

```
// Before (WebRTC default order):
m=video ... 96 97 98 99 100 101 ...
a=rtpmap:96 VP8/90000
a=rtpmap:97 H264/90000

// After (H.264 prioritized):
m=video ... 97 100 99 96 ...
a=rtpmap:97 H264/90000    ← High Profile (4d...)
...
```

### 2. Bitrate Injection

Add `b=AS:...` and `b=TIAS:...` lines to increase the negotiated bitrate cap. Default WebRTC SDP is conservative (~30 Mbps cap); xCloud needs higher for 1080p quality.

### 3. Device Spoofing Headers

HTTP headers on SDP and session requests include Windows/Chrome device info:

| Header | Value | Purpose |
|--------|-------|---------|
| `User-Agent` | Windows Chrome UA | Required for Microsoft servers to serve 1080p streams |
| `x-ms-device-info` | Windows device info JSON | Resolution tier selection |

Without these headers, Microsoft's servers may serve 720p streams regardless of the resolution preference sent in the video preference message. See [CONFIGURATION.md](CONFIGURATION.md) for the `guide.client_profile_os_name` setting that controls this.

---

## ICE Candidates

Xbox Cloud Gaming uses **Teredo IPv6** addresses for NAT traversal. Microsoft relays ICE candidates via HTTP (not WebRTC's built-in trickle ICE).

### `a=` Prefix Quirk

Xbox ICE candidates arrive with an `a=` prefix in the JSON payload:
```json
{ "candidate": "a=candidate:1234 1 udp ..." }
```

The leading `a=` must be stripped before passing to `RTCIceCandidate.init(sdp:)`:

```swift
let raw = candidate.hasPrefix("a=") ? String(candidate.dropFirst(2)) : candidate
let iceCandidate = RTCIceCandidate(sdp: raw, sdpMLineIndex: 0, sdpMid: nil)
```

### Teredo Expansion

`ICEProcessor` may expand a single Teredo IPv6 candidate into multiple forms. This improves connectivity in NAT environments where direct Teredo traversal is blocked.

---

## Binary Input Protocol

Reference: `xbox-xcloud-player/src/channel/input/packet.ts`

Gamepad frames are sent over the `input` data channel. Each packet is encoded in **little-endian** binary and sent at the current live transport cadence of 125 Hz (every 8 ms).

### Packet Layout

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 4 | Report type bitmask | See `ReportType` OptionSet |
| 4 | 2 | Sequence number | Wrapping increment |
| 6 | 8 | Uptime timestamp | Milliseconds |
| 14 | 1 | Gamepad frame count | Number of gamepad frames following |
| 15 | 23 | Gamepad frame | See gamepad frame layout |
| (38) | 1 | Metadata frame count | Number of metadata frames (optional) |
| (39) | 28 | Metadata frame | Timing metadata (optional) |

### Gamepad Frame Layout (23 bytes)

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | Gamepad index | `0` for first controller |
| 1 | 2 | Button bitmask | `GamepadButtons` OptionSet (see below) |
| 3 | 2 | Left trigger | `UInt16`, 0–65535 |
| 5 | 2 | Right trigger | `UInt16`, 0–65535 |
| 7 | 2 | Left thumbstick X | `Int16`, -32768 to 32767 |
| 9 | 2 | Left thumbstick Y | `Int16`, inverted (up = negative) |
| 11 | 2 | Right thumbstick X | `Int16` |
| 13 | 2 | Right thumbstick Y | `Int16`, inverted |
| 15 | 8 | Padding / reserved | Zero-filled |

### Button Bitmask

| Bit | Button | `GamepadButtons` case |
|-----|--------|-----------------------|
| 0 | Nexus (Xbox button) | `.nexus` |
| 1 | Menu (Start) | `.menu` |
| 2 | View (Back/Select) | `.view` |
| 3 | A | `.a` |
| 4 | B | `.b` |
| 5 | X | `.x` |
| 6 | Y | `.y` |
| 7 | D-pad Up | `.dpadUp` |
| 8 | D-pad Down | `.dpadDown` |
| 9 | D-pad Left | `.dpadLeft` |
| 10 | D-pad Right | `.dpadRight` |
| 11 | Left Bumper | `.leftShoulder` |
| 12 | Right Bumper | `.rightShoulder` |
| 13 | Left Thumbstick click | `.leftThumb` |
| 14 | Right Thumbstick click | `.rightThumb` |

### ReportType OptionSet

| Value | Name | Included when |
|-------|------|---------------|
| `0x01` | `.metadata` | Timing metadata frame present |
| `0x02` | `.gamepad` | Gamepad frame present |
| `0x04` | `.pointer` | Pointer/mouse frame present |
| `0x08` | `.keyboard` | Keyboard frame present |
| `0x10` | `.clientMetadata` | First packet (client metadata frame) |

See `Packages/InputBridge/Sources/InputBridge/InputPacket.swift` for the complete encoding implementation.

---

## Control Channel

Reference: `xbox-xcloud-player/src/channel/control.ts`

JSON messages sent over the `controlV1` data channel to manage stream lifecycle:

### Client → Server

```json
// Initial handshake
{"type": "StreamerRequest", "command": "hello"}

// Video preference (sent after handshake)
{
  "type": "VideoPreference",
  "width": 1920,
  "height": 1080,
  "fps": 60,
  "videoCodec": "H264",
  "colorSpaceFlags": 0
}

// Input capability declaration
{
  "type": "InputPreference",
  "maxTouchPoints": 1
}

// Register controller
{
  "type": "gamepadChanged",
  "gamepadIndex": 0,
  "wasAdded": true
}

// Keyframe request (periodic, every 2s in low-latency mode)
{
  "type": "VideoControl",
  "action": "keyframe"
}
```

### Server → Client

```json
// Keepalive ping
{"type": "Heartbeat"}
```

---

## Cloud Library API

Cloud library data is assembled from two sources in `XCloudAPI`:

### 1. xCloud Titles List

```
GET /v2/titles?mr=25
Authorization: XBL3.0 x={uhs};{xCloudGsToken}
Host: eus.core.gssv-play-prod.xboxlive.com (or region-specific host)
```

Returns `XCloudTitlesResponse` with a list of `XCloudTitleDTO`. Each title has:
- `titleId` — internal xCloud title ID
- `details.productId` — Microsoft Store product ID (used for catalog hydration)
- `details.name` — display name
- `details.hasEntitlement` — whether the signed-in user can play this title
- `details.supportedInputTypes` — e.g. `["Gamepad"]`

**Entitlement filter:** Only titles where `dto.details?.hasEntitlement == true` are shown. This typically filters ~1841 xCloud titles down to the ~78 the user actually has access to.

### 2. Game Pass Catalog Hydration

```
POST https://catalog.gamepass.com/v3/products?market=US&language=en-US&hydration=RemoteHighSapphire0
Content-Type: application/json

{ "Products": ["<productId1>", "<productId2>", ...] }
```

`GamePassCatalogClient.hydrateProducts()` sends requests in batches of 100.

Returns `CatalogProduct` with:
- Images (tile, poster, hero) from `assets.play.xbox.com`
- Attributes (genre tags, capabilities)
- Publisher name
- Localized descriptions

The `hydration=RemoteHighSapphire0` parameter selects a Microsoft-defined field set optimized for remote play clients.

---

## Known API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `xgpuweb.gssv-play-prod.xboxlive.com` | xCloud production (Game Pass Ultimate) |
| `eus.core.gssv-play-prod.xboxlive.com` | xCloud library / sessions (EUS region default) |
| `xgpuwebf2p.gssv-play-prod.xboxlive.com` | xCloud free-to-play titles |
| `xhome.gssv-play-prodz.xboxlive.com` | xHome (stream from your Xbox) |
| `catalog.gamepass.com/v3/products` | Game Pass catalog — artwork, metadata |
| `profile.xboxlive.com` | Xbox profile settings (gamertag, avatar, gamerscore) |
| `userpresence.xboxlive.com` | Xbox presence (online/offline, active title) |
| `social.xboxlive.com` | Xbox social people (friends list) |
| `achievements.xboxlive.com` | Xbox achievements |
| `login.microsoftonline.com` | Microsoft OAuth endpoints |
| `user.auth.xboxlive.com` | Xbox Live user authentication |
| `xsts.auth.xboxlive.com` | XSTS token exchange |
| `login.live.com` | MSA token operations (LPT) |

---

## See Also

- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md) — how these protocol steps map to `StreamingSession.connect()`
- [CONFIGURATION.md](CONFIGURATION.md) — hardcoded OAuth constants and Keychain keys
- [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md) — binary packet encoding (Swift side)
- [../SECURITY.md](../SECURITY.md) — token handling policy
