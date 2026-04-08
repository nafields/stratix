# Testing and Validation

Stratix uses a workspace-oriented validation model. The core idea is simple: **run the narrowest lane that honestly proves your change, then widen only when the change crosses more boundaries.**

This document explains what that means, how the test surfaces are organized, which wrapper scripts exist and what they actually run, and how to pick the right one for what you changed. For the concrete operational inventory — exact schemes, test-plan wiring, CI workflows, and hardware lane setup — see [`XCODE_VALIDATION_MATRIX.md`](XCODE_VALIDATION_MATRIX.md).

---

## Why This Validation Model Exists

Think of the test suite like a toolbox. A screwdriver is not better than a hammer — the right tool depends on what you are doing. Running the full validation sweep for a one-line change in a package model is wasteful and still doesn't prove anything about the shell. Running only a package test for a change that touched the streaming renderer is a lie — you got green, but you did not prove the surface you changed.

Stratix is a mixed codebase:
- A tvOS SwiftUI app with complex shell and focus behavior
- Seven local Swift packages, each testable independently
- A vendored WebRTC runtime that has its own integration boundary
- Deterministic UI harnesses that prove shell composition
- Performance and profiling lanes for rendering work

A green lane only means something if it matches the surface you changed. The validation model is designed around this: narrow lanes prove specific surfaces, and you pick the lane that matches your change. When a change crosses multiple surfaces, you compose lanes — run the package sweep *and* the shell UI lane, for example.

This keeps CI fast, keeps proof honest, and makes it easy to tell from a green result what exactly is proven.

---

## The Four Test Surfaces

### 1. Package tests

The fastest and most focused proof layer. Package tests run directly with `swift test` on macOS — no simulator required, no app target compilation. They prove pure logic, controllers, models, protocol handling, input encoding, and diagnostics behavior.

If you changed code in any of the seven packages, package tests are your first stop. They run in seconds to minutes depending on the package.

### 2. App test target

The app-side test target (`StratixTests`) proves app-owned composition, smoke behavior, launch-argument handling, shell-visible state, and the seams between the app and its packages. These tests require a simulator build and take longer than package tests.

### 3. UI test target

`StratixUITests` proves shell composition, route landmarks, focus restoration, and the deterministic harness-visible flows. These are the tests that confirm the shell looks and behaves correctly as a whole — that routes resolve, that overlays appear and dismiss, that focus moves correctly.

The shell harness is driven by launch arguments (defined in `StratixLaunchMode.swift`) that put the app into deterministic states without requiring real auth or live streaming. This is what makes the shell UI tests reliable.

### 4. Performance targets

`StratixPerformanceTests` and `StratixPerformanceUITests` cover performance-oriented UI and rendering lanes, especially around shell scrolling and Metal rendering behavior. You will rarely need these unless you are doing specific performance work.

---

## Which Test Framework?

The framework situation is mixed by design. Understanding this prevents confusion:

| Surface | Framework |
|---|---|
| Package tests | Mixed: Swift Testing and XCTest, depending on the package and suite |
| `StratixTests` | Primarily XCTest, with Swift Testing in active use in some areas |
| `StratixUITests` | XCTest / XCUITest |
| `StratixPerformanceTests` | XCTest |
| `StratixPerformanceUITests` | XCTest / XCUITest |

**Swift Testing** is in active use for new pure-Swift logic in packages. It has a cleaner syntax and better diagnostics for unit-style proof.

**XCTest** remains heavily present in app, UI, and performance targets. This is expected and is not a migration opportunity — XCUITest specifically will stay XCTest-based.

If you are writing new package tests, prefer Swift Testing. If you are writing new app-level tests, use whichever framework the surrounding tests use. Do not convert existing XCTest suites to Swift Testing as part of a feature change.

---

## Shared Workspace Schemes

These schemes live in `Stratix.xcworkspace/xcshareddata/xcschemes/`. You select them from Xcode's toolbar.

