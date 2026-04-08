# AGENTS.override.md — .github/

This directory contains GitHub issue templates, PR templates, and CI workflow files. The workflows are the automated guardrails for the project.

**Modernization contract reference:** If a workflow or CI helper change is related to the modernization program, use `Docs/Stratix_Modernization_Contracts.md` as the canonical Floor/Execution contract reference, together with `Docs/Stratix_Modernization_Plan.md`, `Docs/Stratix_Monolith_Breakdown.md`, and `Docs/Stratix_File_Matrix.md`.

---

## CI workflow inventory

| Workflow | Trigger | What it validates |
|----------|---------|-------------------|
| `ci-app-build-and-smoke.yml` | PR, push to main | Full app build + `AppSmokeTests.swift` |
| `ci-packages.yml` | PR, push to main | All SPM package tests via `Stratix-Packages` scheme |
| `ci-pr-fast-guards.yml` | PR only | Fast build + lint guards. Must pass before other CI runs. |
| `ci-shell-ui.yml` | PR, push to main | Shell UI tests via `Stratix-ShellUI` scheme |
| `ci-shell-visual-regression.yml` | PR, scheduled | Visual regression checkpoints. Reads from `Apps/Stratix/Tools/shell-visual-regression/reference/`. |
| `ci-runtime-safety.yml` | PR, push to main | Runtime safety checks (address sanitizer, thread sanitizer) |
| `ci-release-and-validation.yml` | Tagged release | Release build + `Stratix-Validation` scheme |
| `ci-hardware-device.yml` | Scheduled | Hardware device integration tests |
| `ci-shell-state-tests.yml` | PR, push to main | Shell state integration tests |

---

## Rules

1. **Do not modify workflow files without understanding the full impact.** Workflows are the automated contract for what "passing" means.
2. **`ci-pr-fast-guards.yml` must remain fast.** It is the first guard on every PR. Do not add slow steps to it.
3. **Visual regression reads from `Apps/Stratix/Tools/shell-visual-regression/reference/`.** This path is canonical. Do not change it without updating `ci-shell-visual-regression.yml` simultaneously.
4. **`ci-runtime-safety.yml` runs with sanitizers.** Any new code that introduces data races will fail here. Fix the race, do not disable the sanitizer.
5. **`ci-hardware-device.yml` runs on physical Apple TV hardware.** If it fails with a "device not found" error, that is an infrastructure issue, not a code issue. Do not "fix" hardware CI failures by removing tests.

---

## PR template

`.github/PULL_REQUEST_TEMPLATE.md` defines the expected PR description format. Fill it out for every PR. The CI system does not enforce it, but reviewers expect it.

---

## Issue templates

- `bug_report.yml` — for filing bugs
- `feature_request.yml` — for proposing features
- `config.yml` — template picker configuration

---

## What CI does not currently validate (gaps)

The current gaps are mostly policy and hygiene checks rather than open modernization blockers.

Current examples:
1. Reference-image location is still a convention rather than a hard CI guard. `Apps/Stratix/Tools/shell-visual-regression/reference/` remains the canonical path.
2. New pure-Swift tests using `import Testing` is still a reviewer-enforced rule, not a CI-enforced one.
3. Some repo-shape invariants from the modernization wave are still protected by documentation and review more than by grep-based CI checks.

**Reasonable future additions to `ci-pr-fast-guards.yml`:**
- a grep-based guard that fails on reintroduction of deleted passthrough seams such as `CloudLibraryActionFactory`
- a grep-based guard that fails on reintroduction of deleted micro-shard files that were intentionally merged away
- a small check that warns when new reference-image directories appear outside `Apps/Stratix/Tools/shell-visual-regression/reference/`
