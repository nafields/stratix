# AGENTS.override.md — Consoles/

This directory owns the console list feature — the screen where the user sees their registered Xbox consoles and can launch a remote stream to one.

**Modernization contract reference:** For modernization work in this directory, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with the modernization plan, monolith breakdown, and file matrix.

---

## Files

| File | Role |
|------|------|
| `ConsoleListView.swift` | Root view for the console list screen. Reads console data from the `consoleController` environment object. |
| `ConsoleCardView.swift` | Individual console card tile. |
| `ConsoleGridSection.swift` | Grid layout section for console cards. |
| `ConsoleListEmptyState.swift` | Empty state panel shown when no consoles are registered. |
| `ConsoleListFocusCoordinator.swift` | Focus management for the console grid. Tracks focused card ID and handles D-pad routing. |
| Home-stream launch helpers in `ConsoleListView.swift` | Own the direct stream launch and dismiss behavior for this screen. |

---

## Stream launch ownership

Console stream launch is already owned directly in `ConsoleListView.swift`. The old `ConsoleStreamLaunchCoordinator` passthrough seam is gone.

Do not reintroduce a local namespace wrapper around launch and dismiss calls. If this screen needs more logic in the future, put it directly in the view/state owner or move it to a real reusable state object.

---

## Rules

1. Console list does not own stream state. Stream state lives in `StreamingCore` / `streamController`.
2. Focus state is `ConsoleListFocusCoordinator`'s responsibility only. Do not add focus state to other types in this directory.
3. Unit tests live in `StratixTests/ConsoleListFocusCoordinatorTests.swift`, `ConsoleListShellVisibilityTests.swift`, and the current stream-launch tests around `ConsoleListView`.

---

## Concurrency

`ConsoleListFocusCoordinator` must be `@MainActor` — it holds UI-facing focus state. Any async call to `streamController` from `ConsoleListView` must stay on `@MainActor`.
