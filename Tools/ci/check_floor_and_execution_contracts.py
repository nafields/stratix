#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import rel, read_text, line_count, fail, repo_root

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_TEST_PATH_MARKERS = ("Tests/", "UITests/", "PerformanceTests/", "PerformanceUITests/")


def _is_test_file(path: Path) -> bool:
    posix = path.as_posix()
    return any(marker in posix for marker in _TEST_PATH_MARKERS)


def _iter_production_swift(root: Path) -> list[Path]:
    return [p for p in sorted(root.rglob("*.swift")) if not _is_test_file(p)]


def _iter_all_swift(root: Path) -> list[Path]:
    return sorted(root.rglob("*.swift"))


# Top-level type declaration pattern (not extensions).
_TOP_LEVEL_TYPE_RE = re.compile(
    r"^(?:public |private |internal |fileprivate |open |package )*"
    r"(?:final |@MainActor |nonisolated )*"
    r"(struct|class|enum|protocol|actor)\s+(\w+)"
)

# Extension declaration pattern.
_EXTENSION_RE = re.compile(r"^\s*(?:public |private |internal |fileprivate |open |package )*extension\s+")


def _top_level_type_names(path: Path) -> list[str]:
    """Return distinct non-extension top-level type names declared in the file."""
    text = read_text(path)
    depth = 0
    names: list[str] = []
    in_line_comment = False
    in_block_comment = False
    in_string = False

    for raw_line in text.splitlines():
        line = raw_line.strip()

        # Very rough skip of block comments and line comments.
        # (good enough for a linter approximation)
        if in_block_comment:
            if "*/" in line:
                in_block_comment = False
            continue
        if line.startswith("//"):
            continue
        if "/*" in line and "*/" not in line:
            in_block_comment = True
            continue

        if depth == 0 and not _EXTENSION_RE.match(raw_line):
            m = _TOP_LEVEL_TYPE_RE.match(line)
            if m:
                type_name = m.group(2)
                if type_name not in names:
                    names.append(type_name)

        depth += line.count("{") - line.count("}")
        if depth < 0:
            depth = 0

    return names


# ---------------------------------------------------------------------------
# F1 — No mixed roots
# ---------------------------------------------------------------------------

_F1_KNOWN: dict[str, str] = {
    "Apps/Stratix/Sources/Stratix/Shared/Theme/StratixTheme.swift": "FB-2",
    "Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/RendererAttachmentCoordinator.swift": "FB-1",
}


def check_f1() -> list[str]:
    """F1 — No mixed roots: production files must not declare 2+ distinct top-level types."""
    errors: list[str] = []
    app_sources = rel("Apps/Stratix/Sources")
    for path in _iter_production_swift(app_sources):
        names = _top_level_type_names(path)
        if len(names) >= 2:
            relative = path.relative_to(repo_root()).as_posix()
            pending = _F1_KNOWN.get(relative, "")
            pending_tag = f" (pending: {pending})" if pending else ""
            errors.append(
                f"[F1] Mixed root — {len(names)} top-level types in {path.name}{pending_tag}\n"
                f"     {relative}\n"
                f"     Types found: {', '.join(names)}"
            )
    return errors


# ---------------------------------------------------------------------------
# F2 — No micro-shards
# ---------------------------------------------------------------------------

_F2_KNOWN: set[str] = {
    "MetalVideoRenderer+MainThreadDraw.swift",
    "MetalVideoRenderer+Telemetry.swift",
    "MetalVideoRenderer+Sizing.swift",
    "SampleBufferDisplayRenderer+Telemetry.swift",
    "LibraryController+PostLoadWarmup.swift",
    "XboxComProductDetailsClient+FetchPipeline.swift",
    "XboxComProductDetailsClient+RequestConstruction.swift",
}

_EXTENSION_DECL_RE = re.compile(r"^\s*(?:public |private |internal |fileprivate |open |package )*extension\s+\w+")


def _has_extension_decl(path: Path) -> bool:
    text = read_text(path)
    return bool(_EXTENSION_DECL_RE.search(text, re.MULTILINE))


