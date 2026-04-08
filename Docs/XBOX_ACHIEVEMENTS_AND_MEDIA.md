# Xbox Achievements And Media

This document covers the achievements API, title media normalization pipeline, caching strategy, and controller wiring in the live `Stratix` repo.

> **Disclaimer:** The Xbox Live REST API is undocumented and proprietary. Endpoint paths and token requirements may change without notice.

---

## Ownership

| Layer | Owner | Responsibility |
|-------|-------|---------------|
| Raw API clients | `XCloudAPI` package | HTTP requests, response decoding |
| Orchestration | `StratixCore` `AchievementsController` | Load, cache, restore, refresh loop |
| Stream overlay wiring | `StratixCore` `StreamController` | Active-stream achievement refresh at 120s cadence |
| UI consumers | App target | Title detail gallery, stream overlay, profile surfaces |

Primary files:
- `Packages/XCloudAPI/Sources/XCloudAPI/XboxAchievementsClient.swift`
- `Packages/XCloudAPI/Sources/XCloudAPI/XboxComProductDetailsClient.swift`
- `Packages/StratixCore/Sources/StratixCore/AchievementsController.swift`

---

## Authentication

All endpoints use Xbox Live 3.0 token credentials:

```
Authorization: XBL3.0 x={uhs};{token}
```

The same `XboxWebCredentials` bundle used for social APIs. No separate auth path for achievements.

---

## Achievements API

**Base host:** `https://achievements.xboxlive.com`

### Title History Summary

```
GET /users/xuid({xuid})/history/titles?maxItems=200
x-xbl-contract-version: 2
Authorization: XBL3.0 x={uhs};{token}
```

Returns per-title totals and unlocked counts — achievements earned and total, gamerscore earned and total. Used to populate achievement summary badges on title cards and the profile surface.

Parsed into `TitleAchievementSummary`:
- `titleId` — numeric title identifier (used for the per-title detail fetch below)
- `name` — title display name
- `currentAchievements` — earned count
- `totalAchievements` — total achievable count
- `currentGamerscore` — earned gamerscore
- `totalGamerscore` — total gamerscore available

### Per-Title Achievements

```
GET /users/xuid({xuid})/achievements?titleId={titleId}&maxItems={n}
x-xbl-contract-version: 2
Authorization: XBL3.0 x={uhs};{token}
```

Fetches recent/progress achievements for a specific title. `titleId` here is the **numeric** title history ID from the summary fetch above, not the alphanumeric `TitleID` used in xCloud. The controller resolves the mapping via title history before calling this endpoint.

The parser is resilient to shape variance — handles `titles/items/results/value` envelopes and mixed field casing.

Parsed into `AchievementProgressItem`:
- `id`, `name`, `description` — achievement identity
- `isSecret` — hidden until unlocked
- `progressState` — `"Achieved"`, `"NotStarted"`, `"InProgress"`
- `progression` — current/target value for progressive achievements
- `mediaAssets` — achievement icon URL(s)

---

## Achievement Controller Flow

`AchievementsController` (`@MainActor @Observable`) drives the full lifecycle:

```
AchievementsController.loadTitleAchievements(titleId:forceRefresh:)
    │
    ├── 1. Resolve XboxWebCredentials (XUID + token)
    │
    ├── 2. Check disk cache (Application Support/stratix/stratix.titleAchievements.json)
    │     If cache is fresh and forceRefresh == false → publish from cache immediately
    │
    ├── 3. XboxAchievementsClient.getTitleHistorySummary()
    │     GET /users/xuid({xuid})/history/titles
    │     → map TitleID → numeric history titleId
    │
    ├── 4. XboxAchievementsClient.getAchievements(titleId:)
    │     GET /users/xuid({xuid})/achievements?titleId={numericId}
    │     → [AchievementProgressItem]
    │
    ├── 5. Build TitleAchievementSnapshot
    │
    ├── 6. Persist to disk cache
    │
    └── 7. Publish via AchievementsController.titleAchievementSnapshots
```

**Stream overlay refresh:** While a cloud stream is active and the overlay is visible, `StreamController` triggers `loadStreamAchievements(titleId:forceRefresh:)` every 120 seconds to keep the overlay current.

