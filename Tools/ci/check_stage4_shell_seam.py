#!/usr/bin/env python3
from __future__ import annotations

from common import rel, fail

errors: list[str] = []

shell_files = [
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryView.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Shell/CloudLibraryShellHost.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryShellPresentationBuilder.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryBrowsePresentationBuilder.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryUtilityPresentationBuilder.swift"),
]

forbidden = [
    "libraryController.sections",
    "libraryController.itemsByTitleID",
    "libraryController.itemsByProductID",
    "libraryController.productDetails",
    "libraryController.homeMerchandising",
    "libraryController.discoveryEntries",
    "libraryController.isLoading",
    "libraryController.lastError",
    "libraryController.needsReauth",
    "libraryController.lastHydratedAt",
    "libraryController.cacheSavedAt",
    "libraryController.hasRecoveredLiveHomeMerchandisingThisSession",
    "libraryController.hasCompletedInitialHomeMerchandising",
]

for path in shell_files:
    if not path.exists():
        continue

    text = path.read_text(encoding="utf-8")
    for needle in forbidden:
        if needle in text:
            errors.append(f"{path}: forbidden direct runtime-truth read: {needle}")

fail(errors)
print("Stage 4 shell seam guard passed.")
