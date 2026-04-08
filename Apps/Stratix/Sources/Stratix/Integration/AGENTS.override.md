# AGENTS.override.md — Integration/

The Integration directory is the boundary layer between the app and its external surfaces: the WebRTC binary framework, preview scaffolding, and the UI test harness.

**Modernization contract reference:** If integration-layer work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Subdirectories

### Integration/WebRTC/

The concrete implementations of everything that requires the `WebRTC.xcframework` binary. See `Integration/WebRTC/AGENTS.override.md`.

### Integration/Previews/

Preview scaffolding for CloudLibrary. Contains:

- `CloudLibraryPreviewData.swift` — the primary preview data file. Currently a single large mixed file containing fixtures, preview scenarios, and snapshot logic.

**Planned scaffold directories (currently empty, marked with `.gitkeep`):**
- `PreviewData/` — static fixture data (JSON, stubs)
- `PreviewFixtures/` — deterministic typed fixture builders
- `PreviewScenarios/` — composable preview scenario descriptions
- `PreviewStores/` — in-memory store stubs for previews

**Execution contract for Previews:**
`CloudLibraryPreviewData.swift` must be split across these directories as their content grows. Today, the `.gitkeep` files mark the intended structure. When preview data expands, populate the appropriate directory rather than adding more to `CloudLibraryPreviewData.swift`.

Rules for preview data:
1. Preview fixtures must be deterministic. No network calls in preview mode.
2. Preview stores must be in-memory stubs, not the live controllers.
3. Preview scenarios must be composable — a scenario should be constructible from fixtures, not from hardcoded inline data.

### Integration/UITestHarness/

Test harness views that allow the UI test target to launch the app in controlled states.

| File | Role |
|------|------|
| `ShellUITestHarnessView.swift` | Top-level harness view. Routes to specific shell panels based on launch arguments. |
| `CloudLibraryUITestHarnessView.swift` | CloudLibrary-specific harness. Loads deterministic fixture data for shell checkpoint tests. |

**Current state:**

`ShellExitHandlingDecision` already lives as its own file under `Integration/UITestHarness/`, which keeps the harness root more honest.

The remaining harness guidance is:
1. keep route driving separate from fixture injection where practical
2. keep checkpoint/export helpers deterministic and test-only
3. do not let preview or harness-only helpers leak into production paths

---

## General rules for Integration/

1. Nothing in `Integration/` is imported by the app's feature code directly. The features use protocol abstractions from `StratixCore` and `StreamingCore`. `Integration/` provides the concrete implementations.
2. All WebRTC-dependent code is in `Integration/WebRTC/` and is guarded with `#if WEBRTC_AVAILABLE`.
3. Preview data must not enter production code paths. Use `#if DEBUG` or Swift's `@_spi` if preview types need to be accessible from tests.
4. UI test harness views must not appear in the non-test build. They are compiled only when the `ShellUI` scheme is active or when the UI test target is the host.
