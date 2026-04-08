# AGENTS.override.md — Features/CloudLibrary/

CloudLibrary is the largest feature in the app. It is a vertical slice: it owns its own UI, state, presentation logic, routing, data coordination, and tests. Read this file completely before touching any file in this directory.

**Modernization contract reference:** For all modernization work in this feature, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with `Docs/Stratix_Modernization_Plan.md`, `Docs/Stratix_Monolith_Breakdown.md`, and `Docs/Stratix_File_Matrix.md`.

---

## Directory map

```
Features/CloudLibrary/
├── CloudLibraryShellInteractionCoordinator.swift  ← navigation mutation orchestrator
├── Consoles/
│   └── CloudLibraryConsolesView.swift
├── Detail/
│   ├── CloudLibraryTitleDetailFullscreenMedia.swift
│   ├── CloudLibraryTitleDetailGallery.swift
│   ├── CloudLibraryTitleDetailHeroHeader.swift
│   ├── CloudLibraryTitleDetailMediaReadiness.swift
│   ├── CloudLibraryTitleDetailPanels.swift
│   ├── CloudLibraryTitleDetailScreen.swift
│   ├── CloudLibraryDetailHydrationView.swift
│   └── State/
│       └── DetailStateHotCache.swift
├── Home/
│   ├── CloudLibraryHomeFocusCoordinator.swift
│   ├── CloudLibraryHomeHeroComponents.swift
│   ├── CloudLibraryHomeHeroSection.swift
│   ├── CloudLibraryHomeRailComponents.swift
│   ├── CloudLibraryHomeRailSection.swift
│   ├── CloudLibraryHomeScreen.swift
│   └── HomeRouteRootContainer.swift
├── Library/
│   ├── CloudLibraryLibraryScreenControls.swift
│   ├── CloudLibraryLibraryScreenFocus.swift
│   ├── CloudLibraryLibraryScreenHeader.swift
│   └── CloudLibraryLibraryScreen.swift
├── Presentation/
│   ├── CloudLibraryBrowseRoutePresentation.swift
│   ├── CloudLibraryBrowseRoute.swift
│   ├── CloudLibraryBrowseRouteActions.swift
│   ├── CloudLibraryBrowseRouteHost.swift
│   ├── CloudLibraryContentRouteHost.swift
│   ├── CloudLibraryDetailRouteActions.swift
│   ├── CloudLibraryHeroBackgroundContext.swift
│   ├── CloudLibraryShellPresentation.swift
│   ├── CloudLibraryUtilityRoutePresentation.swift
│   ├── CloudLibraryUtilityRouteActions.swift
├── Profile/
│   └── CloudLibraryProfileView.swift
├── Root/
│   ├── CloudLibraryActionCoordinator.swift
│   ├── CloudLibraryBackActionPolicy.swift
│   ├── CloudLibraryDetailPrewarmCoordinator.swift
│   ├── CloudLibraryDiagnosticsOverlay.swift
│   ├── CloudLibraryLayoutPolicy.swift
│   ├── CloudLibraryViewCacheMaintenance.swift
│   ├── CloudLibraryView.swift
│   ├── CloudLibraryViewModelDetailCache.swift
│   ├── CloudLibraryViewModelHomeProjection.swift
│   ├── CloudLibraryViewModel.swift            ← includes item lookup + prepared index helpers
│   ├── CloudLibraryViewModelLibraryProjection.swift
│   ├── CloudLibraryViewModelSceneMutation.swift
│   ├── CloudLibraryViewModelSearchProjection.swift
│   └── CloudLibraryViewModelDetailCache.swift
├── Search/
│   └── CloudLibrarySearchScreen.swift
├── Settings/
│   ├── CloudLibrarySettingsBindings.swift
│   ├── CloudLibrarySettingsComponents.swift
│   ├── CloudLibrarySettingsControllerPane.swift
│   ├── CloudLibrarySettingsDiagnosticsPane.swift
│   ├── CloudLibrarySettingsInterfacePane.swift
│   ├── CloudLibrarySettingsOverviewPane.swift
│   ├── CloudLibrarySettingsSidebar.swift
│   ├── CloudLibrarySettingsStreamPane.swift
│   ├── CloudLibrarySettingsVideoAudioPane.swift
│   └── CloudLibrarySettingsView.swift
├── Shell/
│   ├── CloudLibraryShellHost.swift             ← primary layout + action owner
│   └── CloudLibraryShellView.swift
└── State/
    ├── CloudLibraryFocusState.swift
    ├── CloudLibraryHeroBackgroundState.swift
    ├── CloudLibraryLoadState.swift
    ├── CloudLibraryLoadStateBuilder.swift
    ├── CloudLibraryPresentationStore.swift
    ├── CloudLibraryRouteState.swift
    ├── CloudLibrarySceneInputs.swift
    ├── CloudLibrarySceneModelMutationTracking.swift
    ├── CloudLibrarySceneModel.swift
    ├── CloudLibrarySceneRouteState.swift
    ├── CloudLibrarySceneStatusState.swift
    └── CloudLibraryStateSnapshot.swift
```

