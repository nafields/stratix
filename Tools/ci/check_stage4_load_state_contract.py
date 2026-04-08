#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, assert_contains, assert_not_contains, fail

errors: list[str] = []

required_paths = [
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryLoadState.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryLoadStateBuilder.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryView.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryPresentationStore.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneModel.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneStatusState.swift"),
]
errors.extend(require_paths(required_paths))

browse_presentation = rel(
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/CloudLibraryBrowsePresentation.swift"
)
cloud_library_view = rel(
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryView.swift"
)
presentation_store = rel(
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryPresentationStore.swift"
)
scene_model = rel(
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneModel.swift"
)
scene_model_status_projection = rel(
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneStatusState.swift"
)

errors.extend(assert_contains(browse_presentation, ["let loadState: CloudLibraryLoadState"]))
errors.extend(
    assert_not_contains(
        browse_presentation,
        [
            "shouldShowRouteLoadingPanel",
            "cachedDataBannerText",
            "let lastError:",
            "let needsReauth:",
            "let isLoading:",
            "let sectionsAreEmpty:",
        ],
    )
)
errors.extend(assert_contains(cloud_library_view, ["loadState: loadState"]))
errors.extend(
    assert_not_contains(
        cloud_library_view,
        [
            "isLoading: stateAdapter.isLoading",
            "lastError: stateAdapter.lastError",
        ],
    )
)
errors.extend(assert_contains(presentation_store, ["loadState: loadState"]))
errors.extend(
    assert_not_contains(
        presentation_store,
        [
            "isLoading: stateAdapter.isLoading",
            "lastError: stateAdapter.lastError",
        ],
    )
)
errors.extend(
    assert_contains(
        scene_model_status_projection,
        [
            "\"loadState=\\(loadState.diagnosticsValue)\"",
            "static func resolve(",
        ],
    )
)
errors.extend(
    assert_contains(
        scene_model,
        [
            "func reconcileInitialLibraryLoadState(loadState: CloudLibraryLoadState)",
        ],
    )
)
errors.extend(
    assert_not_contains(
        scene_model,
        [
            "var routeLoadingPanelVisible",
            "var cachedDataBannerText",
            "\"loading=\\(",
            "\"error=\\(",
        ],
    )
)

fail(errors)
print("Stage 4 load-state contract guard passed.")
