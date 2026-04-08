# Stratix Documentation

Welcome. This directory is the complete documentation set for the Stratix codebase.

If you are new to the project, start with [`GETTING_STARTED.md`](GETTING_STARTED.md) — it walks you through your first build step by step. If something is broken, start with [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md). If you want to understand the architecture before making a change, [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md) are the right place.

Every doc here describes the current live repo. If something in a doc contradicts what you see in the code, trust the code and please open a PR fixing the doc.

---

## The Repo This Docs Set Describes

These docs describe the following live repo shape:

| | Value |
|---|---|
| Workspace | `Stratix.xcworkspace` |
| App target | `Apps/Stratix` |
| App module | `Stratix` |
| Bundle identifier family | `com.stratix.appletv` |

**Packages:**
- `StratixModels` — shared types, IDs, and wire shapes (no local dependencies)
- `DiagnosticsKit` — logging, metrics, and telemetry
- `InputBridge` — controller input capture, queueing, and packet encoding
- `XCloudAPI` — Xbox/xCloud HTTP clients, auth, and token storage
- `StreamingCore` — WebRTC session, SDP/ICE, data channels, runtime contracts
- `VideoRenderingKit` — render strategy and upscale capability selection
- `StratixCore` — controllers, hydration, boot coordination, stream orchestration

**Workspace schemes:** `Stratix-Debug`, `Stratix-ShellUI`, `Stratix-Perf`, `Stratix-Profile`, `Stratix-MetalProfile`, `Stratix-ReleaseRun`, `Stratix-Packages`, `Stratix-Validation`

One compatibility detail: `TokenStore` writes `stratix.*` Keychain entries but migrates older `greenlight.*` tokens forward on read. If you see `greenlight.*` in docs, those are stale.

---

## Start Here

If you are new to the repo, read these four docs first. They are the fastest path from "just cloned" to "ready to contribute":

| Doc | What it gives you |
|---|---|
| [`GETTING_STARTED.md`](GETTING_STARTED.md) | Everything you need to go from a fresh clone to a working build, with each step explained. Includes scheme selection, first launch expectations, and when to use simulator vs. device. |
| [`TESTING.md`](TESTING.md) | The validation model: why it works the way it does, which lane to run for which kind of change, and how CI maps to local wrappers. Read this before your first PR. |
| [`CONFIGURATION.md`](CONFIGURATION.md) | Runtime settings (UserDefaults keys and categories), build flags, Keychain-backed auth storage, and which settings require a restart. |
| [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) | Symptoms, causes, and fixes for the problems you are most likely to hit first — build failures, auth issues, streaming problems, and audio behavior. |

---

## Architecture and Code Organization

These docs explain how the live codebase is structured and why. Read them when you need to understand where a change belongs, or why a boundary exists.

| Doc | What it explains |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | The package graph, app boot sequence, actor-isolation model, and the overall shape of the system. A good first architecture read. |
| [`UI_ARCHITECTURE.md`](UI_ARCHITECTURE.md) | The SwiftUI shell, CloudLibrary composition (the main app surface), route ownership, focus behavior, and view-state layering. |
| [`PACKAGE_GUIDE.md`](PACKAGE_GUIDE.md) | What each of the seven packages owns, what it may depend on, and — critically — where new code should go. The decision guide is directly actionable. |
| [`OBSERVATION.md`](OBSERVATION.md) | How `@Observable` state flows through the app, how typed environment injection works, and the snapshot-based read pattern. |
| [`HYDRATION.md`](HYDRATION.md) | How library data is restored, refreshed, cached, and persisted across app launches. |
| [`RUNTIME_FLOW.md`](RUNTIME_FLOW.md) | End-to-end flows traced across package boundaries — what actually happens from user tap to stream running. Most useful when debugging mid-stream behavior. |
| [`DESIGN_DECISIONS.md`](DESIGN_DECISIONS.md) | Architectural decisions written in ADR format. Explains why major choices were made and what alternatives were considered. |

---

## Development and Contributor Workflow

These docs are the day-to-day operating manual for contributors.

