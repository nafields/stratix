#!/usr/bin/env python3
from __future__ import annotations

import os
from common import changed_files, fail, rel, require_paths

errors: list[str] = []

base_ref = os.environ.get("GITHUB_BASE_REF", "main")
changed = changed_files(base_ref)

required_public_and_truth_docs = [
    rel("README.md"),
    rel("CONTRIBUTING.md"),
    rel("CHANGELOG.md"),
    rel("SUPPORT.md"),
    rel("GOVERNANCE.md"),
    rel("MAINTAINERS.md"),
    rel("Docs", "QUICKSTART.md"),
    rel("Docs", "TESTING.md"),
    rel("Docs", "XCODE_VALIDATION_MATRIX.md"),
    rel("Docs", "KNOWN_ISSUES.md"),
    rel("Docs", "RELEASE_READINESS.md"),
    rel("EXECUTION_PLAN_STATUS.md"),
]
errors.extend(require_paths(required_public_and_truth_docs))

stage_sensitive_prefixes = [
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/",
    "Apps/Stratix/Sources/Stratix/Views/Streaming/",
    "Apps/Stratix/Stratix.xcodeproj/",
    "Packages/StratixCore/Sources/StratixCore/Hydration/",
    "Packages/StratixCore/Sources/StratixCore/LibraryState.swift",
    "Packages/StratixCore/Sources/StratixCore/LibraryAction.swift",
    "Packages/StratixCore/Sources/StratixCore/LibraryReducer.swift",
    "Packages/StratixCore/Sources/StratixCore/App/",
    "Packages/StratixCore/Sources/StratixCore/PostStreamShellRecoveryWorkflow.swift",
    "Packages/StratixCore/Sources/StratixCore/Streaming/",
    "Tools/ci/check_stage7_",
]

release_truth_prefixes = [
    ".github/workflows/",
    "Tools/hooks/",
    "Tools/dev/",
    "Tools/docs/",
    "Tools/test/",
    "Tools/review/",
    "Tools/perf/",
    ".github/ISSUE_TEMPLATE/",
    ".github/pull_request_template.md",
]

required_architecture_docs = {
    "EXECUTION_PLAN_STATUS.md",
    "Docs/XCODE_VALIDATION_MATRIX.md",
    "Docs/ARCHITECTURE_CHANGE_RECORD.md",
}

required_release_truth_docs = {
    "README.md",
    "CONTRIBUTING.md",
    "Docs/QUICKSTART.md",
    "Docs/TESTING.md",
    "Docs/XCODE_VALIDATION_MATRIX.md",
    "Docs/KNOWN_ISSUES.md",
    "Docs/RELEASE_READINESS.md",
}

if any(any(path.startswith(prefix) for prefix in stage_sensitive_prefixes) for path in changed):
    if not any(path in required_architecture_docs for path in changed):
        errors.append(
            "Stage-sensitive architecture files changed but none of "
            "EXECUTION_PLAN_STATUS.md, Docs/XCODE_VALIDATION_MATRIX.md, or "
            "Docs/ARCHITECTURE_CHANGE_RECORD.md changed."
        )

if any(any(path.startswith(prefix) for prefix in release_truth_prefixes) for path in changed):
    if not any(path in required_release_truth_docs for path in changed):
        errors.append(
            "Release-surface automation or workflow files changed but none of "
            "README.md, CONTRIBUTING.md, Docs/QUICKSTART.md, Docs/TESTING.md, "
            "Docs/XCODE_VALIDATION_MATRIX.md, Docs/KNOWN_ISSUES.md, or "
            "Docs/RELEASE_READINESS.md changed."
        )

fail(errors)
print("Docs truth-sync guard passed.")