def check_f2() -> list[str]:
    """F2 — No micro-shards: tiny extension-only files with < 40 lines."""
    errors: list[str] = []
    app_sources = rel("Apps/Stratix/Sources")
    pkg_sources = rel("Packages")
    roots = [app_sources, pkg_sources]

    for root in roots:
        if not root.exists():
            continue
        for path in _iter_production_swift(root):
            lc = line_count(path)
            if lc >= 40:
                continue
            text = read_text(path)
            # Must have at least one extension declaration
            if not _EXTENSION_DECL_RE.search(text):
                continue
            # Must NOT define any non-extension top-level type
            if _top_level_type_names(path):
                continue
            relative = path.relative_to(repo_root()).as_posix()
            known_tag = " (known pending)" if path.name in _F2_KNOWN else ""
            errors.append(
                f"[F2] Micro-shard — {path.name} has {lc} lines and is extension-only{known_tag}\n"
                f"     {relative}"
            )
    return errors


# ---------------------------------------------------------------------------
# F3 — Naming must communicate intent
# ---------------------------------------------------------------------------

def check_f3() -> list[str]:
    """F3 — Naming must communicate intent."""
    errors: list[str] = []

    # Pending rename: RouteSwitchPerformanceTests.swift → RenderLadderRungFallbackPerformanceTests.swift
    wrong_name = rel(
        "Apps/Stratix/StratixPerformanceTests/RouteSwitchPerformanceTests.swift"
    )
    if wrong_name.exists():
        errors.append(
            f"[F3] Misleading name — RouteSwitchPerformanceTests.swift should be renamed to "
            f"RenderLadderRungFallbackPerformanceTests.swift (pending rename)\n"
            f"     {wrong_name.relative_to(repo_root()).as_posix()}"
        )

    # CloudLibraryStateAdapter — check it still uses "StateAdapter" in its type definition
    state_adapter = rel(
        "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/"
        "CloudLibraryStateAdapter.swift"
    )
    if state_adapter.exists():
        text = read_text(state_adapter)
        if "StateAdapter" in text:
            errors.append(
                f"[F3] Truthful rename pending — CloudLibraryStateAdapter.swift still defines a "
                f"'StateAdapter' type; rename to reflect actual role\n"
                f"     {state_adapter.relative_to(repo_root()).as_posix()}"
            )

    return errors


# ---------------------------------------------------------------------------
# F4 — Fake seams dissolved at action routing
# ---------------------------------------------------------------------------

def check_f4() -> list[str]:
    """F4 — Fake seams dissolved at action routing: CloudLibraryActionFactory must be dissolved."""
    errors: list[str] = []
    factory = rel(
        "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/"
        "CloudLibraryActionFactory.swift"
    )
    if factory.exists():
        relative = factory.relative_to(repo_root()).as_posix()
        text = read_text(factory)
        note = ""
        if "func make" in text:
            note = " (contains factory 'make' methods forwarding to ShellHost — dissolve per FB-6)"
        errors.append(
            f"[F4] Fake seam — CloudLibraryActionFactory.swift must be dissolved (FB-6){note}\n"
            f"     {relative}"
        )
    return errors


# ---------------------------------------------------------------------------
# F5 — No fake pass-through files at streaming boundary
# ---------------------------------------------------------------------------

def check_f5() -> list[str]:
    """F5 — No fake pass-through files at streaming boundary."""
    errors: list[str] = []
    coordinator = rel(
        "Apps/Stratix/Sources/Stratix/Consoles/"
        "ConsoleStreamLaunchCoordinator.swift"
    )
    if coordinator.exists():
        relative = coordinator.relative_to(repo_root()).as_posix()
        errors.append(
            f"[F5] Fake pass-through — ConsoleStreamLaunchCoordinator.swift must be dissolved (FB-7)\n"
            f"     {relative}"
        )
    return errors


# ---------------------------------------------------------------------------
# F6 — Test files cover single responsibilities
# ---------------------------------------------------------------------------

_F6_KNOWN: dict[str, str] = {
    "Apps/Stratix/StratixUITests/ShellCheckpointUITests.swift": "FB-8 (1978 lines)",
    "Apps/Stratix/StratixTests/AppSmokeTests.swift": "FB-9 (809 lines)",
}

# Intentional shared harness files: large by design, classified healthy in audit worksheets.
_F6_HARNESS_ALLOWLIST = {
    "PerformanceTestSupport.swift",
}

_TEST_METHOD_RE = re.compile(r"\bfunc test\w+\s*\(")


