# Getting Started with Stratix

This guide is for anyone who has just cloned Stratix and is wondering where to start. By the end of it, you will have a working build on your Mac, understand enough about the repo structure to know where things live, and know which test command to run for your first change.

If something breaks at any point, [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) covers the most common problems — build errors, missing simulators, WebRTC issues, and auth failures. It is a good tab to have open alongside this one.

---

## What You Are Opening

Before you run a single command, it helps to understand what kind of project this is.

Stratix is a **workspace-first monorepo**. That means:

- The shipping tvOS app lives under `Apps/Stratix/`
- The app depends on seven local Swift packages that live under `Packages/`
- Everything is tied together by `Stratix.xcworkspace` at the root
- There is also a pre-built WebRTC binary under `ThirdParty/WebRTC/`
- The `Tools/` directory contains the validation scripts that CI and contributors use

You do not need to assemble anything manually. The repo already contains the workspace, the package manifests, the app project, the test plans, and the vendored WebRTC binary. You clone, open the workspace, and build.

---

## Requirements

Here is what you need before you start, and why each item matters:

| Requirement | Value | Why it matters |
|---|---|---|
| Xcode | 26 or newer | Required for Swift 6.2, the tvOS 26 SDK, and the modern Swift Testing and SwiftData APIs the project uses. Older Xcode versions will not open the workspace correctly. |
| Swift | 6.2 | The project runs with strict concurrency checking set to `complete`. Swift 6.2 is what makes this feasible — the compiler enforces actor isolation at build time, giving you strong safety guarantees for free. |
| Deployment target | tvOS 26.0 | The minimum tvOS version the app supports. Both simulator and device builds need to match. |
| Mac | Apple Silicon recommended | The vendored WebRTC framework ships with `arm64` simulator slices. Intel Macs can work but may struggle with the simulator path. |
| Apple TV | Simulator or device | Most development and testing happens in the simulator. A real Apple TV is needed for performance profiling and real-network streaming tests. |

For specialized work you may also need:
- **Python 3** — some repo scripts and the WebRTC rebuild tooling use it
- **`ffmpeg`** — the shell visual regression checks require it
- **Physical Apple TV** — for hardware shell checks and real streaming confidence

### Verify your toolchain

Run these before doing anything else:

```bash
xcode-select --print-path
xcodebuild -version
swift --version
```

You should see an Xcode 26+ path and a Swift 6.2-compatible compiler. If `xcode-select` points somewhere unexpected:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

---

## The Most Important Thing: Open the Workspace

> **Always open `Stratix.xcworkspace`. Never open `Apps/Stratix/Stratix.xcodeproj` directly.**

This is the most common first mistake, so it deserves emphasis before anything else. There are two ways to open this project in Xcode, and only one of them works correctly.

- `Stratix.xcworkspace` — **correct**. This wires the app target together with all seven local Swift packages. The shared workspace schemes (`Stratix-Debug`, `Stratix-ShellUI`, etc.) live here. All validation wrappers assume this entry point.
- `Apps/Stratix/Stratix.xcodeproj` — **incorrect for normal development**. Opening this directly causes missing-dependency errors because Xcode cannot see the local packages. The scheme set will also be wrong.

```bash
open Stratix.xcworkspace
```

When the workspace first opens, Xcode resolves the Swift package graph. This takes a moment — it is downloading nothing, just indexing the seven local packages from `Packages/`. Let it finish before selecting a scheme.

---

## Repo Structure

Here is the layout you need to understand before making changes. You do not need to memorize this — just know that it exists so you can find things.

