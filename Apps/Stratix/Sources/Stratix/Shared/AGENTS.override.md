# AGENTS.override.md — Shared/

Shared/ contains reusable UI components and the design system. These are available to all features in the app target.

**Modernization contract reference:** For modernization work in shared components or theme support, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with the modernization plan, monolith breakdown, and file matrix.

---

## Subdirectories

### Shared/Components/

Reusable SwiftUI components. All components here must be feature-agnostic — they must not import any feature module or reference feature-specific state.

| File | Role |
|------|------|
| `GlassCard.swift` | Frosted glass card surface. Also contains `FocusRingModifier`, `GamePassTVButtonStyle`, `FocusAwareView`. |
| `MediaTileView.swift` | Tile view for media content (games, titles). Used in rails and grids. |
| `ChipGroupView.swift` | Horizontal chip/filter group. |
| `FocusSettleDebouncer.swift` | Async helper that waits for focus to settle before proceeding. Used to avoid layout thrash during focus transitions. |
| `RemoteArtworkView.swift` | SwiftUI view that fetches and displays remote artwork via `RemoteImagePipeline`. |
| `SideRailNavigationView.swift` | Side navigation rail. Used by CloudLibraryShellView. |
| `SideRailNavList.swift` | Navigation item list within the side rail. |
| `SideRailActionList.swift` | Action item list within the side rail. |
| `SideRailAccountCluster.swift` | Account/profile cluster at the bottom of the side rail. |
| `SideRailFocusCoordinator.swift` | Focus coordinator for the side rail. |
| `CloudLibraryStatusViews.swift` | CloudLibrary status and loading views shared across browse and detail screens. |
| `StratixBranding.swift` | STRATIX wordmark and brand components. |

**Focus pattern used throughout:**
```swift
FocusAwareView { isFocused in
    // custom focus styling using isFocused
}
.gamePassFocusRing(isFocused: isFocused, cornerRadius: 12)
.gamePassDisableSystemFocusEffect()
```

`GamePassTVButtonStyle()` handles press animation only. Combine with `FocusAwareView` for complete focus behavior.

### Shared/Theme/

**Current state:**

The old `StratixTheme.swift` mixed root has already been split into the current files:

| File | Role |
|------|------|
| `Shared/Theme/StratixDesignTokens.swift` | Design tokens, typography helpers, and shared theme modifiers |
| `Shared/Theme/RemoteImagePipeline.swift` | Shared remote-image actor with cache, decode, and signpost work |
| `Shared/Components/CachedRemoteImage.swift` | SwiftUI cached image view |
| `Shared/Components/AmbientBackground.swift` | Ambient/background presentation components |

`RemoteArtworkView.swift` remains the only shared component that should talk directly to `RemoteImagePipeline`.

Performance signposts in `RemoteImagePipeline` should remain there. They are image-pipeline-specific telemetry and do not need to move to `DiagnosticsKit` unless the telemetry must cross package boundaries.

---

## Design system tokens (Execution Contract target)

The design system uses:
- `GamePassTheme.Colors.focusTint` = lime green (`Color(red: 0.72, green: 0.95, blue: 0.34)`)
- Dark backgrounds throughout
- Rounded system fonts via `StratixTypography`
- `GlassCard` as the base frosted glass surface

**Execution contract:** When `GlassEffect` (`glassEffect` modifier, tvOS 26) is adopted, `GlassCard`'s base surface layer should use it where the system material is appropriate. Tokenized fallback must be preserved for cases where `glassEffect` does not apply (e.g., branded surfaces with lime green tint). Do not rewrite `GlassCard` wholesale — adopt `glassEffect` at the base layer only.

---

## Rules

1. Components in `Shared/` must not import feature modules (`Features/CloudLibrary`, `Features/Streaming`, etc.)
2. `RemoteArtworkView` is the only component allowed to reference `RemoteImagePipeline` directly
3. Do not add network or persistence logic to components — that belongs in pipeline actors or packages
4. `FocusSettleDebouncer` is a concurrency primitive. It uses `Task` + `await`. Do not add UI state to it