def check_f6() -> list[str]:
    """F6 — Test files cover single responsibilities: no app test files > 500 lines.

    Package test targets are not scanned here; the plan's F6 findings are
    app-target-only. Package test coverage is evaluated separately.
    """
    errors: list[str] = []
    app_test_roots = [
        rel("Apps/Stratix/StratixTests"),
        rel("Apps/Stratix/StratixUITests"),
        rel("Apps/Stratix/StratixPerformanceTests"),
        rel("Apps/Stratix/StratixPerformanceUITests"),
    ]
    for root in app_test_roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            if path.name in _F6_HARNESS_ALLOWLIST:
                continue
            lc = line_count(path)
            if lc <= 500:
                continue
            relative = path.relative_to(repo_root()).as_posix()
            known_tag = f" (known: {_F6_KNOWN[relative]})" if relative in _F6_KNOWN else ""
            text = read_text(path)
            method_count = len(_TEST_METHOD_RE.findall(text))
            method_note = f"; {method_count} test methods" if method_count > 15 else ""
            errors.append(
                f"[F6] Oversized test file — {path.name} has {lc} lines{method_note}{known_tag}\n"
                f"     {relative}"
            )
    return errors


# ---------------------------------------------------------------------------
# F7 — Logic types must not live in harness files
# ---------------------------------------------------------------------------

def check_f7() -> list[str]:
    """F7 — Logic types must not live in harness files."""
    errors: list[str] = []
    harness = rel(
        "Apps/Stratix/Sources/Stratix/Integration/UITestHarness/"
        "ShellUITestHarnessView.swift"
    )
    if harness.exists():
        text = read_text(harness)
        if "ShellExitHandlingDecision" in text:
            relative = harness.relative_to(repo_root()).as_posix()
            errors.append(
                f"[F7] Logic in harness — ShellUITestHarnessView.swift contains 'ShellExitHandlingDecision'"
                f" which should live in its own file (FB-10)\n"
                f"     {relative}"
            )
    return errors


# ---------------------------------------------------------------------------
# F9 — Reference image location rule
# ---------------------------------------------------------------------------

_F9_SCRIPT_SUFFIXES = {".sh", ".yml", ".yaml", ".json", ".rb", ".js", ".ts"}


