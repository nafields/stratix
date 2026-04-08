#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, assert_not_contains, fail

errors: list[str] = []

required_paths = [
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationOrchestrator.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationRequest.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationCommitContext.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationLiveFetchResult.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationCommitResult.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationOrchestrationResult.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationPersistenceIntent.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationStartupRestoreWorkflow.swift"),
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationPostStreamDeltaWorkflow.swift"),
]
errors.extend(require_paths(required_paths))

legacy_monolith = rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydration.swift")
if legacy_monolith.exists():
    errors.append(f"{legacy_monolith}: legacy hydration monolith must not exist.")

library_controller = rel("Packages/StratixCore/Sources/StratixCore/LibraryController.swift")
errors.extend(
    assert_not_contains(
        library_controller,
        [
            "func applyStartupRestoreResult(",
            "func applyHydrationRecoveryState(",
            "func applyHydrationPublishedState(",
            "func applyProductDetailsState(",
        ],
    )
)

fail(errors)
print("Stage 2 hydration boundary guard passed.")
