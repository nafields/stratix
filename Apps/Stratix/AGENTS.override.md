# AGENTS.override.md — Apps/Stratix

This override applies to the entire `Stratix` app target directory. Read the root `AGENTS.md` first.

**Modernization contract reference:** For app-target work governed by the modernization program, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with `Docs/Stratix_Modernization_Plan.md`, `Docs/Stratix_Monolith_Breakdown.md`, and `Docs/Stratix_File_Matrix.md`.

**Skill policy reference:** Use the root AGENTS skill policy together with `Docs/Stratix_Skill_Policy.md`. For app-target work, default to `[$ios-skills:ios-skills-router](/Users/nicholas/.ios-skills/skills/_router/SKILL.md)`, `[$ios-skills:swiftui-pro](/Users/nicholas/.ios-skills/skills/twostraws--swiftui-pro/SKILL.md)`, `[$ios-skills:swift-concurrency-pro](/Users/nicholas/.ios-skills/skills/twostraws--swift-concurrency-pro/SKILL.md)`, and `[$ios-skills:swift-accessibility-skill](/Users/nicholas/.ios-skills/skills/pasqualevittoriosi--swift-accessibility/SKILL.md)` before editing UI or focus/navigation code.

---

## What this directory is

`Apps/Stratix/` is the single tvOS app target. It contains:

- `Sources/Stratix/` — all production Swift source files
- `Tests/StratixTests/` — unit tests grouped by feature area
- `Tests/StratixUITests/` — shell checkpoint and UI regression tests grouped by function
- `Tests/StratixPerformanceTests/` — performance tests grouped by function
- `Tests/StratixPerformanceUITests/` — performance UI tests grouped by function
- `Stratix.xcodeproj/` — Xcode project file

---

## Project file rules

The Xcode project file (`Stratix.xcodeproj/project.pbxproj`) is the source of truth for which files are compiled, which test targets they belong to, and what build settings are active.

When you add, move, or delete a Swift source file, you must also update `project.pbxproj` to reflect the change. Failing to do so means the file will be excluded from builds or tests silently.

Do not change the following build settings without an explicit reason:
- `SWIFT_VERSION = 6.2`
- `SWIFT_STRICT_CONCURRENCY = complete`
- `TVOS_DEPLOYMENT_TARGET = 26.0`
- `OTHER_SWIFT_FLAGS = -DWEBRTC_AVAILABLE`

---

## App Skill Routing

Use these additional skills when the work matches:

- `[$ios-skills:swiftui-view-refactor](/Users/nicholas/.ios-skills/skills/dimillian--swiftui-view-refactor/SKILL.md)` for large SwiftUI host/container files such as CloudLibrary shell and route hosts
- `[$ios-skills:swiftui-performance-audit](/Users/nicholas/.ios-skills/skills/dimillian--swiftui-performance-audit/SKILL.md)` for route switching, focus churn, and expensive view recomposition
- `[$ios-skills:swiftui-uikit-interop](/Users/nicholas/.ios-skills/skills/dpearson2699--swiftui-uikit-interop/SKILL.md)` for streaming/rendering bridge surfaces
- `[$ios-skills:swiftui-liquid-glass](/Users/nicholas/.ios-skills/skills/dimillian--swiftui-liquid-glass/SKILL.md)` for tvOS 26 shell chrome/material work
- `[$ios-skills:debugging-instruments](/Users/nicholas/.ios-skills/skills/dpearson2699--debugging-instruments/SKILL.md)` for AVFoundation, rendering, streaming, and performance investigations
- `[$ios-skills:xcodebuildmcp](/Users/nicholas/.ios-skills/skills/getsentry--xcodebuildmcp/SKILL.md)` or `[$ios-skills:ios-debugger-agent](/Users/nicholas/.ios-skills/skills/dimillian--ios-debugger-agent/SKILL.md)` for simulator/device validation
- `[$ios-skills:swift-testing-expert](/Users/nicholas/.ios-skills/skills/avdlee--swift-testing-expert/SKILL.md)` for any pure-Swift test migration inside app tests, while keeping XCUI work on XCTest

---

## Test target rules

**StratixTests** — unit tests
- Framework: currently XCTest, migrating to Swift Testing
- Scope: state machines, data shaping, routing, focus, streaming surface model
- One test file per type under test, named `[TypeName]Tests.swift`
- Do not put UI automation here

**StratixUITests** — shell checkpoint UI tests
- Framework: XCTest + XCUI (must stay XCTest)
- Current state: shell checkpoint coverage is already split across helper/support files plus the remaining root test classes
- Do not add Swift Testing imports here

**StratixPerformanceTests** — performance measurements
- Framework: XCTest
- Use the `Stratix-Perf` scheme for runs
- `PerformanceTestSupport.swift` is a `@MainActor enum` containing launch argument constants and app factory helpers. Lower priority than other splits. Tracked as EF-6.

**StratixPerformanceUITests** — performance UI scenarios
- Framework: XCTest + XCUI
- Use the `Stratix-Perf` or `Stratix-ShellUI` scheme

---

## Source directory map

| Directory | What lives here |
|-----------|----------------|
| `App/` | Entry point (`StratixApp`), delegate, root view, launch mode flags |
| `Auth/` | Auth screen, device code screen |
| `Consoles/` | Console list view, stream launch coordinator, focus coordinator |
| `Data/CloudLibrary/` | Side-effect-free data shaping (no async, no state) |
| `Features/CloudLibrary/` | Full CloudLibrary vertical slice |
| `Features/Guide/` | Guide overlay |
| `Features/Streaming/` | Stream view, overlay, rendering surface |
| `Integration/Previews/` | Preview data and fixture scaffolding |
| `Integration/UITestHarness/` | UI test harness views |
| `Integration/WebRTC/` | Metal renderer + WebRTC client implementation |
| `Models/` | App-local model types not in StratixModels |
| `Profile/` | Profile overlay view components |
| `RouteState/` | NavigationTypes |
| `Sections/` | Guide pane section builders |
| `Shared/Components/` | Reusable UI components |
| `Shared/Theme/` | Design tokens and the remote image pipeline |
| `Shell/` | AuthenticatedShellView |
| `ViewState/` | CloudLibraryViewState, NavigationPerformanceTracker, StatusFeedback |

---

## Current modernization posture in this target

The major floor-blocker file moves, dissolutions, and merges for the app target have already landed. Treat the current app structure as the baseline unless a new approved modernization wave says otherwise.

The remaining work in this target is follow-up quality work:

- keep route/action closures explicitly `@MainActor`
- avoid reintroducing passthrough wrappers that were already dissolved
- keep tests domain-shaped instead of rebuilding monolithic test roots
- keep shared/theme and streaming/rendering seams aligned with the current split