def check_f9() -> list[str]:
    """F9 — Reference image location rule: wrong path Tools/reference/ used in CI/build scripts."""
    errors: list[str] = []
    tools_root = rel("Tools")
    # Only scan executable script/config files — not Python source or documentation,
    # which may legitimately mention the path as a negative example.
    wrong_path = "Tools" + "/reference/"  # avoid self-detection
    for path in sorted(tools_root.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() not in _F9_SCRIPT_SUFFIXES:
            continue
        try:
            text = read_text(path)
        except (UnicodeDecodeError, PermissionError):
            continue
        if wrong_path in text:
            relative = path.relative_to(repo_root()).as_posix()
            errors.append(
                f"[F9] Wrong reference path — '{wrong_path}' found in {path.name}; "
                f"canonical path is 'Apps/Stratix/Tools/shell-visual-regression/reference/'\n"
                f"     {relative}"
            )
    return errors


# ---------------------------------------------------------------------------
# E2 — Action closure types not yet annotated @MainActor
# ---------------------------------------------------------------------------

_E2_FILES = [
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/"
    "CloudLibraryBrowseRouteActions.swift",
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/"
    "CloudLibraryDetailRouteActions.swift",
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Presentation/"
    "CloudLibraryUtilityRouteActions.swift",
]

# Closure property without @MainActor prefix.
_UNANNOTATED_CLOSURE_RE = re.compile(
    r"^\s+let \w+: (?!@MainActor)(?:\([^)]*\)|@escaping).*-> "
)


def check_e2() -> list[str]:
    """E2 — Action closure types not yet annotated @MainActor."""
    errors: list[str] = []
    for rel_path in _E2_FILES:
        path = rel(rel_path)
        if not path.exists():
            continue
        text = read_text(path)
        hits = []
        for i, line in enumerate(text.splitlines(), 1):
            if _UNANNOTATED_CLOSURE_RE.match(line):
                hits.append(f"line {i}: {line.strip()}")
        if hits:
            errors.append(
                f"[E2] Missing @MainActor on closure properties in {path.name}\n"
                f"     {rel_path}\n"
                + "".join(f"     {h}\n" for h in hits).rstrip()
            )
    return errors


# ---------------------------------------------------------------------------
# E3 — Swift Async Algorithms not yet adopted
# ---------------------------------------------------------------------------

_MANUAL_DRAIN_RE = re.compile(r"Task\s*\(\s*priority\s*:\s*\.utility\s*\)")


def check_e3() -> list[str]:
    """E3 — Swift Async Algorithms not yet adopted."""
    errors: list[str] = []

    # Check Package.swift files for swift-async-algorithms dependency.
    packages_root = rel("Packages")
    found_in_any = False
    for pkg_manifest in sorted(packages_root.rglob("Package.swift")):
        if "swift-async-algorithms" in read_text(pkg_manifest):
            found_in_any = True
            break

    if not found_in_any:
        errors.append(
            "[E3] swift-async-algorithms not yet added to any Package.swift under Packages/"
        )

    # Check NavigationPerformanceTracker for manual drain/sleep pattern.
    tracker = rel(
        "Apps/Stratix/Sources/Stratix/ViewState/"
        "NavigationPerformanceTracker.swift"
    )
    if tracker.exists():
        text = read_text(tracker)
        if _MANUAL_DRAIN_RE.search(text) and "import AsyncAlgorithms" not in text:
            relative = tracker.relative_to(repo_root()).as_posix()
            errors.append(
                f"[E3] Manual drain/sleep loop in NavigationPerformanceTracker.swift "
                f"(Task(priority: .utility) without AsyncAlgorithms import)\n"
                f"     {relative}"
            )

    return errors


# ---------------------------------------------------------------------------
# E4 — Swift Testing adoption incomplete in unit tests
# ---------------------------------------------------------------------------

def _count_import_pattern(paths: list[Path], import_str: str) -> int:
    return sum(1 for p in paths if import_str in read_text(p))


def check_e4() -> list[str]:
    """E4 — Swift Testing adoption incomplete in unit tests."""
    errors: list[str] = []

    # App unit tests.
    app_tests_root = rel("Apps/Stratix/StratixTests")
    if app_tests_root.exists():
        test_files = list(sorted(app_tests_root.rglob("*.swift")))
        if test_files:
            xctest_count = _count_import_pattern(test_files, "import XCTest")
            testing_count = _count_import_pattern(test_files, "import Testing")
            total = len(test_files)
            if total > 0 and testing_count / total < 0.20:
                pct = int(testing_count / total * 100)
                errors.append(
                    f"[E4] Swift Testing adoption low in StratixTests/: "
                    f"{testing_count}/{total} files use 'import Testing' ({pct}%); "
                    f"{xctest_count} still use XCTest — target ≥ 20%"
                )

    # Package test targets.
    packages_root = rel("Packages")
    if packages_root.exists():
        pkg_test_files = [
            p for pkg in sorted(packages_root.iterdir()) if pkg.is_dir()
            for p in sorted((pkg / "Tests").rglob("*.swift"))
            if (pkg / "Tests").exists()
        ]
        if pkg_test_files:
            xctest_count = _count_import_pattern(pkg_test_files, "import XCTest")
            testing_count = _count_import_pattern(pkg_test_files, "import Testing")
            total = len(pkg_test_files)
            if total > 0 and testing_count / total < 0.20:
                pct = int(testing_count / total * 100)
                errors.append(
                    f"[E4] Swift Testing adoption low in Packages/ test targets: "
                    f"{testing_count}/{total} files use 'import Testing' ({pct}%); "
                    f"{xctest_count} still use XCTest — target ≥ 20%"
                )

    return errors


# ---------------------------------------------------------------------------
# E6 — Liquid Glass surface not yet adopted
# ---------------------------------------------------------------------------

def check_e6() -> list[str]:
    """E6 — Liquid Glass surface not yet adopted."""
    errors: list[str] = []
    glass_card = rel(
        "Apps/Stratix/Sources/Stratix/Shared/Components/GlassCard.swift"
    )
    if glass_card.exists():
        text = read_text(glass_card)
        if ".glassEffect" not in text:
            relative = glass_card.relative_to(repo_root()).as_posix()
            fill_note = ""
            if re.search(r"\bfill\b", text):
                fill_note = " (manual fill/color usage detected — not yet migrated)"
            errors.append(
                f"[E6] Liquid Glass not adopted — GlassCard.swift lacks '.glassEffect'{fill_note}; "
                f"E6 not yet started\n"
                f"     {relative}"
            )
    return errors


# ---------------------------------------------------------------------------
# E7 — Focus token pattern not yet normalized
# ---------------------------------------------------------------------------

_FOCUS_TOKEN_RE = re.compile(r"focusRequestToken\s*:\s*Int")


def check_e7() -> list[str]:
    """E7 — Focus token pattern not yet normalized: integer focus tokens should use prefersDefaultFocus."""
    errors: list[str] = []
    sources_root = rel("Apps/Stratix/Sources")
    for path in _iter_production_swift(sources_root):
        text = read_text(path)
        if _FOCUS_TOKEN_RE.search(text):
            relative = path.relative_to(repo_root()).as_posix()
            errors.append(
                f"[E7] Integer focus token — 'focusRequestToken: Int' in {path.name}; "
                f"replace with prefersDefaultFocus pattern\n"
                f"     {relative}"
            )
    return errors


# ---------------------------------------------------------------------------
# E9 / E12 — Platform seam isolation and third-party framework isolation
# ---------------------------------------------------------------------------

_WEBRTC_IMPORT_RE = re.compile(r"^\s*import\s+WebRTC\b", re.MULTILINE)
_METAL_IMPORT_RE = re.compile(r"^\s*import\s+(?:Metal|MetalKit)\b", re.MULTILINE)


def check_e9_e12() -> list[str]:
    """E9/E12 — Platform seam isolation: WebRTC/Metal imports outside designated seam paths."""
    errors: list[str] = []
    sources_root = rel("Apps/Stratix/Sources")

    for path in _iter_production_swift(sources_root):
        posix = path.as_posix()
        text = read_text(path)
        relative = path.relative_to(repo_root()).as_posix()

        # E9: import WebRTC outside Integration/WebRTC/
        if _WEBRTC_IMPORT_RE.search(text):
            if "Integration/WebRTC/" not in posix:
                errors.append(
                    f"[E9] WebRTC import outside seam — 'import WebRTC' in {path.name} "
                    f"must live under Integration/WebRTC/\n"
                    f"     {relative}"
                )

        # E12: import Metal/MetalKit in feature UI files (Features/CloudLibrary/)
        if _METAL_IMPORT_RE.search(text):
            if "Features/CloudLibrary/" in posix:
                errors.append(
                    f"[E12] Metal import in UI feature — 'import Metal/MetalKit' in {path.name} "
                    f"must not appear in Features/CloudLibrary/ (pure UI feature)\n"
                    f"     {relative}"
                )

    return errors


# ---------------------------------------------------------------------------
# E13 — Mixed support roots / fake wrapper ceremony
# ---------------------------------------------------------------------------

def check_e13() -> list[str]:
    """E13 — Mixed support roots / fake wrapper ceremony."""
    errors: list[str] = []

    # StratixTheme.swift is a known mixed root (also flagged by F1).
    stratix_theme = rel(
        "Apps/Stratix/Sources/Stratix/Shared/Theme/StratixTheme.swift"
    )
    if stratix_theme.exists():
        names = _top_level_type_names(stratix_theme)
        relative = stratix_theme.relative_to(repo_root()).as_posix()
        errors.append(
            f"[E13] Mixed support root — StratixTheme.swift contains blended "
            f"theme/support/runtime-helper types not allowed in modern state\n"
            f"     {relative}\n"
            f"     Types found: {', '.join(names)}"
        )

    # Integration/Previews/ — files with multiple distinct non-preview types.
    previews_root = rel(
        "Apps/Stratix/Sources/Stratix/Integration/Previews"
    )
    if previews_root.exists():
        for path in sorted(previews_root.rglob("*.swift")):
            names = _top_level_type_names(path)
            if len(names) >= 2:
                relative = path.relative_to(repo_root()).as_posix()
                errors.append(
                    f"[E13] Preview integration file has {len(names)} distinct non-preview types "
                    f"in {path.name}; preview support must have truthful single ownership\n"
                    f"     {relative}\n"
                    f"     Types found: {', '.join(names)}"
                )

    return errors


# ---------------------------------------------------------------------------
# E1 — Layered actor strategy: @MainActor on key state types
# ---------------------------------------------------------------------------

# Key state types that E1 requires to carry explicit @MainActor.
# SwiftUI View conformance gives implicit body isolation but not type-level
# @MainActor. State objects and view-model-adjacent types must be explicit.
_E1_MAINACTOR_REQUIRED: dict[str, list[str]] = {
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryFocusState.swift": [
        "@MainActor",
    ],
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryRouteState.swift": [
        "@MainActor",
    ],
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneModel.swift": [
        "@MainActor",
    ],
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryPresentationStore.swift": [
        "@MainActor",
    ],
}