| Scheme | What it proves |
|---|---|
| `Stratix-Debug` | Day-to-day app build, smoke tests, and targeted simulator proof |
| `Stratix-ShellUI` | Deterministic shell and route harness proof |
| `Stratix-Packages` | All seven package test suites |
| `Stratix-Validation` | Broad sweep across app, packages, and integration |
| `Stratix-Perf` | Performance-oriented UI lane |
| `Stratix-Profile` | Manual Instruments profiling build (no test plan binding) |
| `Stratix-MetalProfile` | GPU and Metal profiling lane |
| `Stratix-ReleaseRun` | Release-configuration app build (no test plan binding) |

### Test plan wiring

Each scheme (except Profile and ReleaseRun) is bound to a test plan:

| Scheme | Test plan |
|---|---|
| `Stratix-Debug` | `Apps/Stratix/ShellRegression.xctestplan` |
| `Stratix-ShellUI` | `Apps/Stratix/ShellRegression.xctestplan` |
| `Stratix-Packages` | `Apps/Stratix/PackagesRegression.xctestplan` |
| `Stratix-Perf` | `Apps/Stratix/Performance.xctestplan` |
| `Stratix-MetalProfile` | `Apps/Stratix/MetalRendering.xctestplan` |
| `Stratix-Validation` | `Apps/Stratix/ValidationAll.xctestplan` |

**A note on `Stratix.xctestplan`:** This file still exists in the repo but is not the default plan for `Stratix-Debug`. Old docs and local project habits can mislead people here. The shared workspace debug lane is wired to `ShellRegression.xctestplan`.

---

## Validation Wrapper Scripts

The wrappers under `Tools/dev/` and `Tools/test/` are the preferred way to run validation. Use them instead of writing `xcodebuild` commands by hand — they encode the correct destination strings, derived-data paths, `-only-testing` slices, and environment variable requirements.

| Wrapper | What it runs |
|---|---|
| `bash Tools/dev/run_debug_build.sh` | Builds `Stratix-Debug` for Apple TV simulator |
| `bash Tools/dev/run_app_smoke.sh` | Runs the app smoke test slice on `Stratix-Debug` |
| `bash Tools/dev/run_package_sweep.sh` | Runs `swift test` across all seven local packages |
| `bash Tools/dev/run_runtime_safety.sh` | Runs the targeted runtime/WebRTC safety test slice |
| `bash Tools/dev/run_shell_ui_checks.sh` | Runs isolated shell checkpoint UI tests one by one |
| `bash Tools/dev/run_validation_build.sh` | Runs `Stratix-Validation` as a full test lane |
| `bash Tools/dev/run_release_build.sh` | Builds `Stratix-ReleaseRun` |
| `bash Tools/dev/run_hardware_shell_checks.sh` | Runs shell UI proof on a real device (needs `HARDWARE_DEVICE_ID`) |
| `bash Tools/test/run_shell_visual_regression.sh` | Reruns shell UI checkpoints, captures images, diffs against references |

When a wrapper exists, use it. The wrapper is a statement of intent — "this is the canonical way to prove this surface." Hand-written commands can drift from the correct flags over time.

---

## Choosing the Right Lane

Use this table as your first-pass guide. Pick the row that matches what you changed and run the listed lane. If your change crosses multiple rows, compose the corresponding lanes.

| What you changed | Minimum honest lane |
|---|---|
| Types, IDs, or value shapes in `StratixModels` | `run_package_sweep.sh` |
| Logic in any of the seven packages | `run_package_sweep.sh` |
| App composition, environment wiring, or app startup | `run_debug_build.sh` + `run_app_smoke.sh` |
| Shell routing, overlays, focus, or harness-visible flows | `run_shell_ui_checks.sh` |
| Visual shell layout or rendering drift | `run_shell_visual_regression.sh` (requires `ffmpeg`) |
| WebRTC bridge, streaming runtime, renderer, audio, or input channels | `run_runtime_safety.sh` + `run_validation_build.sh` |
| Broad closeout across app and packages | `run_validation_build.sh` |
| Release-shape build proof | `run_release_build.sh` |
| Real-device shell confidence | `run_hardware_shell_checks.sh` |
| Real-device performance capture | `run_hardware_profile_capture.sh` |

---

## App Test File Layout

