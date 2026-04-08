# AGENTS.override.md — Packages/XCloudAPI/

XCloudAPI is the network layer for all Xbox Live and xCloud API communication. It owns auth token management, catalog fetching, presence, profiles, achievements, and stream session setup.

**Modernization contract reference:** For modernization work in this package, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with the modernization plan, monolith breakdown, and file matrix.

---

## What lives here

```
XCloudAPI/Sources/XCloudAPI/
├── Auth/
│   ├── MicrosoftAuthService.swift     ← OAuth / device code auth flow
│   └── TokenStore.swift               ← Persists and refreshes auth tokens
├── XCloudAPIClient.swift              ← Main client entry point
├── GamePassCatalogClient.swift        ← Game catalog API
├── GamePassSiglClient.swift           ← SIGL token endpoint
├── XboxAchievementsClient.swift
├── XboxWebPresenceClient.swift
├── XboxWebProfileClient.swift
├── XboxComProductDetailsClient.swift
├── XboxSocialPeopleClient.swift
├── StreamSession.swift                ← Stream session negotiation
├── XboxWebRequestSupport.swift        ← Shared HTTP request helpers
├── BlockingURLProtocol.swift          ← Test support: blocking URL protocol
└── CloudLibraryModels.swift           ← API-layer response models (not shared with StratixModels)
```

---

## Auth flow

`MicrosoftAuthService` implements the device code flow used in `DeviceCodeView`. It produces `DeviceCodeInfo` (polling interval, user code, verification URL) and polls for completion. Tokens are stored in `TokenStore`.

`AppCoordinator` in `StratixCore` drives auth state by calling into this service. `DeviceCodeView` reads the `DeviceCodeInfo` from the coordinator's auth state.

---

## Current file-shape guidance

The old micro-shard cleanup in the `XboxComProductDetailsClient` cluster has already landed. The current split is the baseline:

- `XboxComProductDetailsClient.swift` owns the public API and request orchestration
- `XboxComProductDetailsResponseDecoding.swift` stays as substantive decode logic
- `XboxComProductDetailsParsingSupport.swift` stays as substantive parsing/mapping support

Do not reintroduce tiny `+FetchPipeline` or `+RequestConstruction` extension shards around single public entry points.

---

## Rules

1. No UIKit, no SwiftUI. Network clients are pure Swift.
2. `TokenStore` is an actor — it manages mutable token state accessed from multiple async contexts.
3. `BlockingURLProtocol` is test support only. It is used in `Tests/` to provide deterministic URL session behavior. Do not use it in production code paths.
4. `CloudLibraryModels.swift` in this package contains the raw API response types (Codable). These are distinct from `StratixModels/CloudLibrary/CloudLibraryModels.swift` which contains domain model types. Do not collapse these.
5. All async methods must be `Sendable`-safe. Responses parsed from network must be value types or actors.
6. New API endpoints go in new client files, not in `XCloudAPIClient.swift`. Follow the existing pattern: one client file per API surface.
7. Do not add new micro-shard extension files to established client clusters. If `+FetchPipeline` and `+RequestConstruction` already proved to be micro-shards that must be merged, new single-function extensions should go directly into the closest substantive extension or the root.