```
stratix/
├── Stratix.xcworkspace              ← always open this
│
├── Apps/Stratix/
│   ├── Sources/Stratix/
│   │   ├── App/                     ← entry point and launch-mode wiring
│   │   ├── Auth/                    ← device-code sign-in flow
│   │   ├── Consoles/                ← console list and xHome launch
│   │   ├── Data/CloudLibrary/       ← pure data shaping for library UI
│   │   ├── Features/                ← CloudLibrary, Guide overlay, Streaming surface
│   │   ├── Integration/             ← WebRTC bridge, previews, UI test harnesses
│   │   ├── Profile/                 ← profile overlay UI
│   │   ├── Shared/                  ← shared UI components and theme
│   │   ├── Shell/                   ← authenticated app shell (tab view, chrome)
│   │   └── ViewState/               ← app-owned derived view state
│   ├── Tests/                       ← unit, UI, and performance test targets
│   ├── *.xctestplan                 ← shared test plans used by workspace schemes
│   └── Stratix.xcodeproj            ← do not open this directly
│
├── Packages/
│   ├── StratixModels/               ← shared types; depends on nothing
│   ├── DiagnosticsKit/              ← logging, metrics, telemetry
│   ├── InputBridge/                 ← controller input capture and encoding
│   ├── XCloudAPI/                   ← Xbox/xCloud HTTP clients and auth
│   ├── StreamingCore/               ← WebRTC session, SDP/ICE, channels
│   ├── VideoRenderingKit/           ← render strategy selection
│   └── StratixCore/                 ← controllers, hydration, boot, orchestration
│
├── ThirdParty/WebRTC/               ← vendored xcframework (arm64 device + simulator)
├── Tools/                           ← validation wrappers, docs checks, WebRTC build tools
├── Docs/                            ← all current documentation
└── Docs_to_update/                  ← historical reference only; not current truth
```

If you want to understand why the packages are split this way — and especially where new code should go — [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md) is the right next read.

---

## Workspace Schemes

The repo uses shared workspace schemes that live in `Stratix.xcworkspace/xcshareddata/xcschemes/`. You will always select one of these from Xcode's toolbar scheme picker.

| Scheme | What it is for |
|---|---|
| `Stratix-Debug` | Day-to-day development. Build, run, and targeted simulator testing. This is your default. |
| `Stratix-ShellUI` | Deterministic shell and route harness lane. Use this when your change touches shell routing, focus, or overlay behavior. |
| `Stratix-Packages` | Package regression. Runs all seven package test suites. Use after any package-level change. |
| `Stratix-Validation` | Broad validation sweep. Use before a wide-scope PR closeout. |
| `Stratix-Perf` | Performance UI lane. For benchmarking and performance-sensitive changes. |
| `Stratix-Profile` | Manual profiling build. Use with Instruments. |
| `Stratix-MetalProfile` | GPU and Metal profiling. Use for rendering performance investigation. |
| `Stratix-ReleaseRun` | Release-configuration build. Use to test release-shape behavior. |

For most development, you will use `Stratix-Debug` while iterating, then switch to `Stratix-Packages` or `Stratix-ShellUI` before committing.

---

## Your First Build

### In Xcode

1. Open `Stratix.xcworkspace`
2. Select the `Stratix-Debug` scheme from the toolbar
3. Choose **Apple TV 4K (3rd generation)** from the simulator picker
4. Press **Cmd+R**

The first build compiles all seven Swift packages and the app target — expect a few minutes. Incremental builds are fast after that.

### From the command line

The repo provides a wrapper that handles all the flags:

```bash
bash Tools/dev/run_debug_build.sh
```

Under the hood, this runs:

```bash
xcodebuild -quiet \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/stratix_debug_build \
  -clonedSourcePackagesDirPath /tmp/stratix_debug_build_spm \
  build
```

Prefer the wrapper. It stays up-to-date with the correct destination strings, derived-data paths, and any flags the CI pipeline uses.

---

## What You Will See on First Launch

When the app boots for the first time, you will land on a sign-in screen — not the game library. This is expected.

The sign-in flow works like this:

1. The app shows a short code and asks you to visit a URL on another device
2. You sign in to your Microsoft account at that URL and enter the code
3. The app receives the auth token and takes you to the authenticated shell
4. The main CloudLibrary view (home, full library, search) becomes your primary surface

This is Microsoft's device-code authentication flow — the standard approach for TV platforms where typing a full password with a remote control is impractical.

**You need a Microsoft account with an active Xbox Game Pass Ultimate subscription to get past the sign-in screen.** The subscription is what grants access to the xCloud streaming service. You can build, run, and explore all the code without a subscription — you just cannot stream games.

If you are doing development work that does not require sign-in (package logic, shell composition, preview work), you can use the UI test harness launch modes instead. Those are controlled by launch arguments in `Apps/Stratix/Sources/Stratix/App/StratixLaunchMode.swift` and do not require authentication.

---

## Simulator Versus Device

Most development and testing happens in the simulator. Here is when each matters:

**Simulator is sufficient for:**
- App shell, routing, and focus work
- Package logic and unit tests
- Library browsing and presentation
- Preview harnesses
- Most integration and smoke tests

