# Contributing to Stratix

Welcome. This guide explains how to contribute to the Stratix codebase without having to guess about repo structure, validation expectations, or code standards. It is written to be read, not skimmed — every rule here has a reason, and understanding the reason is more valuable than memorizing the rule.

Stratix is an open-source tvOS project with one app target, a workspace-first development model, and seven local Swift packages that enforce real ownership boundaries. The codebase is deliberately opinionated about concurrency, validation, and package direction. Those opinions exist because they protect contributors from entire categories of subtle bugs. This guide explains what they are and why they matter.

---

## First: Read the Architecture Docs

Before making a code change, it is worth spending 20 minutes understanding where the code lives and why. Two docs cover this:

- [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md) — the overall package graph, boot sequence, and actor-isolation model.
- [`Docs/PACKAGE_GUIDE.md`](Docs/PACKAGE_GUIDE.md) — what each of the seven packages owns and, critically, where new code should go.

If you skip these and put code in the wrong layer, the symptom is usually not an error — it is a test that can no longer run independently, or a dependency that cannot be built without the app target. The architecture docs exist to prevent exactly that.

---

## First Principles

These are the load-bearing rules. Each one has a reason.

**Use the workspace, not the project file.**
Always open `Stratix.xcworkspace`, not `Apps/Stratix/Stratix.xcodeproj`. The workspace is what wires the app and all seven local packages together. Opening the project file directly causes missing-dependency errors and gives you the wrong scheme set. Every validation wrapper, CI pipeline, and contributor workflow assumes the workspace as the entry point.

**Choose the validation lane that actually proves what you changed.**
There is a temptation to either run nothing (fast but wrong) or run everything (slow but wasteful). The right answer is the narrowest lane that honestly matches your change. If you changed a model in `StratixModels`, run the package sweep. If you changed the shell routing, run the shell UI checks. This is documented in [`Docs/TESTING.md`](Docs/TESTING.md) — it is worth reading before your first PR.

**Keep docs aligned with the live tree.**
When you change something that affects how contributors build, test, or navigate the repo — validation commands, package ownership, scheme names, path names — update the docs in the same change set. Public repos accumulate trust through accuracy. A doc that describes a path that no longer exists is actively harmful to the next person who reads it.

**Preserve package boundaries.**
The package structure is load-bearing. If you move a streaming runtime concern into the app target because it was convenient, the package tests can no longer prove that concern independently. If you add an HTTP client to `StratixCore` instead of `XCloudAPI`, you have created a hidden dependency that can only be tested through the whole app. The boundary is the test surface, not just a style preference. See [`Docs/PACKAGE_GUIDE.md`](Docs/PACKAGE_GUIDE.md) for the full decision guide.

**Keep UI-facing state on explicit `@MainActor` boundaries.**
Swift 6.2 with strict concurrency checking set to `complete` makes the compiler enforce actor isolation at build time. This means: if your code compiles, you have a strong guarantee it is not racing across actor boundaries at runtime. Do not broaden `@MainActor` ownership to silence a compiler error you do not understand — figure out what the error is telling you. The error is usually right.

**Do not commit credentials, tokens, or personal identifiers.**
Stratix is a public repository. Do not commit real auth tokens, personal device IDs, real Xbox account identifiers, or any sample data that contains private information. If you find old local-only data in previews, tests, or docs, remove or replace it with synthetic safe data.

---

## Before You Make a Change: Read the Right Docs

The right docs depend on what surface you are changing. Here is the map:

| If you are working on... | Read these |
|---|---|
| General orientation | [README.md](README.md), [Docs/README.md](Docs/README.md), [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) |
| Package code | [Docs/PACKAGE_GUIDE.md](Docs/PACKAGE_GUIDE.md) |
| App shell, routing, focus, or SwiftUI state | [Docs/UI_ARCHITECTURE.md](Docs/UI_ARCHITECTURE.md), [Docs/OBSERVATION.md](Docs/OBSERVATION.md) |
| Library data or persistence | [Docs/HYDRATION.md](Docs/HYDRATION.md) |
| Streaming, WebRTC, or rendering | [Docs/STREAMING_ARCHITECTURE.md](Docs/STREAMING_ARCHITECTURE.md), [Docs/WEBRTC_GUIDE.md](Docs/WEBRTC_GUIDE.md), [Docs/RUNTIME_FLOW.md](Docs/RUNTIME_FLOW.md) |
| Validation scripts or CI | [Docs/TESTING.md](Docs/TESTING.md), [Docs/XCODE_VALIDATION_MATRIX.md](Docs/XCODE_VALIDATION_MATRIX.md) |
| Settings or configuration | [Docs/CONFIGURATION.md](Docs/CONFIGURATION.md), [Docs/GETTING_STARTED.md](Docs/GETTING_STARTED.md) |
| Repo rules or non-negotiables | [Docs/REPO_POLICIES.md](Docs/REPO_POLICIES.md) |

When current docs and older historical material in `Docs_to_update/` disagree, the live repo wins.

---

## Repo Shape

Stratix is a workspace-based monorepo with:

- one tvOS app target under `Apps/Stratix`
- one Xcode workspace: `Stratix.xcworkspace` (always the entry point)
- seven local Swift packages under `Packages/`
- a vendored WebRTC xcframework under `ThirdParty/WebRTC/`
- local tooling and CI wrappers under `Tools/`

The package dependency direction is intentional and must be preserved:

```
StratixModels  ← no local dependencies (shared leaf)
    ↓
DiagnosticsKit, InputBridge, XCloudAPI  ← depend on StratixModels
    ↓
StreamingCore  ← depends on the three above
    ↓
VideoRenderingKit, StratixCore  ← depend on StreamingCore
    ↓
Apps/Stratix  ← depends on everything, but nothing depends on it
```