# Types that must NOT be @MainActor per E1 Layer 3 (rendering/compute paths).
_E1_MAINACTOR_FORBIDDEN_TYPES = [
    # Off-main streaming helpers must not regain type-level @MainActor.
    "StreamHeroArtworkEnvironment",
    "StreamAchievementRefreshCoordinator",
    "StreamOverlayVisibilityCoordinator",
    "StreamReconnectCoordinator",
]


def check_e1() -> list[str]:
    """E1 — Layered actor strategy: @MainActor must be explicit on key state/model types."""
    errors: list[str] = []

    for rel_path, needles in _E1_MAINACTOR_REQUIRED.items():
        path = rel(rel_path)
        if not path.exists():
            errors.append(
                f"[E1] Missing required file — {path.name} does not exist\n"
                f"     {rel_path}"
            )
            continue
        text = read_text(path)
        for needle in needles:
            if needle not in text:
                errors.append(
                    f"[E1] @MainActor isolation not explicit — '{needle}' not found in {path.name}; "
                    f"E1 Layer 1 requires explicit @MainActor on state/model types\n"
                    f"     {rel_path}"
                )

    # Layer 3: rendering/compute helpers must not carry type-level @MainActor.
    streaming_sources = rel(
        "Packages/StratixCore/Sources/StratixCore/Streaming"
    )
    if streaming_sources.exists():
        for path in sorted(streaming_sources.rglob("*.swift")):
            text = read_text(path)
            for type_name in _E1_MAINACTOR_FORBIDDEN_TYPES:
                if type_name in text:
                    # Check for @MainActor on the struct/class/actor line
                    if f"@MainActor struct {type_name}" in text or f"@MainActor final class {type_name}" in text:
                        relative = path.relative_to(repo_root()).as_posix()
                        errors.append(
                            f"[E1] Rendering/compute type regained @MainActor — '{type_name}' in "
                            f"{path.name} must not be type-level @MainActor (E1 Layer 3)\n"
                            f"     {relative}"
                        )

    return errors