App tests live under one physical root, grouped by function:

```
Apps/Stratix/Tests/
├── StratixTests/
│   ├── App/
│   ├── CloudLibrary/
│   ├── Consoles/
│   ├── Streaming/
│   ├── Shell/
│   └── Support/
├── StratixUITests/
├── StratixPerformanceTests/
└── StratixPerformanceUITests/
```

The functional grouping within `StratixTests/` means a file path is usually a better guide than just the target name when you are choosing which tests to run or where to add new ones.

---

## CI Workflow Overview

The CI pipelines under `.github/workflows/` map directly to the local wrapper lanes:

| Workflow | What it proves |
|---|---|
| `ci-app-build-and-smoke.yml` | Debug build plus app smoke — the fast PR gate |
| `ci-packages.yml` | Package sweep — runs on all package changes |
| `ci-pr-fast-guards.yml` | Architecture guards and docs checks |
| `ci-runtime-safety.yml` | Targeted streaming/WebRTC safety proof |
| `ci-shell-ui.yml` | Shell UI wrapper |
| `ci-shell-visual-regression.yml` | Manual shell visual regression plus artifact upload |
| `ci-release-and-validation.yml` | Release build plus full validation sweep |
| `ci-hardware-device.yml` | Self-hosted hardware shell checks |
| `ci-shell-state-tests.yml` | Shell-state regression wrapper |

Two things to know:
- Hardware device proof uses a **self-hosted runner** and is not part of the normal hosted CI floor. It requires a registered Apple TV.
- `ci-release-and-validation.yml` is a broader lane than the fast PR guards and should not be treated as interchangeable with them.

---

## Mock vs. Real Runtime in Tests

The repo intentionally separates the WebRTC protocol boundary from the concrete framework binding. This matters for testing:

- `StreamingCore` owns the `WebRTCBridge` protocol surface — tests can be written against this protocol without the real framework
- `Apps/Stratix/Integration/WebRTC/WebRTCClientImpl.swift` owns the concrete, framework-backed implementation
- `MockWebRTCBridge` is available for tests, previews, and harnesses that need a deterministic, no-network bridge

Do not assume every test uses the real WebRTC framework just because the build configuration defines `WEBRTC_AVAILABLE`. Many tests are intentionally written against the protocol seam — that is a feature, not a limitation. It is what makes those tests fast, reliable, and runnable without a network connection.

---

## Current Caveats Worth Knowing

**Apple Silicon is effectively required for the main simulator lanes.** The vendored WebRTC xcframework ships with `arm64` simulator support. Intel Macs will have trouble with simulator paths.

**`run_shell_ui_checks.sh` is narrow on purpose.** It proves a small number of deterministic shell checkpoints — not a broad UI suite. This is intentional: narrow tests fail fast and point directly at what broke. If you want broader coverage, `run_validation_build.sh` is the full sweep.

**`run_shell_visual_regression.sh` requires `ffmpeg`.** Visual regression proof captures screenshots and diffs them against references. Install `ffmpeg` before using this wrapper.

**Hardware wrappers need `HARDWARE_DEVICE_ID` or `TVOS_HARDWARE_DEVICE_ID`.** There is no hardcoded device ID. Set the environment variable to your device's identifier before running hardware wrappers.

**Device proof still matters for some questions.** Simulator success is necessary but not always sufficient. Streaming performance, audio behavior under load, and real-network behavior all require a real device to be fully proven.

**Bundle identifiers are `com.stratix.appletv*`.** Any doc that mentions `com.greenlight.*` bundle identifiers is stale.

---

## Related Docs

- [`GETTING_STARTED.md`](GETTING_STARTED.md) — first build and first validation pass
- [`XCODE_VALIDATION_MATRIX.md`](XCODE_VALIDATION_MATRIX.md) — concrete operational inventory of all schemes, wrappers, and CI lanes
- [`CONFIGURATION.md`](CONFIGURATION.md) — build flags and runtime settings
- [`PERFORMANCE.md`](PERFORMANCE.md) — profiling surfaces and performance test lanes
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — what to do when a test or build fails unexpectedly
