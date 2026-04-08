# Repo Policies

This document summarizes the current operating rules of the live `Stratix` repo.

It is not a replacement for [../AGENTS.md](../AGENTS.md), but it is the contributor-facing version of the rules that most directly affect public development work.

## Baseline Technical Constraints

These are current repo constraints, not suggestions:

- Swift version: `6.2`
- strict concurrency checking: `complete`
- deployment target: `tvOS 26.0`
- workspace entry point: `Stratix.xcworkspace`

Do not silently weaken those constraints just to make a local change easier.

## WebRTC Rule

Concrete WebRTC integration must remain behind `#if WEBRTC_AVAILABLE` boundaries.

That rule exists because the repo supports:

- preview and UI development flows that do not need the full WebRTC runtime
- package test lanes that should not depend on the concrete bridge
- explicit separation between app-owned bridge code and package-owned runtime contracts

## Package Boundary Rule

Keep package responsibilities clear:

- `StratixModels`: shared models and identifiers
- `DiagnosticsKit`: diagnostics, logging, telemetry
- `InputBridge`: controller input and packet shaping
- `XCloudAPI`: auth and network clients
- `StreamingCore`: session/runtime/channel flow
- `VideoRenderingKit`: rendering policy and capability logic
- `StratixCore`: app lifecycle, controllers, hydration, shell orchestration

The app target depends on packages. Packages do not depend on the app target.

## Testing Rule

Use the narrowest validation lane that proves the changed surface.

General expectations:

- package logic: package sweep
- shell and focus changes: shell UI lane
- runtime and WebRTC changes: runtime safety lane
- broad closeout: validation build

For new pure-Swift logic in targets that are already migrating, prefer Swift Testing. XCUI remains XCTest.

## Concurrency Rule

Current repo posture:

- UI-facing state may be `@MainActor`
- shared mutable service state should prefer actors
- heavy work should stay off the main actor unless it is inherently UI-bound

Do not add:

- `nonisolated(unsafe)` in production code
- broad `@unchecked Sendable` usage

without a narrow, documented reason.

See [CONCURRENCY_EXCEPTIONS.md](CONCURRENCY_EXCEPTIONS.md) for the current exception boundary.

## Documentation Rule

Contributor-facing docs should match the live repo.

That means:

- update docs when paths, commands, or contributor workflows change
- prefer `Docs/` over `Docs_to_update/`
- merge truthful old material forward instead of duplicating contradictory explanations
- avoid leaving historical naming or stale paths in public docs

## Sensitive Data Rule

Do not commit:

- tokens
- personal credentials
- personal device identifiers
- private account information
- real preview/test sample data that exposes a real user or environment

If local-only data is found in docs, tests, previews, or scripts, replace it with safe synthetic data.

## Validation Is A Means, Not The Product

Internal architecture guards and hygiene checks are useful, but they are not the only measure of repo health.

For the current public-open-source push, higher priorities are:

- safe public content
- accurate docs
- working builds
- truthful validation wrappers
- understandable contributor workflow

That ordering should guide cleanup decisions.
