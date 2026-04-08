# Governance

This document describes how source of truth, contributor-facing rules, and project decisions currently work in the live `Stratix` repo.

It is intentionally lightweight. Stratix does not currently have a heavy formal governance process, steering committee, or RFC program. What it does have is a set of practical documents, code boundaries, and validation surfaces that define how changes should be made.

## Source Of Truth

When two sources disagree, use this order:

1. live code, project files, package manifests, tests, and scripts
2. current docs under `Docs/`
3. stale or historical material under `Docs_to_update/`

If the docs disagree with the code, the docs need to be fixed.

## Canonical Working Contracts

These are the main repo-level contracts:

- [../AGENTS.md](../AGENTS.md)
- [REPO_POLICIES.md](REPO_POLICIES.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [PACKAGE_GUIDE.md](PACKAGE_GUIDE.md)
- [TESTING.md](TESTING.md)

Some modernization and audit artifacts still exist in `Docs/` because they shaped the current tree. They may still be useful for historical context, but they are not the first source a new contributor should trust.

## What Governance Means In Practice

In the current project, governance mostly means:

- repo naming should stay coherent
- package ownership should remain intentional
- contributor-facing docs should stay current
- validation lanes should reflect the real repo shape
- unsafe exceptions should stay narrowly bounded and documented
- private data should not leak into the public repo

That is enough structure to keep a public open-source codebase understandable without turning every change into a process exercise.

## Naming And Path Rules

Current naming rules:

- use `Stratix` for the repo, app target, schemes, docs, and package-facing contributor language
- keep bundle and signing identifiers aligned with the current `com.stratix.appletv` family
- avoid reintroducing pre-rename app names in new docs or new code

Historical names may still appear in old docs or explanatory notes, but they should be clearly marked as historical rather than current.

## Documentation Rule

Current docs live under `Docs/`.

`Docs_to_update/` is audit input and historical reference material. It is not the published source of truth. Useful sections from that folder should be merged forward into `Docs/` only after they are checked against the live repo.

## Change Priority Rule

When deciding what to fix first, favor:

1. correctness
2. public-safety issues like leaked private data
3. build and validation health
4. contributor comprehension
5. internal policy perfection

This matters because Stratix is moving toward a first public open-source state. Internal guardrails are useful, but they should not outrank the basics of a clean, understandable, safe public repo.

## Decision Style

Good decisions in this repo are usually:

- specific
- reversible where possible
- grounded in code and validation
- documented when they change contributor expectations

If a decision changes where code belongs, how validation works, or how new contributors should enter the repo, update the matching docs in the same change.
