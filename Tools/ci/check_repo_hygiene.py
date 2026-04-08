#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_ROOT = REPO_ROOT / "Docs" / "archive" / "reviews" / "2026-03-28"
ASSET_CATALOG = REPO_ROOT / "Apps" / "Stratix" / "Stratix" / "Assets.xcassets"
MISSPELLED_ASSET_CATALOG = REPO_ROOT / "Apps" / "Stratix" / "Stratix" / "Assests.xcassets"
PROJECT_FILE = REPO_ROOT / "Apps" / "Stratix" / "Stratix.xcodeproj" / "project.pbxproj"
VALIDATION_DOC = REPO_ROOT / "Docs" / "XCODE_VALIDATION_MATRIX.md"

ROOT_SCRATCH_NAMES = {
    "new views",
    "overlay",
    "overlay-next",
    "mock_sendable_probe",
    "gamepass_library.json",
    "review_artifacts",
    "review_audit",
    "phase_update_code_review",
    "phase_update_code_review.md",
}

REQUIRED_XCTESTPLANS = {
    "ShellRegression.xctestplan",
    "Performance.xctestplan",
    "MetalRendering.xctestplan",
    "ValidationAll.xctestplan",
    "PackagesRegression.xctestplan",
    "Stratix.xctestplan",
}


def rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def contains_reference(doc_text: str, needle: str) -> bool:
    return needle in doc_text


def iter_named_paths(root: Path, target_name: str):
    for current_root, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            dirname
            for dirname in dirnames
            if dirname not in {".git", ".build", ".swiftpm", "__pycache__", "DerivedData"}
        ]

        current_path = Path(current_root)
        if current_path.name == target_name:
            yield current_path

        for filename in filenames:
            if filename == target_name:
                yield current_path / filename


def tracked_repo_paths() -> set[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
    )
    raw_paths = [entry for entry in result.stdout.decode("utf-8", errors="ignore").split("\0") if entry]
    return set(raw_paths)


def main() -> int:
    errors: list[str] = []
    tracked_paths = tracked_repo_paths()

    for name in sorted(ROOT_SCRATCH_NAMES):
        path = REPO_ROOT / name
        if path.exists():
            errors.append(f"repo root contains banned scratch artifact: {name}")

    for path in iter_named_paths(REPO_ROOT, ".build"):
        errors.append(f"package/build artifact directory must not be present: {rel(path)}")

    for path in iter_named_paths(REPO_ROOT, "__pycache__"):
        errors.append(f"python cache directory must not be present: {rel(path)}")

    for path in iter_named_paths(REPO_ROOT, ".DS_Store"):
        relative_path = rel(path)
        if relative_path in tracked_paths:
            errors.append(f".DS_Store must not be tracked: {relative_path}")

    if MISSPELLED_ASSET_CATALOG.exists():
        errors.append(f"misspelled asset catalog still present: {rel(MISSPELLED_ASSET_CATALOG)}")

    if not ASSET_CATALOG.exists():
        errors.append(f"required asset catalog missing: {rel(ASSET_CATALOG)}")

    accent_color = ASSET_CATALOG / "AccentColor.colorset" / "Contents.json"
    if not accent_color.exists():
        errors.append(f"AccentColor asset is missing: {rel(accent_color)}")

    project_text = PROJECT_FILE.read_text()
    if "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;" not in project_text:
        errors.append("project settings no longer declare AccentColor while the repo requires an explicit accent asset")
    if "Assests.xcassets" in project_text:
        errors.append("project file still references misspelled Assests.xcassets")

    validation_doc_text = VALIDATION_DOC.read_text()
    for plan in sorted(REQUIRED_XCTESTPLANS):
        if not contains_reference(validation_doc_text, plan):
            errors.append(f"validation docs do not mention active/spare plan: {plan}")

    archived_review_paths = {
        ARCHIVE_ROOT / "review_artifacts",
        ARCHIVE_ROOT / "review_audit",
        ARCHIVE_ROOT / "phase_update_code_review",
        ARCHIVE_ROOT / "phase_update_code_review.md",
    }
    for archived_path in archived_review_paths:
        if not archived_path.exists():
            errors.append(f"required archived review artifact is missing: {rel(archived_path)}")

    for needle in ("review_artifacts", "review_audit", "phase_update_code_review", "phase_update_code_review.md"):
        for path in iter_named_paths(REPO_ROOT, needle):
            if path in archived_review_paths:
                continue
            errors.append(f"review/audit artifact must live under {rel(ARCHIVE_ROOT)}: {rel(path)}")

    if errors:
        print("Repo hygiene check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Repo hygiene check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
