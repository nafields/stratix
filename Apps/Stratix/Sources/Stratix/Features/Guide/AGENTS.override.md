# AGENTS.override.md — Features/Guide/

The Guide feature is a small overlay that appears during streaming. It provides contextual help, settings access, and quick actions during a game session.

**Modernization contract reference:** If guide work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Files

| File | Role |
|------|------|
| `StreamGuideOverlayView.swift` | Root overlay view. Conditionally shown during streaming. |
| `GuideOverlayComposition.swift` | Composes the overlay panels and layout. |
| `GuideOverlaySettingsAccessors.swift` | Reads settings state for display in the guide. |
| `GuideRows.swift` | Individual row components in the guide overlay. |
| `GuideSettingCatalog.swift` | Defines which settings are surfaced in the guide. |

Model types for the guide pane live in `Models/GuidePaneModels.swift` and `Sections/GuidePaneSections.swift` (app-level, not feature-level, because they are shared with the shell pane builder).

---

## Rules

1. Guide overlay state is thin. Do not introduce a guide-specific view model unless state genuinely needs to be tracked across multiple views.
2. Settings accessed through the guide are read from `settingsStore` (injected via environment). Do not duplicate settings state here.
3. `GuideSettingCatalog` defines the surface — adding new guide-accessible settings means adding a definition here and wiring the accessor in `GuideOverlaySettingsAccessors`.
4. Unit test: `StratixTests/StreamGuideOverlayStateTests.swift`.