**A real Apple TV is needed for:**
- Performance profiling (Instruments, MetalHUD)
- Real-network streaming tests
- Hardware controller input testing
- The highest-confidence streaming/runtime proof

The vendored WebRTC framework includes simulator slices, so the full bridge code compiles and links on simulator — you are not working with a stripped-down mock build.

---

## Your First Validation Pass

After your build succeeds, the next step before making any change is knowing which test command to run. The principle is simple: **run the narrowest test lane that honestly proves your change.**

Running everything is not the right default. It is slow, and a green result only means something if it matches what you changed. Running nothing is obviously wrong. The goal is the lane that actually proves your surface.

Here is the quick guide:

```bash
# Changed something in a Package?
bash Tools/dev/run_package_sweep.sh

# Changed app composition or startup?
bash Tools/dev/run_debug_build.sh
bash Tools/dev/run_app_smoke.sh

# Changed shell routing, focus, overlays, or navigation?
bash Tools/dev/run_shell_ui_checks.sh

# Changed streaming, WebRTC, renderer, or audio?
bash Tools/dev/run_runtime_safety.sh

# Broad closeout before a PR?
bash Tools/dev/run_validation_build.sh
```

For the full breakdown of what each lane runs, when to use each one, and how CI maps to these wrappers, see [`TESTING.md`](TESTING.md).

---

## Runtime Settings and Configuration

The app stores user-facing settings in `UserDefaults` through `SettingsStore`:

- **Location:** `Packages/StratixCore/Sources/StratixCore/SettingsStore.swift`
- **Isolation:** `@MainActor @Observable`
- **Categories:** shell, library, stream, controller, accessibility, diagnostics

During development, you can change settings through the app's guide overlay UI or by writing defaults from the Xcode debugger:

```swift
// In the Xcode debugger console (lldb):
expr UserDefaults.standard.set("sampleBuffer", forKey: "guide.renderer_mode")
expr UserDefaults.standard.set(true, forKey: "guide.show_stream_stats")
expr UserDefaults.standard.set(false, forKey: "guide.stereo_audio")
```

Not every setting takes effect immediately. Some stream settings only apply on the next session start. [`CONFIGURATION.md`](CONFIGURATION.md) documents which categories apply immediately and which require a stream or app restart.

---

## Auth Tokens and Secrets

Auth tokens are stored in the platform Keychain, not in source-controlled files.

- **Location:** `Packages/XCloudAPI/Sources/XCloudAPI/Auth/TokenStore.swift`
- **Storage:** platform Keychain
- **Key family:** `stratix.*` (migrates older `greenlight.*` entries forward on read)

Do not:
- Put real auth tokens in `.env` files
- Copy real token values into docs, tests, or preview data
- Export UserDefaults or Keychain contents from a machine that has personal auth state and commit them

---

## Common First Problems

**"The project builds in Xcode but my wrapper script fails."**
The wrappers target specific schemes, test plans, or `-only-testing` slices that are narrower than a manual build. Check what each wrapper does in [`TESTING.md`](TESTING.md) — the narrowness is intentional.

**"I opened the project file and my schemes do not match the docs."**
The shared schemes live in the workspace, not the project. Open `Stratix.xcworkspace`.

**"I changed a setting but the app didn't react."**
Not every setting is hot-applied. Check [`CONFIGURATION.md`](CONFIGURATION.md) for which settings require a stream restart or app restart to take effect.

**"I don't know where new code belongs."**
Read [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md). Those two docs answer "where does this go?" faster than anything else.

**"Build failed with Swift concurrency errors."**
This is expected if you are adding code that crosses actor boundaries without the correct isolation annotation. The errors are the compiler telling you something real. Read the error message carefully — it usually points directly at the unsafety. Do not add `@unchecked Sendable` or `nonisolated(unsafe)` to silence the error without understanding it first.

For build, auth, streaming, and audio failures, see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## What to Read Next

After this guide, the best follow-up order is:

1. [`TESTING.md`](TESTING.md) — understand the validation model before making your first change
2. [`ARCHITECTURE.md`](ARCHITECTURE.md) — understand the package graph and where code lives
3. [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md) — understand where new code belongs
4. [`CONFIGURATION.md`](CONFIGURATION.md) — understand runtime settings and build flags
5. [`FEATURE_INVENTORY.md`](FEATURE_INVENTORY.md) — understand what works and what doesn't
6. [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — keep this handy for when things break
