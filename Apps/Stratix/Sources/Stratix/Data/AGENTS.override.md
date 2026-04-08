# AGENTS.override.md — Data/

This directory contains the data shaping layer for CloudLibrary. It is explicitly side-effect-free.

**Modernization contract reference:** If changes here are part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing ownership or seams.

---

## What lives here

```
Data/
└── CloudLibrary/
    ├── CloudLibraryDataSource.swift           ← root type declaration
    └── CloudLibraryDataSource/
        ├── CloudLibraryDataSourceDetailState.swift
        ├── CloudLibraryDataSourceHomeProjection.swift
        ├── CloudLibraryDataSourceLibraryIndex.swift
        └── CloudLibraryDataSourceSearchResults.swift
```

`CloudLibraryDataSource` and its extensions transform raw library models from `StratixModels` into view-ready state structs consumed by `CloudLibraryViewModel`. This transformation is:
- Pure (no side effects)
- Synchronous
- Testable without mocks or async harnesses

---

## Rules

1. **No async functions here.** If a transformation requires async work, it does not belong in this layer.
2. **No `@MainActor` isolation here.** Data shaping is not UI work. These functions can be called from any isolation context.
3. **No network calls here.** Input is already-fetched model data.
4. **No state mutation here.** These are functions that take values and return values.
5. **No imports of UIKit or SwiftUI here.** Only StratixModels and Swift standard library.

---

## Tests

`StratixTests/CloudLibraryDataSourceTests.swift` — covers all shaping paths. These tests are pure and fast. Run them in isolation frequently.

If you add a new companion file for `CloudLibraryDataSource`, add a corresponding test section in `CloudLibraryDataSourceTests.swift`.