# ---------------------------------------------------------------------------
# E5 — SwiftData adoption tracking
# ---------------------------------------------------------------------------

def check_e5() -> list[str]:
    """E5 — SwiftData adoption: tracks whether adoption has started in StratixCore/Hydration.

    stage2 validates the hydration structural prerequisite. This check confirms
    whether SwiftData has actually been adopted (import SwiftData present) and
    that no SwiftData types leak outside StratixCore/Hydration/.
    """
    errors: list[str] = []

    hydration_root = rel("Packages/StratixCore/Sources/StratixCore/Hydration")
    if not hydration_root.exists():
        errors.append(
            "[E5] Missing hydration directory — Packages/StratixCore/Sources/StratixCore/Hydration/ "
            "must exist (stage2 structural prerequisite)"
        )
        return errors

    hydration_files = list(hydration_root.rglob("*.swift"))
    adopted = any("import SwiftData" in read_text(f) for f in hydration_files)

    if not adopted:
        errors.append(
            "[E5] SwiftData not yet adopted — no 'import SwiftData' found in "
            "Packages/StratixCore/Sources/StratixCore/Hydration/; "
            "E5 requires SwiftData adoption behind the repository interface (pending)"
        )
        return errors

    # If adopted, verify it hasn't leaked outside Hydration/.
    package_sources = rel("Packages/StratixCore/Sources/StratixCore")
    for path in sorted(package_sources.rglob("*.swift")):
        if hydration_root in path.parents:
            continue
        if "import SwiftData" in read_text(path):
            relative = path.relative_to(repo_root()).as_posix()
            errors.append(
                f"[E5] SwiftData leaked outside Hydration boundary — {path.name} imports SwiftData "
                f"outside StratixCore/Hydration/; E5 requires confinement behind repository interface\n"
                f"     {relative}"
            )

    # Also check app target.
    app_sources = rel("Apps/Stratix/Sources")
    for path in sorted(app_sources.rglob("*.swift")):
        if "import SwiftData" in read_text(path):
            relative = path.relative_to(repo_root()).as_posix()
            errors.append(
                f"[E5] SwiftData leaked into app target — {path.name} imports SwiftData; "
                f"app must not import SwiftData directly (E5 requires confinement to StratixCore/Hydration/)\n"
                f"     {relative}"
            )

    return errors


