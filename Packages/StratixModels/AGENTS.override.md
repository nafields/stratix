# AGENTS.override.md — Packages/StratixModels/

StratixModels is the leaf-level shared model package. It has no dependencies on other packages in this repo.

**Modernization contract reference:** If model-layer work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Files

| File | Role |
|------|------|
| `CloudLibrary/CloudLibraryModels.swift` | Game title, library item, catalog, category model types |
| `Achievements/AchievementModels.swift` | Achievement, trophy, progress model types |
| `Input/InputModels.swift` | Gamepad input model types |
| `Identifiers/ProductID.swift` | Typed ID for a product (game) |
| `Identifiers/TitleID.swift` | Typed ID for a title |
| `Streaming/StreamingConfig.swift` | Streaming configuration model |
| `Streaming/StreamingRuntime.swift` | Streaming runtime state model |
| `Streaming/StreamingProtocol.swift` | Streaming protocol/channel model |

---

## Rules

1. **No package dependencies.** `StratixModels` must always remain the leaf. It cannot import any other package in this repo.
2. **No UIKit, no SwiftUI, no Foundation networking.** Pure value types only.
3. **All types must be `Sendable`.** These types cross actor boundaries frequently. Use `struct`, `enum`, or `final class` with `Sendable` conformance.
4. **`ProductID` and `TitleID` are typed IDs.** They must remain distinct types — do not collapse them to `String` aliases. They enable the compiler to catch mismatched ID passing.
5. New shared model types go here. Do not add model types to the app target if they are shared with packages.
6. Do not create new files with only comments or re-export stubs. All files must own at least one type.