| Doc | What it covers |
|---|---|
| [`CONFIGURATION.md`](CONFIGURATION.md) | UserDefaults keys, diagnostics toggles, compiler flags, token storage, and which settings apply immediately vs. on next stream. |
| [`PREVIEW_STANDARDS.md`](PREVIEW_STANDARDS.md) | How to write Xcode previews that stay deterministic and useful — including the preview harness pattern and mock injection. |
| [`CONCURRENCY_EXCEPTIONS.md`](CONCURRENCY_EXCEPTIONS.md) | The current `@unchecked Sendable` and `nonisolated(unsafe)` allowlist. Before adding a new exception, read this to understand what already exists and why. |
| [`PERFORMANCE.md`](PERFORMANCE.md) | Profiling surfaces, performance test lanes, and the known hot paths in the rendering and input stacks. |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | How to make changes, choose validation lanes, understand the package boundaries, and write a good PR. Start here if you want to contribute. |
| [`../CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) | Community standards. |
| [`GOVERNANCE.md`](GOVERNANCE.md) | The project's collaboration posture and how decisions get made. |
| [`REPO_POLICIES.md`](REPO_POLICIES.md) | The non-negotiable constraints: Swift 6.2, strict concurrency, package direction, WebRTC guards. |

---

## Streaming, WebRTC, and Protocol Docs

These docs matter when you are touching the streaming surface. Read them together — the streaming stack spans several packages and has integration points that are non-obvious without the context these docs provide.

| Doc | What it covers |
|---|---|
| [`STREAMING_ARCHITECTURE.md`](STREAMING_ARCHITECTURE.md) | The full streaming stack from user tap to video frame, including the layered runtime model and package ownership at each layer. |
| [`XCLOUD_PROTOCOL.md`](XCLOUD_PROTOCOL.md) | The xCloud signaling protocol: how session creation works, what the auth tokens are, and how the SDP exchange happens. |
| [`AUDIO_ARCHITECTURE.md`](AUDIO_ARCHITECTURE.md) | tvOS audio session setup, the custom WebRTC patches required for tvOS, and the current stereo audio situation. |
| [`CONTROLLER_INPUT.md`](CONTROLLER_INPUT.md) | The binary input protocol, the 125 Hz input loop, gamepad frame normalization, and the packet wire format. |
| [`CONTROLLER_SUPPORT.md`](CONTROLLER_SUPPORT.md) | Which controllers are supported and how the input bridge handles differences across hardware. |
| [`WEBRTC_GUIDE.md`](WEBRTC_GUIDE.md) | Why the project ships a custom WebRTC build, what was patched, where the integration boundary sits, and what you need to know day-to-day. |
| [`WEBRTC_BUILD_REFERENCE.md`](WEBRTC_BUILD_REFERENCE.md) | How to rebuild the WebRTC binary from source. Most contributors will never need this, but it documents the process for those who do. |

---

## Product, Platform, and Reference

These docs help you understand what Stratix already does and where it is headed.

| Doc | What it covers |
|---|---|
| [`FEATURE_INVENTORY.md`](FEATURE_INVENTORY.md) | The complete feature matrix with honest status markers. The authoritative source for "does X work?" questions. |
| [`GLOSSARY.md`](GLOSSARY.md) | Definitions for every term of art in the codebase, grouped by domain (Auth, Streaming, WebRTC, tvOS, Xbox). Check here when a term is unfamiliar. |
| [`FUTURE_WORK.md`](FUTURE_WORK.md) | Open threads, planned features, and high-impact contribution opportunities. A good place to find a first meaningful contribution. |
| [`XBOX_SOCIAL_API.md`](XBOX_SOCIAL_API.md) | The Xbox social, profile, and presence API integrations — what is implemented and what is partial. |
| [`../SECURITY.md`](../SECURITY.md) | Security policy for reporting vulnerabilities. |

---

## Validation Reference

Two docs should be read together when proving a change:

| Doc | What it covers |
|---|---|
| [`TESTING.md`](TESTING.md) | The validation philosophy, how to pick the right lane, and what each lane proves. The "why" doc. |
| [`XCODE_VALIDATION_MATRIX.md`](XCODE_VALIDATION_MATRIX.md) | The concrete operational inventory: exact schemes, wrapper scripts, CI workflows, test plans, and hardware lane setup. The "what" doc. |

Read both before changing any scripts, workflows, or test-plan wiring.

---

## A Note on Historical Material

The repo still contains some historical documentation:

- `Docs/historical/` — pre-open-source planning and reference materials preserved for context only
- `Docs_to_update/` — documents from earlier repo shapes, kept as reference
- A few older `_old.md` files kept as migration input
- Some planning and modernization docs from when the codebase was being restructured

These are background context only. Do not quote them as current truth without verifying against the live code first. If a historical doc and a current doc disagree, the current doc wins — and if the current doc is wrong, please fix it.