---

## State ownership model

All state objects are `@MainActor` and `@Observable`. They are created in `CloudLibraryView` and passed down to `CloudLibraryShellHost`.

| Type | What it owns |
|------|-------------|
| `CloudLibraryViewModel` | All data projections (home, library, search, detail cache, prepared index) |
| `CloudLibrarySceneModel` | Scene-level derived state: route state, hero background, load status |
| `CloudLibraryPresentationStore` | Presentation projection cache for shell and browse screens |
| `CloudLibraryRouteState` | Current browse route, utility route, detail path stack |
| `CloudLibraryFocusState` | Focus request tokens, settled tile IDs, side rail expansion |
| `CloudLibraryLoadState` | Loading/error/empty/success envelope |

---

## Action routing

**Current state:**
`CloudLibraryShellHost` owns the three routed action bags directly (`browseActions`, `detailActions`, `utilityActions`). The former `CloudLibraryActionFactory` passthrough seam is already dissolved.

`CloudLibraryBrowseRouteActions`, `CloudLibraryDetailRouteActions`, and `CloudLibraryUtilityRouteActions` remain the correct boundary. All action closures in these structs should stay explicitly `@MainActor` when invoked from `@MainActor` view code.

---

## Shell hierarchy

`CloudLibraryShellHost` is the single owner of:
- Layout policy queries (`CloudLibraryLayoutPolicy`)
- All action routing (after factory dissolution)
- Shell bootstrap
- Back action handling
- Settings shortcut handling
- Side rail action dispatch

`CloudLibraryShellView` is a pure layout view. It owns the side rail + content slot geometry, nothing else.

`CloudLibraryShellInteractionCoordinator` orchestrates navigation mutations: opening detail, selecting primary route, handling back, bootstrapping shell state.

Do not add navigation mutation logic to `CloudLibraryShellHost` directly. Route mutations go through `CloudLibraryShellInteractionCoordinator`.

---

## Focus model

Focus is owned by `CloudLibraryFocusState`. It exposes request tokens (opaque incrementing integers) that views observe to know when to claim focus. The token pattern is the current mechanism.

Future direction (Execution Contract): where SwiftUI's `prefersDefaultFocus` and `defaultFocus` can replace a focus token, prefer the framework mechanism. Do not add new focus tokens for new screens — use `prefersDefaultFocus` at the screen root.

---

## Tests

All CloudLibrary unit tests live in `StratixTests/`. Named by the type under test:

- `CloudLibraryActionCoordinatorTests.swift`
- `CloudLibraryRoutePresentationBuilderTests.swift`
- `CloudLibraryBackActionPolicyTests.swift`
- `CloudLibraryRoutePresentationBuilderTests.swift`
- `CloudLibraryDataSourceTests.swift`
- `CloudLibraryDetailPrewarmTests.swift`
- `CloudLibraryFocusStateTests.swift`
- `CloudLibraryHomeFocusCoordinatorTests.swift`
- `CloudLibraryLayoutPolicyTests.swift`
- `CloudLibraryLoadStateTests.swift`
- `CloudLibraryRouteStateTests.swift`
- `CloudLibrarySceneStateTests.swift`
- `CloudLibrarySettingsPaneTests.swift`
- `CloudLibraryShellHostTests.swift`
- `CloudLibraryShellInteractionCoordinatorTests.swift`
- `CloudLibraryShellVisibilityTests.swift`
- `CloudLibraryStateSnapshotTests.swift`
- `CloudLibraryViewModelSceneMutationTests.swift`
- `GamePassTitleDetailScreenStateTests.swift`

---

## Current CloudLibraryViewModel cluster status

The root now owns `preparedIndexIfNeeded(...)`, `heroCandidateURL(for:)`, and both `rebuildItemLookup(...)` helpers directly. The five remaining companion files (`CloudLibraryViewModelDetailCache.swift`, `CloudLibraryViewModelHomeProjection.swift`, `CloudLibraryViewModelLibraryProjection.swift`, `CloudLibraryViewModelSceneMutation.swift`, `CloudLibraryViewModelSearchProjection.swift`) are correctly split and must not be merged.

---

## What to preserve

The CloudLibrary feature is the strongest part of the app's architecture:
- The vertical slice structure is correct and must not be flattened
- The separation of State/ from Presentation/ from Root/ is correct
- The Data/ layer being side-effect-free is correct
- The @MainActor state object pattern is correct
- The `CloudLibraryShellInteractionCoordinator` orchestrating mutations is correct
- `DetailStateHotCache` being co-located with Detail/ is correct
- The five projection companion files (`CloudLibraryViewModelDetailCache.swift`, `CloudLibraryViewModelHomeProjection.swift`, `CloudLibraryViewModelLibraryProjection.swift`, `CloudLibraryViewModelSceneMutation.swift`, `CloudLibraryViewModelSearchProjection.swift`) are correctly split — do not merge them

Do not restructure these without a documented reason.
