# Security

This document explains the current security-sensitive areas in the live `Stratix` repo and how contributors should treat them in a public open-source context.

Stratix is an Xbox cloud gaming client. That means security concerns are not hypothetical: the repo touches authentication flows, token storage, session startup, local settings, and contributor-side test data.

## Main Security Surfaces

The most security-sensitive code currently lives in:

- [`Packages/XCloudAPI/Sources/XCloudAPI/Auth`](Packages/XCloudAPI/Sources/XCloudAPI/Auth)
- [`Packages/XCloudAPI/Sources/XCloudAPI/XCloudAPIClient.swift`](Packages/XCloudAPI/Sources/XCloudAPI/XCloudAPIClient.swift)
- [`Packages/XCloudAPI/Sources/XCloudAPI/StreamSession.swift`](Packages/XCloudAPI/Sources/XCloudAPI/StreamSession.swift)
- [`Packages/StratixCore/Sources/StratixCore/SessionController.swift`](Packages/StratixCore/Sources/StratixCore/SessionController.swift)
- [`Packages/StratixCore/Sources/StratixCore/Streaming`](Packages/StratixCore/Sources/StratixCore/Streaming)

The main security concerns are:

- auth token handling
- token persistence and migration
- private testing data leaking into source or docs
- accidental publication of device-specific or account-specific identifiers

## Token And Auth Handling

The repo uses device-code sign-in and token exchange flows through the Microsoft and Xbox auth chain. Those flows are implemented in `XCloudAPI` and orchestrated by `StratixCore`.

Contributors should treat:

- access tokens
- refresh tokens
- xCloud/xHome session tokens
- web tokens or intermediate auth artifacts

as secrets. They do not belong in:

- markdown docs
- checked-in sample config
- preview fixtures
- tests
- screenshots
- issue reports

## Local Persistence

Token persistence is handled through the token-storage surface in `XCloudAPI`, not through ad hoc plaintext files or “temporary” checked-in fixtures.

If you touch auth persistence:

- prefer migration over destructive breakage when reasonable
- document compatibility implications
- audit for stale keys or naming debt
- avoid logging secret values while debugging

## Public Repo Hygiene

Because this repo is moving toward a first public push, the practical security rule is broader than just crypto and auth:

do not publish anything that ties the repo to a real personal environment.

That includes:

- real gamertags
- real Microsoft account identifiers
- personal Apple TV device names
- local machine-specific paths in published docs
- copied logs with private identifiers intact

Use safe synthetic values instead.

## Reporting A Security Issue

Do not open a normal public feature request or bug report for a live security issue.

Instead:

- contact the maintainer privately through a non-public channel
- include only the minimum information needed to reproduce and assess the issue
- avoid posting active secrets, working exploit details, or reusable attack steps in public

If the project later adds a dedicated private security reporting path, this document should be updated to point to it directly.

## Current Security Posture

What can be said honestly today:

- the repo has a real auth and token-storage surface
- the repo is actively removing personal testing residue and public-unsafe sample data
- the repo does not currently present itself as a formally audited security-hardened product
- contributors should assume careful handling is required, especially in auth, session, preview, and test surfaces

## Review Guidance

Security-sensitive changes should get extra scrutiny when they touch:

- auth flows
- token storage
- session bootstrap
- local persistence of account-linked data
- logs or diagnostics that might expose secrets

Related docs:

- [Docs/REPO_POLICIES.md](Docs/REPO_POLICIES.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [Docs/CONFIGURATION.md](Docs/CONFIGURATION.md)