**Published state:**

| Property | Type | Description |
|----------|------|-------------|
| `titleAchievementSnapshots` | `[TitleID: TitleAchievementSnapshot]` | Per-title cached snapshots |
| `lastTitleAchievementsErrorByTitleId` | `[TitleID: String]` | Per-title error state |

**StreamController additions:**
- `currentStreamAchievementSnapshot: TitleAchievementSnapshot?` — current stream's achievements
- `lastStreamAchievementError: String?` — error from last stream overlay refresh

---

## Title Media Normalization

`XboxComProductDetailsClient` normalizes raw product data into canonical `CloudLibraryMediaAsset` entries.

### CloudLibraryMediaAsset

| Field | Type | Values / Description |
|-------|------|---------------------|
| `kind` | `MediaAssetKind` | `image` or `video` |
| `url` | `URL` | Direct asset URL |
| `thumbnailURL` | `URL?` | Thumbnail for video assets |
| `title` | `String?` | Video title or caption |
| `priority` | `Int` | Sort order hint |
| `source` | `MediaAssetSource` | `productDetails`, `catalog`, or `inferred` |

`CloudLibraryProductDetail.mediaAssets` is the **canonical** media contract. `galleryImageURLs` and `trailers` remain populated as compatibility fields but are not the primary source for new code.

### Gallery Selection Policy

When composing the title detail gallery:

1. Use `mediaAssets` from product details as the primary source
2. Deterministic ordering:
   - Videos/trailers first (up to 3)
   - Screenshots/images next (up to 12)
3. Trailer thumbnail fallback order:
   - Explicit trailer thumbnail URL
   - Cached extracted frame
   - Screenshot fallback
   - Gradient placeholder

### Product Details Fetch

```
GET https://emerald.xboxservices.com/xboxcomfd/productdetails/{productId}
Authorization: XBL3.0 x={uhs};{token}
```

`XboxComProductDetailsClient` batch-fetches product details for all titles needing enrichment. Results are normalized into `CloudLibraryItem` records during `LibraryHydrationCatalogShapingWorkflow`.

---

## Caching Strategy

| Cache | Location | TTL / Strategy |
|-------|----------|----------------|
| Achievement snapshots | `Application Support/stratix/stratix.titleAchievements.json` | Restored on launch; refreshed on demand when title-detail or related flows request achievements |
| Product detail cache | `Application Support/stratix/stratix.cloudLibraryDetails.v2.json` plus in-memory `LibraryController.productDetails` state | Restored from the library-details disk snapshot and updated on live refresh |
| Post-load warmup | Profile + social prewarm tasks | `LibraryPostLoadWarmupCoordinator` currently warms current-user profile and social people loads after library load |

Error behavior: cache errors are non-fatal. A stale snapshot renders rather than showing an empty state. Per-title error state is tracked separately so one failure doesn't affect other titles.

---

## API Endpoint Summary

| API | Method | URL | Notes |
|-----|--------|-----|-------|
| Title history summary | GET | `https://achievements.xboxlive.com/users/xuid({xuid})/history/titles?maxItems=200` | Contract version 2 |
| Per-title achievements | GET | `https://achievements.xboxlive.com/users/xuid({xuid})/achievements?titleId={id}&maxItems={n}` | Numeric titleId from history |
| Product details | GET | `https://emerald.xboxservices.com/xboxcomfd/productdetails/{productId}` | Batch, normalized via `XboxComProductDetailsClient` |

---

## Current Limits

| Limitation | Detail |
|-----------|--------|
| xHome achievements | Not treated as equivalent to cloud-stream achievement support — explicit unsupported messaging in the overlay |
| Media coverage | Not every `CloudLibraryMediaAsset` kind has a first-class view in every screen |
| Clips/captures | `gameclipsmetadata.xboxlive.com` user captures are out of scope for the current media contract |
| Real-time unlock events | No push/socket mechanism — achievement state is polled at 120s cadence during active streams |

---

## Related Docs

- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
- [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md)
- [HYDRATION.md](HYDRATION.md)
- [BETTER_XCLOUD.md](BETTER_XCLOUD.md)
- [XCLOUD_PROTOCOL.md](XCLOUD_PROTOCOL.md)