# ---------------------------------------------------------------------------
# E8 — FrameProbeRenderer concurrency correctness
# ---------------------------------------------------------------------------

def check_e8() -> list[str]:
    """E8 — FrameProbeRenderer must use @unchecked Sendable + NSLock after extraction (FB-1).

    While FB-1 (splitting RendererAttachmentCoordinator) is pending, this check
    reports the precondition state. Once FrameProbeRenderer.swift exists on its
    own, it must have @unchecked Sendable + NSLock (matching MetalVideoRenderer).
    """
    errors: list[str] = []

    # Current state: FrameProbeRenderer is still embedded in RendererAttachmentCoordinator.
    mixed_root = rel(
        "Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/"
        "RendererAttachmentCoordinator.swift"
    )
    extracted = rel(
        "Apps/Stratix/Sources/Stratix/Integration/WebRTC/FrameProbeRenderer.swift"
    )

    if extracted.exists():
        # FB-1 is done — enforce E8 requirements on the extracted file.
        text = read_text(extracted)
        relative = extracted.relative_to(repo_root()).as_posix()
        if "@unchecked Sendable" not in text:
            errors.append(
                f"[E8] FrameProbeRenderer missing @unchecked Sendable — {extracted.name} must declare "
                f"'@unchecked Sendable' with NSLock protection (E8 requirement)\n"
                f"     {relative}"
            )
        if "NSLock" not in text and "lock" not in text.lower():
            errors.append(
                f"[E8] FrameProbeRenderer missing NSLock protection — {extracted.name} must use "
                f"NSLock to protect mutable state (E8 requirement)\n"
                f"     {relative}"
            )
    elif mixed_root.exists():
        # FB-1 still pending — report E8 as blocked, and verify FrameProbeRenderer
        # is not already trying to use @unchecked Sendable incorrectly in the mixed file.
        text = read_text(mixed_root)
        if "class FrameProbeRenderer" in text:
            if "@unchecked Sendable" not in text:
                errors.append(
                    "[E8] FrameProbeRenderer not yet extracted (FB-1 pending) and lacks "
                    "@unchecked Sendable — E8 requires extraction + @unchecked Sendable + NSLock; "
                    "blocked on floor blocker FB-1\n"
                    f"     {mixed_root.relative_to(repo_root()).as_posix()}"
                )
    else:
        errors.append(
            "[E8] Cannot locate FrameProbeRenderer — neither RendererAttachmentCoordinator.swift "
            "nor a standalone FrameProbeRenderer.swift found"
        )

    return errors


# ---------------------------------------------------------------------------
# E11 — Dependency direction supplement
# ---------------------------------------------------------------------------

# App feature UI paths that must not import concrete platform seam packages directly.
# AppCoordinator coupling is already checked by check_f8_e11_package_boundaries.py.
# This check guards the remaining E11 direction rules not covered there.
_E11_FEATURE_UI_ROOTS = [
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary",
    "Apps/Stratix/Sources/Stratix/Features/Guide",
]

# Packages that feature UI should access through StratixCore interfaces, not directly.
_E11_FORBIDDEN_DIRECT_IMPORTS = [
    "import StreamingCore",
    "import VideoRenderingKit",
    "import XCloudAPI",
]


