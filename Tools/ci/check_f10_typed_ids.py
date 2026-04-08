#!/usr/bin/env python3
from __future__ import annotations

from common import rel, fail

errors: list[str] = []

files = [
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryRouteState.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryFocusState.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryBrowseScreenPresentation.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryBrowseRouteActions.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryDetailRouteActions.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryActionFactory.swift"),
]

forbidden = [
    "detailPath: [String]",
    "focusedTileIDsByRoute: [CloudLibraryBrowseRoute: String]",
    "settledHomeHeroTileID: String?",
    "settledLibraryHeroTileID: String?",
    "homeFocusTileID: (String?) -> Void",
    "libraryFocusTileID: (String?) -> Void",
    "searchFocusTileID: (String?) -> Void",
    "launchStream: (String, String) -> Void",
    "preferredHomeTileID: String?",
    "preferredLibraryTileID: String?",
    "preferredSearchTileID: String?",
    "[String: CloudLibraryHomeScreen.TileLookupEntry]",
    "[String: MediaTileViewState]",
]

for path in files:
    if not path.exists():
        continue

    text = path.read_text(encoding="utf-8")
    for needle in forbidden:
        if needle in text:
            errors.append(f"{path}: forbidden raw-string shell identity: {needle}")

fail(errors)
print("Stage 4 typed ID guard passed.")
