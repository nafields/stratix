# Xbox Social, Profile, And Presence

This document explains the Xbox social/profile/presence APIs used in the live `Stratix` repo — endpoints, auth model, response shapes, data flow, and polling strategy.

> **Disclaimer:** The Xbox Live REST API is undocumented and proprietary. Endpoint paths, request formats, and token requirements may change without notice. This documentation reflects the protocol as used in Stratix.

---

## Ownership

| Layer | Owner | Responsibility |
|-------|-------|---------------|
| Raw API clients | `XCloudAPI` package | HTTP requests, response decoding, error handling |
| Orchestration | `StratixCore` `ProfileController` | Caching, refresh scheduling, app-facing state publication |
| UI presentation | App target | Profile overlay, friends surface, shell presence indicators |

Primary files:
- `Packages/XCloudAPI/Sources/XCloudAPI/XboxWebProfileClient.swift`
- `Packages/XCloudAPI/Sources/XCloudAPI/XboxWebPresenceClient.swift`
- `Packages/XCloudAPI/Sources/XCloudAPI/XboxSocialPeopleClient.swift`
- `Packages/StratixCore/Sources/StratixCore/Profile/ProfileController.swift`

---

## Authentication

All three social APIs use **Xbox Live 3.0 token** format:

```
Authorization: XBL3.0 x={uhs};{token}
```

`XboxWebCredentials` is constructed from the `webToken` and `webTokenUHS` fields on `StreamTokens`, which are populated during the main auth flow. The app does not maintain a separate social-only login path — the same token bundle used for xCloud streaming authenticates all social endpoints.

---

## Xbox Profile API

**Client:** `XboxWebProfileClient` (actor)
**Base URL:** `https://profile.xboxlive.com`

### Get Current User Profile

```
GET /users/me/profile/settings?settings=GameDisplayName,GameDisplayPicRaw,Gamerscore,Gamertag
x-xbl-contract-version: 2
Authorization: XBL3.0 x={uhs};{token}
```

Returns `XboxCurrentUserProfile`:

| Field | Type | Description |
|-------|------|-------------|
| `xuid` | `String` | Xbox user ID |
| `gamertag` | `String` | Account gamertag |
| `gameDisplayName` | `String?` | Display name (may differ from gamertag) |
| `gameDisplayPicRaw` | `String?` | Avatar image URL (CDN, direct load) |
| `gamerscore` | `String?` | Lifetime gamerscore (string, may include commas) |

### Get Profiles by XUID (batch)

```
POST /users/batch/profile/settings
x-xbl-contract-version: 3
Content-Type: application/json

{
  "settings": ["GameDisplayName", "GameDisplayPicRaw", "Gamerscore", "Gamertag"],
  "userIds": ["xuid1", "xuid2", ...]
}
```

Used to hydrate friend profile images and display names after the social people list loads. Called after `loadSocialPeople()` to merge display pictures into the people list for online friends.

---

## Xbox Presence API

**Client:** `XboxWebPresenceClient` (actor)
**Base URL:** `https://userpresence.xboxlive.com`

### Get Current User Presence

```
GET /users/me?level=all
x-xbl-contract-version: 3
Authorization: XBL3.0 x={uhs};{token}
```

Returns `XboxCurrentUserPresence`:

| Field | Type | Description |
|-------|------|-------------|
| `xuid` | `String` | Xbox user ID |
| `state` | `String` | `"Online"` or `"Offline"` |
| `devices` | `[XboxPresenceDevice]` | Active devices with titles |
| `lastSeen` | `XboxPresenceLastSeen?` | Last seen title, device, and timestamp |
| `fetchedAt` | `Date` | Local timestamp when response was received |

Computed properties:
- `isOnline: Bool` — case-insensitive check on `state`
- `activeTitleName: String?` — name of the first active title across all devices

**Response format quirk:** The presence API may return the user object in one of three shapes:
1. Top-level JSON object `{ state:, xuid:, devices: }`
2. Wrapped under a `"presence"` key
3. As the first element of a `"users"` or `"people"` array

`XboxWebPresenceClient.parseCurrentUserPresence` handles all three shapes.

### Set Presence

```
POST /users/me
x-xbl-contract-version: 3
Content-Type: application/json

{ "state": "Online" }   // or "Offline"
```

Supported by `ProfileController` when the current environment allows Xbox presence writes. The current app UI mainly exposes a local presence-display override rather than a guaranteed live write toggle, and write failures remain non-fatal state.

---

## Xbox Social People API

**Client:** `XboxSocialPeopleClient` (actor)
**Base URL:** `https://social.xboxlive.com`

### Get Friends List

```
GET /users/me/people?view=all&startIndex=0&maxItems=24
x-xbl-contract-version: 5
Authorization: XBL3.0 x={uhs};{token}
```

Returns `XboxSocialPeoplePage`:

| Field | Type | Description |
|-------|------|-------------|
| `totalCount` | `Int` | Total friends count (may exceed items returned) |
| `people` | `[XboxSocialPerson]` | Friends list |

Each `XboxSocialPerson`:

| Field | Type | Description |
|-------|------|-------------|
| `xuid` | `String` | Xbox user ID |
| `gamertag` | `String?` | Account gamertag |
| `displayName` | `String?` | Display name |
| `realName` | `String?` | Real name (if visible) |
| `displayPicRaw` | `String?` | Avatar image URL |
| `gamerScore` | `String?` | Lifetime gamerscore |
| `presenceState` | `String?` | `"Online"` or `"Offline"` |
| `presenceText` | `String?` | Activity text (e.g., game title) |
| `isFavorite` | `Bool` | Favorited by user |
| `isFollowingCaller` | `Bool` | Follows the current user |
| `isFollowedByCaller` | `Bool` | Followed by the current user |

Computed:
- `preferredName: String` — `displayName ?? gamertag ?? xuid`
- `isOnline: Bool` — case-insensitive check on `presenceState`

**Sort order:** Online status first, then favorites, then alphabetically by `preferredName`.

**Post-load hydration:** After the people list loads, `ProfileController` optionally fetches profile images for online friends via `XboxWebProfileClient.getProfiles(userIds:)` (batch POST). Results are merged into the displayed people list.

---

## Data Flow

```
ProfileController.loadProfile()
    │
    ├── XboxWebProfileClient.getCurrentUserProfile()
    │     GET profile.xboxlive.com/users/me/profile/settings
    │     → XboxCurrentUserProfile (gamertag, avatar, gamerscore)
    │
    ├── XboxWebPresenceClient.getCurrentUserPresence()
    │     GET userpresence.xboxlive.com/users/me?level=all
    │     → XboxCurrentUserPresence (status, active title, device)
    │
    └── ProfileController.profileSnapshot updated
            → @Observable → profile overlay re-renders
```

```
User opens profile overlay → "Friends" tab
    │
    └── ProfileController.loadSocialPeople()
            │
            └── XboxSocialPeopleClient.getPeople(startIndex:maxItems:)
                    GET social.xboxlive.com/users/me/people
                    → XboxSocialPeoplePage (friends list with presence)
                    │
                    └── (optional) XboxWebProfileClient.getProfiles(userIds:)
                            POST profile.xboxlive.com/users/batch/profile/settings
                            → Hydrated avatar URLs for online friends
                    → ProfileController.socialPeople updated
```

---

## ProfileController State

`ProfileController` is `@MainActor @Observable` (defined in `StratixCore`). It publishes:

| Property | Type | Description |
|----------|------|-------------|
| `currentUserProfile` | `XboxCurrentUserProfile?` | Loaded profile data |
| `currentUserPresence` | `XboxCurrentUserPresence?` | Current presence state |
| `isLoadingCurrentUserPresence` | `Bool` | In-flight presence request |
| `socialPeople` | `[XboxSocialPerson]` | Loaded friends list |
| `socialPeopleTotalCount` | `Int` | Total friends count |
| `isLoadingSocialPeople` | `Bool` | In-flight social request |
| `lastSocialPeopleError` | `String?` | Last error from social fetch |
| `lastCurrentUserPresenceError` | `String?` | Last error from presence fetch |

On sign-out, all of these are reset to their defaults.

---

## Presence Refresh Model

The live repo does **not** run a shell-active presence polling timer today.

Current behavior:

- presence is loaded on demand through the profile load path
- the controller keeps the last successful presence snapshot in observable state
- write capability is cached separately via `stratix.presence.write_supported`
- there is no live `guide.presence_poll_interval_seconds` setting in `SettingsStore`

---

## Current Capabilities

| Capability | Status |
|-----------|--------|
| Current user profile load | Implemented |
| Current user presence load | Implemented |
| Presence write (set online/offline) | Partial |
| Friends/people list | Implemented |
| Profile + social cache restore before refresh | Implemented |
| Presence polling while shell active | Not implemented |
| Friends search | Not started |
| Party / invite UX | Not started |
| Multi-account social context | Not started |

---

## API Endpoint Summary

| API | Method | URL | Auth Header |
|-----|--------|-----|-------------|
| Current user profile | GET | `https://profile.xboxlive.com/users/me/profile/settings?settings=GameDisplayName,GameDisplayPicRaw,Gamerscore,Gamertag` | `XBL3.0 x={uhs};{token}` |
| Batch profiles | POST | `https://profile.xboxlive.com/users/batch/profile/settings` | `XBL3.0 x={uhs};{token}` |
| Current user presence | GET | `https://userpresence.xboxlive.com/users/me?level=all` | `XBL3.0 x={uhs};{token}` |
| Set presence | POST | `https://userpresence.xboxlive.com/users/me` | `XBL3.0 x={uhs};{token}` |
| Friends list | GET | `https://social.xboxlive.com/users/me/people?view=all&startIndex=0&maxItems=24` | `XBL3.0 x={uhs};{token}` |

All endpoints require `x-xbl-contract-version` header — see individual section for the correct version value.

---

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md)
- [RUNTIME_FLOW.md](RUNTIME_FLOW.md)
- [XBOX_ACHIEVEMENTS_AND_MEDIA.md](XBOX_ACHIEVEMENTS_AND_MEDIA.md)
- [XCLOUD_PROTOCOL.md](XCLOUD_PROTOCOL.md)
