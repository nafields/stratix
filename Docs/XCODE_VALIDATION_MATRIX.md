# Xcode Validation Matrix

This file is the operational map of the live validation surface for the current `Stratix` workspace.

Use it with [TESTING.md](TESTING.md):

- [TESTING.md](TESTING.md) explains how to choose proof
- this file records the concrete schemes, test plans, wrapper scripts, and CI workflows that exist right now

## Canonical Entry Point

The current validation surface is workspace-first:

- workspace: `Stratix.xcworkspace`
- app project: `Apps/Stratix/Stratix.xcodeproj`

When in doubt, start from the workspace and shared schemes rather than a project-local scheme or a stale document.

## Shared Workspace Scheme Inventory

| Scheme | Configuration | Current purpose |
|--------|---------------|-----------------|
| `Stratix-Debug` | `Debug` | standard app build, app smoke, targeted simulator proof |
| `Stratix-ShellUI` | `Debug` | deterministic shell checkpoint and harness-visible shell proof |
| `Stratix-Packages` | `Debug` | package regression lane |
| `Stratix-Validation` | `Debug` | broad validation sweep |
| `Stratix-Perf` | `Profile` | performance UI lane |
| `Stratix-Profile` | `Profile` | manual profiling build |
| `Stratix-MetalProfile` | `Profile` | Metal and renderer profiling lane |
| `Stratix-ReleaseRun` | `Release` | release-shape app build |

## Shared Test-Plan Wiring

These are the current scheme-to-plan bindings in `Stratix.xcworkspace/xcshareddata/xcschemes/`:

| Scheme | Test plan |
|--------|-----------|
| `Stratix-Debug` | `Apps/Stratix/ShellRegression.xctestplan` |
| `Stratix-ShellUI` | `Apps/Stratix/ShellRegression.xctestplan` |
| `Stratix-Packages` | `Apps/Stratix/PackagesRegression.xctestplan` |
| `Stratix-Perf` | `Apps/Stratix/Performance.xctestplan` |
| `Stratix-MetalProfile` | `Apps/Stratix/MetalRendering.xctestplan` |
| `Stratix-Validation` | `Apps/Stratix/ValidationAll.xctestplan` |
| `Stratix-Profile` | none |
| `Stratix-ReleaseRun` | none |

Operational note:

- `Apps/Stratix/Stratix.xctestplan` exists in the repo
- it is not the shared debug-lane source of truth

## Test-Plan Surface

The current test plans under `Apps/Stratix/` are:

| Test plan | Targets included |
|-----------|------------------|
| `ShellRegression.xctestplan` | `StratixUITests`, `StratixTests` |
| `PackagesRegression.xctestplan` | `StratixTests` |
| `Performance.xctestplan` | `StratixPerformanceUITests` |
| `MetalRendering.xctestplan` | `StratixPerformanceTests`, `StratixPerformanceUITests` |
| `ValidationAll.xctestplan` | `StratixUITests`, `StratixTests`, `StratixPerformanceTests`, `StratixPerformanceUITests` |
| `Stratix.xctestplan` | `StratixTests`, `StratixUITests` but not wired into the shared workspace schemes |

## Wrapper Lanes

The scripts under `Tools/dev/` and `Tools/test/` are the fastest honest entry points for day-to-day proof.

| Lane | Wrapper | Underlying proof |
|------|---------|------------------|
| Debug build | `bash Tools/dev/run_debug_build.sh` | simulator build of `Stratix-Debug` |
| App smoke | `bash Tools/dev/run_app_smoke.sh` | targeted app smoke test slice on `Stratix-Debug` |
| Package sweep | `bash Tools/dev/run_package_sweep.sh` | `swift test` across all seven local packages |
| Runtime safety | `bash Tools/dev/run_runtime_safety.sh` | targeted runtime/WebRTC safety slice on `Stratix-Debug` |
| Shell UI | `bash Tools/dev/run_shell_ui_checks.sh` | isolated shell checkpoint tests on `Stratix-ShellUI` |
| Validation sweep | `bash Tools/dev/run_validation_build.sh` | full `Stratix-Validation` test run |
| Release build | `bash Tools/dev/run_release_build.sh` | `Stratix-ReleaseRun` build |
| Hardware shell checks | `bash Tools/dev/run_hardware_shell_checks.sh` | real-device shell checkpoint proof using env-provided device id |
| Hardware profile capture | `bash Tools/perf/run_hardware_profile_capture.sh` | hardware profiling capture |
| Shell visual regression | `bash Tools/test/run_shell_regression_checks.sh` | reruns shell UI, captures screenshots, diffs against canonical references |
| Architecture guards | `bash Tools/dev/run_architecture_guards.sh` | current Python guard suite for architecture constraints |
| Docs checks | `bash Tools/docs/run_docs_checks.sh` | docs portability, docs truth sync, and repo-hygiene checks |

## What Each Lane Is Actually Good For

### Fast guards

Use when:

- you changed structure-sensitive code
- you changed docs and want the docs checks
- you want early failure before heavier Xcode lanes

Entry points:

- `bash Tools/dev/run_architecture_guards.sh`
- `bash Tools/docs/run_docs_checks.sh`

### Package sweep

Use when:

- your change stays inside `Packages/`
- you changed models, settings, controllers, diagnostics, input, or protocol code
- you want the fastest broad logic confidence lane

Entry point:

```bash
bash Tools/dev/run_package_sweep.sh
```

### Debug build

Use when:

- you changed the app target but do not yet need a full test run
- you want to prove the main simulator app still builds

Entry point:

```bash
bash Tools/dev/run_debug_build.sh
```

### App smoke

Use when:

- the app starts and compiles, but you also want a targeted app-target sanity check
- your change touches app wiring or launch behavior

Entry point:

```bash
bash Tools/dev/run_app_smoke.sh
```

### Shell UI

Use when:

- you changed shell composition
- you changed focus or destination switching
- you changed route restoration or shell overlay behavior

Entry point:

```bash
bash Tools/dev/run_shell_ui_checks.sh
```

Important operational truth: this wrapper runs isolated tests one by one because those checkpoints are more stable in separate sessions than in a broad combined xcodebuild run.

### Shell visual regression

Use when:

- the change is visual
- you need screenshot-level shell drift detection

Entry point:

```bash
bash Tools/test/run_shell_regression_checks.sh
```

This wrapper reruns the shell UI lane before capture and requires `ffmpeg`.

### Runtime safety

Use when:

- you changed WebRTC integration
- you changed renderer selection or transport boundaries
- you changed streaming runtime safety behavior

Entry point:

```bash
bash Tools/dev/run_runtime_safety.sh
```

### Validation sweep

Use when:

- the change crosses app and package boundaries
- you are closing out a broad refactor
- you want the current broad proof lane

Entry point:

```bash
bash Tools/dev/run_validation_build.sh
```

### Hardware lanes

Use when:

- you need real-device shell proof
- you need real-device performance capture
- simulator proof is not enough for the question you are answering

Current entry points:

```bash
HARDWARE_DEVICE_ID=<device-id> bash Tools/dev/run_hardware_shell_checks.sh
bash Tools/perf/run_hardware_profile_capture.sh
```

`run_hardware_shell_checks.sh` requires `HARDWARE_DEVICE_ID` or `TVOS_HARDWARE_DEVICE_ID`.

## CI Workflow Matrix

The current workflow map is:

| Workflow | What it runs |
|----------|--------------|
| `ci-app-build-and-smoke.yml` | `run_debug_build.sh`, `run_app_smoke.sh` |
| `ci-packages.yml` | `run_package_sweep.sh` |
| `ci-pr-fast-guards.yml` | `run_architecture_guards.sh`, `Tools/docs/run_docs_checks.sh` |
| `ci-runtime-safety.yml` | `run_runtime_safety.sh` |
| `ci-shell-ui.yml` | `run_shell_ui_checks.sh` |
| `ci-shell-visual-regression.yml` | `run_shell_regression_checks.sh` plus artifact upload |
| `ci-release-and-validation.yml` | `run_release_build.sh`, `run_validation_build.sh`, workflow export evidence |
| `ci-hardware-device.yml` | `run_hardware_shell_checks.sh` on self-hosted hardware |
| `ci-shell-state-tests.yml` | `run_stage4_shell_tests.sh` |

The hosted baseline is useful, but it is not identical to the full local proof surface:

- hardware proof is separate and self-hosted
- profiling lanes are still effectively local or device-oriented
- wrapper behavior matters as much as workflow names

## Minimum Recommended Proof By Change Type

| Change type | Recommended minimum proof |
|-------------|---------------------------|
| Package-only logic | package sweep |
| App build or composition change | debug build plus app smoke |
| Shell UI, focus, or route change | shell UI |
| Shell visual change | shell UI plus shell visual regression |
| Streaming, WebRTC, audio, or renderer change | runtime safety plus validation sweep |
| Broad refactor | debug build plus validation sweep |
| Release-shape confidence | release build plus validation sweep |
| Real-device shell behavior | hardware shell checks |

## Current Direct Command Shapes

### Debug build

```bash
xcodebuild -quiet \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/stratix_debug_build \
  -clonedSourcePackagesDirPath /tmp/stratix_debug_build_spm \
  build
```

### Validation sweep

```bash
xcodebuild \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-Validation \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/stratix_validation_lane \
  -clonedSourcePackagesDirPath /tmp/stratix_validation_lane_spm \
  test
```

### Shell UI build-for-testing

```bash
xcodebuild \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-ShellUI \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  build-for-testing
```

## Operational Rules

- prefer shared workspace schemes over project-local ones
- prefer wrapper scripts over hand-written commands when a wrapper exists
- rerun the narrowest honest lane before escalating to a broad sweep
- use unique temporary build paths when running multiple lanes at once
- treat hardware proof as complementary to simulator proof, not a replacement for it

## Current Caveats

- `Stratix.xctestplan` is present but not wired to the shared debug scheme
- the shell UI lane is intentionally narrow and isolated, not a general UI sweep
- shell visual regression requires `ffmpeg`
- hardware proof requires an environment-provided device identifier
- bundle identifiers are already on the `com.stratix.appletv*` family; any contrary doc is stale

## Related Docs

- [TESTING.md](TESTING.md)
- [GETTING_STARTED.md](GETTING_STARTED.md)
- [CONFIGURATION.md](CONFIGURATION.md)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
