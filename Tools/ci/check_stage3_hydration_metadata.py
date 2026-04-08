#!/usr/bin/env python3
from __future__ import annotations

from common import assert_contains, rel, require_paths, fail

errors: list[str] = []

metadata_path = rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationMetadata.swift")
tests_path = rel("Packages/StratixCore/Tests/StratixCoreTests/LibraryHydrationMetadataTests.swift")
persistence_tests_path = rel("Packages/StratixCore/Tests/StratixCoreTests/LibraryHydrationPersistenceMetadataTests.swift")
planner_tests_path = rel("Packages/StratixCore/Tests/StratixCoreTests/LibraryHydrationMetadataPlannerTests.swift")

errors.extend(
    require_paths(
        [
            metadata_path,
            tests_path,
            persistence_tests_path,
            planner_tests_path,
        ]
    )
)

errors.extend(
    assert_contains(
        metadata_path,
        [
            "snapshotID: UUID",
            "generatedAt: Date",
            "cacheVersion: Int",
            "market: String",
            "language: String",
            "refreshSource: String",
            "hydrationGeneration: UInt64",
            "homeReady: Bool",
            "completenessBySectionID: [String: Bool]",
            "deferredStages: [LibraryHydrationStage]",
            "trigger: String",
            'trigger: "legacy_decode"',
        ],
    )
)

errors.extend(
    assert_contains(
        tests_path,
        [
            "snapshotID: UUID()",
            "refreshSource:",
            "homeReady:",
        ],
    )
)

errors.extend(
    assert_contains(
        persistence_tests_path,
        [
            "decoded.metadata.refreshSource",
            "decoded.metadata.cacheVersion",
            "decoded.metadata.homeReady",
        ],
    )
)

errors.extend(
    assert_contains(
        planner_tests_path,
        [
            "LibraryHydrationMetadata(",
            "cacheVersion: LibraryHydrationCacheSchema.currentCacheVersion",
            "homeReady: true",
        ],
    )
)

fail(errors)
print("Stage 3 hydration metadata guard passed.")