If you are proposing a change that crosses those seams — moving code between layers, adding a new dependency direction — explain why in the PR and update the docs that describe the boundary.

---

## Choosing the Right Kind of Change

Understanding what type of change you are making determines what validation is required and which docs you may need to update.

### Package-local logic

*Examples:* fixing a decoder, updating a shared model, changing controller logic inside one package, updating a diagnostics helper.

What to do:
- run the affected package tests
- run the full package sweep if the change touches shared types or interfaces
- update docs if contributor-facing behavior changed

### App shell or UI

*Examples:* shell composition changes, route or focus behavior, browse or detail presentation, app-owned state publication.

What to do:
- debug build to confirm the app builds correctly
- run the shell UI lane if route, focus, overlay, or back-command behavior changed
- update docs if the public architecture or contributor workflow changed

### Runtime, WebRTC, or rendering

*Examples:* `WebRTCClientImpl`, renderer attach/detach, stream startup/teardown/recovery, runtime boundary ownership.

What to do:
- run affected package tests
- run the runtime-safety lane
- run the shell lane if stream return-to-shell behavior changed
- provide device-specific evidence if simulator proof is insufficient

### Architecture or repo-shape change

*Examples:* changing package boundaries, changing validation wrapper behavior, moving ownership between app and package surfaces, changing canonical paths or documentation entry points.

What to do:
- explain explicitly what changed and why
- update the docs that describe the boundary you changed
- revalidate the wrappers or guards affected by the change

---

## Local Environment

Stratix is developed with:

- Xcode 26+
- Swift 6.2
- tvOS deployment target `26.0`
- strict concurrency checking set to `complete`

Open the workspace:

```bash
open Stratix.xcworkspace
```

Install the repo hooks once per clone:

```bash
bash Tools/hooks/install_git_hooks.sh
```

The hooks run pre-commit and pre-push checks automatically. They are not slow — they run a targeted check, not a full validation sweep.

---

## Validation Wrapper Reference

Use the wrapper scripts instead of hand-writing `xcodebuild` commands. The wrappers encode the correct derived-data paths, destination strings, `-only-testing` slices, and environment variable requirements.

| Wrapper | When to use it |
|---|---|
| `bash Tools/dev/run_package_sweep.sh` | After any package-level change |
| `bash Tools/dev/run_debug_build.sh` | After app-level changes, as a sanity check |
| `bash Tools/dev/run_app_smoke.sh` | After app composition or startup changes |
| `bash Tools/dev/run_shell_ui_checks.sh` | After shell, route, focus, or overlay changes |
| `bash Tools/test/run_shell_regression_checks.sh` | After visual shell changes (requires `ffmpeg`) |
| `bash Tools/dev/run_runtime_safety.sh` | After streaming, WebRTC, renderer, or audio changes |
| `bash Tools/dev/run_validation_build.sh` | Before a broad closeout — the "prove everything" lane |
| `bash Tools/dev/run_release_build.sh` | Release-shape build proof |

Pre-commit and pre-push:

```bash
bash Tools/dev/run_pre_commit_checks.sh
bash Tools/dev/run_pre_push_checks.sh
```

For the full validation decision guide, see [`Docs/TESTING.md`](Docs/TESTING.md).

---

## Code Standards

**Swift version and concurrency:** Keep `SWIFT_VERSION = 6.2` and strict concurrency at `complete`. These are not version preferences — they are safety properties. The compiler is your collaborator here, not your adversary.

**Deployment target:** Keep the deployment target at `tvOS 26.0`. No backwards-compatibility shims, no `#available` guards for things that are supposed to always be available.

**WebRTC guards:** Preserve `#if WEBRTC_AVAILABLE` guards around all concrete WebRTC integration. This is what allows the streaming packages to compile and test without the framework binary.

**Test frameworks:** Prefer Swift Testing for new pure-Swift logic in packages. Keep XCUI work in XCTest — that framework is not going away. The mixed state across the repo is intentional, not a mistake to be cleaned up.

**Actor isolation:** Keep app-owned UI state explicit and actor-correct. Do not broaden `@MainActor` ownership to silence a compiler error. Do not add `@unchecked Sendable` or `nonisolated(unsafe)` without understanding and documenting why the standard approach cannot work. The current exception list lives in [`Docs/CONCURRENCY_EXCEPTIONS.md`](Docs/CONCURRENCY_EXCEPTIONS.md).

---

## Documentation Standards

If your change alters contributor workflow, validation commands, package ownership, or any runtime behavior the docs describe — update the docs in the same PR.

The test for whether docs need updating: could a new contributor read the existing docs and be misled about what you just changed? If yes, update the docs.

---

## What Makes a Good Pull Request

A good PR makes it easy for the reviewer to understand four things:

1. **What changed** — a clear description of the code change itself
2. **Why it changed** — the motivation: bug fix, new capability, cleanup, response to a user problem
3. **What proves it** — which validation lanes you ran and what they showed
4. **What risk remains** — any known rough edges, caveats, or follow-up work the change leaves behind

When a change is broad, summarize by surface area. A list of files is not a summary.

---

## If You Are Not Sure

It is fine to not know where to start. Here is what to do:

1. Check the docs index at [`Docs/README.md`](Docs/README.md) — it maps every doc to the task it serves.
2. Open a draft PR and explain what you are trying to do. Drafts are good for getting direction before investing a lot of time.
3. Prefer the smaller, better-scoped change. A small change that works is more valuable than a large change that is hard to review.
4. If you ran into something confusing or hard to understand, document what you learned. Improving the docs for the next person is a real contribution.

The goal is an open-source project that is genuinely welcoming to contributors — where the architecture, docs, and validation model lower the barrier to making real improvements rather than raising it.
