# AGENTS.override.md — App/

This directory is the app entry point. It owns the `@main` struct, the app delegate, the root view, and launch mode flags.

**Modernization contract reference:** If work in this directory is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Files

| File | Role |
|------|------|
| `StratixApp.swift` | `@main` struct. Creates `AppCoordinator`, injects all controllers as typed environment objects. Do not add logic here beyond what is needed to wire the environment. |
| `StratixAppDelegate.swift` | `UIApplicationDelegate`. Receives the `AppCoordinator` reference after launch. Handles system-level lifecycle events. |
| `RootView.swift` | Top-level SwiftUI view. Reads auth state from `AppCoordinator` and routes to auth or shell. |
| `StratixLaunchMode.swift` | Static flags for UI test launch overrides (`isShellUITestModeEnabled`, `isGamePassHomeUITestModeEnabled`, `uiTestBrowseRouteOverrideRawValue`). These are read at launch and at shell bootstrap. |

---

## Rules for this directory

1. `StratixApp` must not grow. If a new controller needs to be injected, add it to `AppCoordinator` in `StratixCore` and inject it here with `.environment(coordinator.newController)`. The pattern is established and must not diverge.
2. `StratixLaunchMode` is the only place where UI test launch flags are read. Do not scatter launch mode checks through the source tree.
3. `RootView` is the only place where the auth state branch lives. Do not add feature-level routing here.
4. This directory has no tests of its own. `StratixAppExitHandlingTests.swift` lives in `StratixTests/` and tests delegate behavior.

---

## Concurrency

`AppCoordinator` is `@MainActor`. All calls to `coordinator.onAppear()` in `StratixApp` are already dispatched with `.task`. Do not call coordinator methods outside of `.task` or `@MainActor` contexts.
