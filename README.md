# Stratix

[![Build](https://github.com/nafields/stratix/actions/workflows/ci-app-build-and-smoke.yml/badge.svg)](https://github.com/nafields/stratix/actions/workflows/ci-app-build-and-smoke.yml)
[![Packages](https://github.com/nafields/stratix/actions/workflows/ci-packages.yml/badge.svg)](https://github.com/nafields/stratix/actions/workflows/ci-packages.yml)
[![PR Guards](https://github.com/nafields/stratix/actions/workflows/ci-pr-fast-guards.yml/badge.svg)](https://github.com/nafields/stratix/actions/workflows/ci-pr-fast-guards.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg?logo=swift)](https://swift.org)
[![tvOS 26](https://img.shields.io/badge/tvOS-26.0-black.svg?logo=apple)](https://developer.apple.com/tvos/)
[![Platform: Apple TV](https://img.shields.io/badge/Platform-Apple%20TV-lightgrey.svg?logo=apple)](https://www.apple.com/apple-tv-4k/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Status: Early Alpha](https://img.shields.io/badge/Status-Early%20Alpha-yellow.svg)]()

Stratix is a native tvOS app that brings Xbox Game Pass cloud gaming to Apple TV. It is built from scratch in Swift because tvOS has no browser runtime and Microsoft does not make an official Apple TV app — so we made one. It streams Game Pass titles from Microsoft's xCloud service and can also stream games directly from your own Xbox console. Everything you need — authentication, WebRTC signaling, video rendering, controller input — is here in this repo, buildable and readable.

## Screenshots
| Demo |
|---|---|
| ![Demo](Docs/Screenshots/Demo.mp4) |

| Sign In | Loading |
|---|---|
| ![Sign In](Docs/Screenshots/Sign-In.png) | ![Loading](Docs/Screenshots/Loading.png) |

| Home| Side Menu |
|---|---|
|![Home](Docs/Screenshots/Home.png) | ![Side Menu](Docs/Screenshots/Side_Menu.png) |

| Game Details | Search |
|---|---|
| ![Game Details](Docs/Screenshots/Game_Details.png) | ![Search](Docs/Screenshots/Search.png) |

This is an early public alpha. The core flows work. There are rough edges. Specifically around UI/UX. Contributions are very welcome.

---

## What Is This, Exactly?

Xbox Game Pass Ultimate lets you stream Xbox games over the internet — a service Microsoft calls **xCloud**. When you play an xCloud game, the actual game is running on a server in a Microsoft datacenter. The video is encoded and streamed to your device over WebRTC, and your controller inputs are sent back the same way. You get a full Xbox game on your device without needing powerful local hardware.

Apple TV has no browser and Microsoft has never released an official Apple TV app, so there is no first-party way to use xCloud on tvOS. Stratix fills that gap by implementing the xCloud client protocol natively in Swift.

Stratix also supports **xHome** streaming. If you own an Xbox console, you can stream from that console directly to your Apple TV instead of going through Microsoft's cloud servers. xHome has lower latency when your Xbox and Apple TV are on the same network, and it doesn't require waiting in a cloud capacity queue.

> **Game Pass required for streaming.** You do not need an Xbox Game Pass Ultimate subscription to build, read, or explore the code. You do need one to sign in and actually stream games.

---

## What Works Right Now

| Feature | Status | Notes |
|---|---|---|
| Microsoft device-code sign-in | ✅ Working | Full token lifecycle with automatic refresh |
| Cloud library browsing | ✅ Working | Home rails, full library grid, and search |
| Title detail screens | ✅ Working | Metadata, artwork, launch actions |
| xCloud game streaming | ✅ Working | Primary streaming path, battle-tested |
| xHome console streaming | ⚠️ Not Fully Tested | Local console streaming over home network |
| Controller input | ✅ Working | Gamepad capture and 125 Hz input channel |
| Metal video rendering | ✅ Working | Metal-backed renderer with sample-buffer fallback |
| In-stream guide overlay | ✅ Working | Accessible overlay during active streams |
| Library persistence | ✅ Working | Disk-cached, restored across launches |
| Profile and achievements | ✅ Working | Xbox social API integration |
| Diagnostics and stream stats | ✅ Working | In-stream stats overlay and logging pipeline |
| Multi-account support | ❌ Not yet | Single Microsoft account only |
| Party and invite UX | ❌ Not yet | No group play features yet |
| Seamless auto-reconnect | ⚠️ Partial | Reconnect exists but is conservative |

For the full breakdown of what works, what is partial, and what is explicitly planned, see [`Docs/FEATURE_INVENTORY.md`](Docs/FEATURE_INVENTORY.md).

### Known rough edges

A few things are deliberately not finished yet and are worth naming upfront so they do not surprise you:

- **Multi-account:** The app assumes one Microsoft account at a time. Switching accounts requires signing out completely.
- **Party and invites:** No group play, no invites, no friend-session joining. This is a significant gap for social gaming but is on the roadmap.
- **Search | UI/UX:** Search and navigation work ok. But disappear occasionaly or trigger the side-rail inadvertantly. Create a PR if you have a fix or proposal.
- **Conservative reconnect:** If a stream drops, it reconnects — but not seamlessly. There is a noticeable recovery flow rather than a transparent resume.

If any of these affects you, they are also great places to contribute.

---

## Requirements

| Requirement | Version | Why |
|---|---|---|
| **Xcode** | 26 or newer | Required for Swift 6.2, the tvOS 26 SDK, and the updated Swift Testing and SwiftData APIs this project uses. Earlier Xcode builds will not open the workspace correctly. |
| **Swift** | 6.2 | Stratix runs with strict concurrency checking set to `complete`. Swift 6.2 makes this possible without painful workarounds — the compiler enforces actor isolation at build time, which means a successful build is a strong safety guarantee. |
| **tvOS SDK** | 26.0 | The deployment target. Both the simulator and any real device need to be running tvOS 26. |
| **Mac** | Apple Silicon recommended | The vendored WebRTC framework ships with `arm64` simulator slices. Intel Macs will have a harder time running the simulator path. |
| **Apple TV** | Simulator or device | Most flows work in the Apple TV simulator. A real Apple TV is needed for performance profiling work and real-network streaming tests. |

> **Always open `Stratix.xcworkspace`, not `Apps/Stratix/Stratix.xcodeproj`.** There are two ways to open this project and one of them breaks things. The workspace is what ties the app and its seven local Swift packages together. Opening the project file directly causes missing dependency errors. This is worth saying twice because it is the most common first mistake.

---

## Quick Start

**1. Clone the repository.**
```bash
git clone https://github.com/nafields/stratix.git
cd stratix
```

**2. Open the workspace — not the project file.**
```bash
open Stratix.xcworkspace
```
This opens the app together with all seven of its local Swift packages. Xcode will resolve the package graph automatically on first open — this takes a moment.

**3. Select the `Stratix-Debug` scheme.**
In Xcode's toolbar, click the scheme picker and select **Stratix-Debug**. This is the everyday development scheme.

**4. Choose an Apple TV simulator.**
In the destination picker, select **Apple TV 4K (3rd generation)** or any Apple TV simulator from the list.

**5. Build and run.**
Press **Cmd+R**. The first build compiles all seven Swift packages and takes a few minutes. Incremental builds are fast after that.

**What you'll see on first boot:** A sign-in screen asking you to visit a URL and enter a short code. This is Microsoft's device-code authentication flow — the standard auth approach for TV platforms where typing a password is impractical. You need a Microsoft account with an active Game Pass Ultimate subscription to get past this screen.

<details>
<summary>Build from the command line instead</summary>

The repo provides a validation wrapper that handles all the flags for you:

```bash
bash Tools/dev/run_debug_build.sh
```

Or, if you need a manual invocation:

```bash
xcodebuild -workspace Stratix.xcworkspace \
  -scheme Stratix-Debug \
  -sdk appletvsimulator \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  build
```

</details>

---

## Architecture Overview

Stratix is organized as a workspace-first monorepo. One Xcode workspace ties a single tvOS app target together with seven local Swift packages. The packages are layered: lower ones provide building blocks, higher ones orchestrate them, and the app target owns only presentation and composition.

```
                 StratixModels
                      │
                  (shared types, IDs, wire shapes — no dependencies)
                      │
   ┌──────────────────┼──────────────────┐
   │                  │                  │
DiagnosticsKit   InputBridge         XCloudAPI
 (logging,        (gamepad,          (auth, catalog,
  metrics)         input queue)       Xbox HTTP clients)
   │                  │                  │
   └──────────────────┼──────────────────┘
                      │
                 StreamingCore
              (WebRTC session, SDP/ICE,
               data channels, runtime contracts)
                      │
      ┌───────────────┼───────────────┐
      │                               │
VideoRenderingKit                StratixCore
 (render strategy,              (controllers, hydration,
  upscale logic)                 boot coordination,
                                 stream orchestration)
      └───────────────┬───────────────┘
                      │
                 Apps/Stratix
          (SwiftUI shell, Metal rendering,
           WebRTC integration, presentation)
```

**The rule that makes this work:** packages never depend on the app target. `StratixModels` sits at the bottom with no local dependencies. This means the networking layer, streaming runtime, and input handling can all be tested independently — without launching the app, without a simulator, without a network connection.

**What happens when you tap a game title:** The app resolves your auth tokens through `XCloudAPI`, creates a stream session through `StreamingCore`, exchanges WebRTC signaling with Microsoft's servers, and hands the resulting peer connection to a Metal-backed renderer in the app target. Your controller inputs go back to the server through `InputBridge` at 125 Hz. The entire lifecycle is orchestrated by `StratixCore`.

For the full picture — boot sequence, actor-isolation model, persistence — see [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md).

---

## Project Structure

```
stratix/
├── Stratix.xcworkspace              # Always open this. This is the entry point.
│
├── Apps/Stratix/                    # The tvOS app target
│   ├── Sources/Stratix/
│   │   ├── App/                     # Entry point, launch mode wiring
│   │   ├── Auth/                    # Device-code sign-in flow
│   │   ├── Features/                # CloudLibrary, Guide overlay, Streaming surface
│   │   ├── Integration/WebRTC/      # Concrete WebRTC bridge (Metal + framework attachment)
│   │   ├── Shell/                   # Authenticated app shell (tab view, top chrome)
│   │   └── Shared/                  # Reusable UI components, theme, image pipeline
│   └── Tests/                       # Unit, UI, and performance test targets
│
├── Packages/
│   ├── StratixModels/               # Shared vocabulary: typed IDs, value types, wire shapes.
│   │                                #   Everything else depends on this; it depends on nothing.
│   ├── DiagnosticsKit/              # Logging, metrics, and telemetry used across all layers.
│   ├── InputBridge/                 # Controller input capture, 125 Hz queueing, packet encoding.
│   │                                #   Deliberately UI-free — testable on macOS alone.
│   ├── XCloudAPI/                   # Everything that talks to Microsoft: auth tokens, xCloud
│   │                                #   catalog, Xbox social and profile APIs, stream setup.
│   ├── StreamingCore/               # WebRTC session facade, SDP/ICE negotiation, data channels,
│   │                                #   and runtime contracts. No UIKit, no Metal, no app shell.
│   ├── VideoRenderingKit/           # Render strategy selection and upscale capability logic.
│   │                                #   Small and focused — does not own Metal views or overlays.
│   └── StratixCore/                 # The orchestration layer. Long-lived controllers, hydration,
│                                    #   stream launch/reconnect, shell boot, settings store.
│
├── ThirdParty/
│   └── WebRTC/WebRTC.xcframework    # Pre-built WebRTC for tvOS (arm64 device + simulator)
│
├── Tools/
│   ├── dev/                         # Validation wrapper scripts (run_debug_build.sh, etc.)
│   ├── test/                        # Test runner helpers (shell regression, hardware checks)
│   ├── hooks/                       # Git pre-commit and pre-push hooks
│   ├── webrtc-build/                # Scripts for rebuilding WebRTC from source (advanced)
│   └── ci/                          # CI pipeline helpers
│
├── Docs/                            # All current documentation (start at Docs/README.md)
└── .github/workflows/               # CI pipelines
```

---

## How to Contribute

The best first contributions are ones that start small and build familiarity: fixing a doc that confused you, adding a test for a package behavior you traced through the code, improving a Xcode preview harness, or picking up a "not yet" item from [`Docs/FEATURE_INVENTORY.md`](Docs/FEATURE_INVENTORY.md). The codebase is thoroughly documented specifically to make this kind of exploration tractable — every subsystem has a doc that explains what it is and why it exists.

To make a change: install the git hooks once (`bash Tools/hooks/install_git_hooks.sh`), read the architecture docs for whatever surface you are changing, use the narrowest validation lane that honestly proves your change works, and write a PR description that explains what changed and why. Full details in [`CONTRIBUTING.md`](CONTRIBUTING.md). Community standards in [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

---

## Documentation

The full doc set lives under [`Docs/`](Docs/). Here is the guided path in:

**Start here**

| Doc | What it covers |
|---|---|
| [`Docs/GETTING_STARTED.md`](Docs/GETTING_STARTED.md) | From clone to first working build, with each step explained. Start here if you are new. |
| [`Docs/TESTING.md`](Docs/TESTING.md) | Which validation lane to use for which kind of change, and why the model is designed this way. Don't skip this before opening a PR. |
| [`Docs/TROUBLESHOOTING.md`](Docs/TROUBLESHOOTING.md) | Symptoms, causes, and fixes for common build, auth, streaming, and audio problems. |
| [`Docs/CONFIGURATION.md`](Docs/CONFIGURATION.md) | Every UserDefaults key, build flag, and Keychain entry, with defaults and explanations. |
| [`Docs/FEATURE_INVENTORY.md`](Docs/FEATURE_INVENTORY.md) | What the app can do right now, with honest partial and not-started markers for everything. |

**Architecture and subsystems**

| Doc | What it covers |
|---|---|
| [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md) | Package graph, boot sequence, actor-isolation model, and the overall shape of the codebase. |
| [`Docs/PACKAGE_GUIDE.md`](Docs/PACKAGE_GUIDE.md) | What each package owns, its dependencies, and — crucially — where new code belongs. |
| [`Docs/STREAMING_ARCHITECTURE.md`](Docs/STREAMING_ARCHITECTURE.md) | The full streaming stack from user tap to video on screen. |
| [`Docs/WEBRTC_GUIDE.md`](Docs/WEBRTC_GUIDE.md) | Why there is a custom WebRTC build, what was patched, and where the integration boundary sits. |
| [`Docs/CONTROLLER_INPUT.md`](Docs/CONTROLLER_INPUT.md) | The binary input protocol, the 125 Hz loop, and the packet wire format. |
| [`Docs/AUDIO_ARCHITECTURE.md`](Docs/AUDIO_ARCHITECTURE.md) | tvOS audio session setup, the WebRTC patches, and the current state of stereo audio. |
| [`Docs/UI_ARCHITECTURE.md`](Docs/UI_ARCHITECTURE.md) | Shell composition, routing, focus management, and SwiftUI state layering. |
| [`Docs/XCLOUD_PROTOCOL.md`](Docs/XCLOUD_PROTOCOL.md) | The xCloud signaling protocol and session creation flow. |
| [`Docs/DESIGN_DECISIONS.md`](Docs/DESIGN_DECISIONS.md) | Why major architectural choices were made, written in ADR format. |

**Reference and policies**

| Doc | What it covers |
|---|---|
| [`Docs/GLOSSARY.md`](Docs/GLOSSARY.md) | Definitions for every term of art in the codebase, grouped by domain. Check here when a term is unfamiliar. |
| [`Docs/FUTURE_WORK.md`](Docs/FUTURE_WORK.md) | Where the project is headed — open threads and high-impact contribution opportunities. |
| [`Docs/REPO_POLICIES.md`](Docs/REPO_POLICIES.md) | Non-negotiable constraints: Swift 6.2, strict concurrency, package boundaries. |
| [`Docs/OBSERVATION.md`](Docs/OBSERVATION.md) | How `@Observable` state flows through the app and how typed environment injection works. |
| [`Docs/HYDRATION.md`](Docs/HYDRATION.md) | How the library data is restored, refreshed, cached, and persisted across launches. |
| [`Docs/RUNTIME_FLOW.md`](Docs/RUNTIME_FLOW.md) | End-to-end user and runtime flows traced across package boundaries. |

---

## License

Stratix is licensed under the [GNU General Public License v3.0](LICENSE). In practical terms: you can use, study, and modify this code freely. If you distribute a modified version — as an app, a fork, or anything else — you must make your modifications available under the same GPL v3 terms. You cannot take this code and ship it as part of a closed-source product. If that constraint is relevant to what you want to build, read the full license text before going further.