def check_e11() -> list[str]:
    """E11 — Dependency direction: feature UI must not import concrete platform packages directly.

    AppCoordinator / composition coupling is already guarded by
    check_f8_e11_package_boundaries.py. This check covers the remaining E11
    rule: feature UI slices depend on state/service interfaces, not concrete
    platform seam packages.
    """
    errors: list[str] = []

    for feature_root_str in _E11_FEATURE_UI_ROOTS:
        feature_root = rel(feature_root_str)
        if not feature_root.exists():
            continue
        for path in sorted(feature_root.rglob("*.swift")):
            if _is_test_file(path):
                continue
            text = read_text(path)
            for forbidden in _E11_FORBIDDEN_DIRECT_IMPORTS:
                if forbidden in text:
                    relative = path.relative_to(repo_root()).as_posix()
                    errors.append(
                        f"[E11] Direct platform package import in feature UI — '{forbidden}' in "
                        f"{path.name}; feature UI must depend on StratixCore service interfaces, "
                        f"not concrete platform packages\n"
                        f"     {relative}"
                    )

    return errors


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

ALL_CHECKS: dict[str, tuple[str, object]] = {
    "F1": ("No mixed roots", check_f1),
    "F2": ("No micro-shards", check_f2),
    "F3": ("Naming must communicate intent", check_f3),
    "F4": ("Fake seams dissolved at action routing", check_f4),
    "F5": ("No fake pass-through files at streaming boundary", check_f5),
    "F6": ("Test files cover single responsibilities", check_f6),
    "F7": ("Logic types must not live in harness files", check_f7),
    "F9": ("Reference image location rule", check_f9),
    "E1": ("Layered actor strategy — @MainActor on key state types", check_e1),
    "E2": ("Action closure types not yet annotated @MainActor", check_e2),
    "E3": ("Swift Async Algorithms not yet adopted", check_e3),
    "E4": ("Swift Testing adoption incomplete in unit tests", check_e4),
    "E5": ("SwiftData adoption in StratixCore/Hydration", check_e5),
    "E6": ("Liquid Glass surface not yet adopted", check_e6),
    "E7": ("Focus token pattern not yet normalized", check_e7),
    "E8": ("FrameProbeRenderer concurrency correctness", check_e8),
    "E9/E12": ("Platform seam isolation and third-party framework isolation", check_e9_e12),
    "E11": ("Dependency direction must follow architecture", check_e11),
    "E13": ("Mixed support roots / fake wrapper ceremony", check_e13),
}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Floor and execution contract linter for the Stratix iOS/tvOS project."
    )
    parser.add_argument(
        "--rule",
        metavar="RULE",
        help="Run only the specified rule (e.g. F1, E3). Prefix-matches supported.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output violations as JSON.",
    )
    args = parser.parse_args()

    selected: dict[str, tuple[str, object]] = {}
    if args.rule:
        rule_upper = args.rule.upper()
        # Exact match takes priority; fall back to prefix/contains for partial inputs.
        if rule_upper in {k.upper() for k in ALL_CHECKS}:
            selected = {k: v for k, v in ALL_CHECKS.items() if k.upper() == rule_upper}
        else:
            for key, value in ALL_CHECKS.items():
                if key.upper().startswith(rule_upper) or rule_upper in key.upper():
                    selected[key] = value
        if not selected:
            print(f"Unknown rule: {args.rule!r}. Available: {', '.join(ALL_CHECKS)}", file=sys.stderr)
            return 2
    else:
        selected = ALL_CHECKS

    all_violations: dict[str, list[str]] = {}
    for rule_id, (description, check_fn) in selected.items():
        violations = check_fn()  # type: ignore[operator]
        all_violations[rule_id] = violations

    if args.json_output:
        print(json.dumps(all_violations, indent=2))
    else:
        for rule_id, violations in all_violations.items():
            if violations:
                for v in violations:
                    print(v)

    # Summary table.
    floor_rules = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F9"]
    exec_rules = ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9/E12", "E11", "E13"]

    floor_violations = sum(
        len(v) for k, v in all_violations.items() if k in floor_rules
    )
    exec_violations = sum(
        len(v) for k, v in all_violations.items() if k in exec_rules
    )
    total = floor_violations + exec_violations

    if not args.json_output:
        print()
        print(f"Floor rules:   {' '.join(floor_rules)}  — {floor_violations} violations")
        print(f"Execution:     {' '.join(exec_rules)}  — {exec_violations} violations")
        print("(F8 covered by check_f8_e11_package_boundaries + check_f8_package_platform_audit; F10 by check_f10_typed_ids + check_f10_typed_id_completion)")

    return 1 if total > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
