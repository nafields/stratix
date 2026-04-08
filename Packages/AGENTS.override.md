# AGENTS.override.md — Packages/

This directory contains seven Swift Package Manager packages. Each package has its own `AGENTS.override.md`. This file establishes the rules that apply across all packages.

**Modernization contract reference:** For package work governed by the modernization program, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with the modernization plan, monolith breakdown, and file matrix.

**Skill policy reference:** Use the root AGENTS skill policy together with `Docs/Stratix_Skill_Policy.md`. For package work, default to `[$ios-skills:ios-skills-router](/Users/nicholas/.ios-skills/skills/_router/SKILL.md)`, `[$ios-skills:swift-concurrency-pro](/Users/nicholas/.ios-skills/skills/twostraws--swift-concurrency-pro/SKILL.md)`, and `[$ios-skills:swift-coding-guideline](/Users/nicholas/.ios-skills/skills/martinlasek--swift-coding-guideline/SKILL.md)` before editing package code.

---

## Package inventory

| Package | Role | Key dependency |
|---------|------|----------------|
| `StratixModels` | Shared model types | None (leaf package) |
| `XCloudAPI` | Network layer (xCloud API) | StratixModels |
| `StratixCore` | App lifecycle, auth, controllers | StratixModels, XCloudAPI, StreamingCore |
| `StreamingCore` | WebRTC session protocol, channels | StratixModels |
| `VideoRenderingKit` | Upscale strategy resolution | None |
| `InputBridge` | Gamepad input, input queue | None |
| `DiagnosticsKit` | Metrics pipeline, logging | None |

---

## Dependency direction rules

The app target depends on packages. Packages do not depend on the app target.

Package-to-package dependencies must follow data flow:
- `StratixModels` has no package dependencies
- `XCloudAPI` may depend on `StratixModels`
- `StreamingCore` may depend on `StratixModels`
- `StratixCore` may depend on `StratixModels`, `XCloudAPI`, `StreamingCore`
- `VideoRenderingKit`, `InputBridge`, `DiagnosticsKit` are standalone — they do not depend on each other or on the domain packages unless there is an explicit, documented reason

Do not introduce circular package dependencies.

---

## Adding code to packages vs the app target

A type belongs in a package if:
- It is used by more than one of: the app target, another package, or a test target
- It has no UIKit or SwiftUI dependency (UIKit/SwiftUI code belongs in the app target)
- It represents a domain model, service, or infrastructure concern

A type belongs in the app target if:
- It is a SwiftUI view or UIKit view controller
- It is a view model or presentation state object
- It is specific to one feature and has no cross-package consumers

---

## Testing rules for packages

- Each package has a `Tests/` directory
- New code in a package must have corresponding package-level tests
- Package tests run via the `Stratix-Packages` scheme
- Package tests are covered by `ci-packages.yml` in CI

---

## Concurrency rules for packages

- Packages are compiled with Swift 6.2 strict concurrency
- Package types that cross the MainActor boundary must be `Sendable`
- Service types that hold shared mutable state must be actors
- Do not use `@MainActor` in packages unless the type is genuinely a UI coordinator (should be rare in packages)

---

## Package Skill Routing

Use these package-specific skills when the domain matches:

- `[$ios-skills:swift-testing-expert](/Users/nicholas/.ios-skills/skills/avdlee--swift-testing-expert/SKILL.md)` for new package tests and XCTest to Swift Testing migrations
- `[$ios-skills:swiftdata](/Users/nicholas/.ios-skills/skills/dpearson2699--swiftdata/SKILL.md)` for StratixCore hydration persistence and `SwiftDataLibraryRepository`
- `[$ios-skills:ios-networking](/Users/nicholas/.ios-skills/skills/dpearson2699--ios-networking/SKILL.md)` and `[$ios-skills:swift-codable](/Users/nicholas/.ios-skills/skills/dpearson2699--swift-codable/SKILL.md)` for `Packages/XCloudAPI/`
- `[$ios-skills:swift-security-expert](/Users/nicholas/.ios-skills/skills/ivan-magda--swift-security-expert/SKILL.md)` for auth/token storage and security boundaries
- `[$ios-skills:debugging-instruments](/Users/nicholas/.ios-skills/skills/dpearson2699--debugging-instruments/SKILL.md)` for performance-sensitive runtime/package investigations
- `[$ios-skills:spm-build-analysis](/Users/nicholas/.ios-skills/skills/avdlee--spm-build-analysis/SKILL.md)` when package graph, compile cost, or SPM overhead is the concern
