#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re

from common import rel, repo_root, fail

errors: list[str] = []
root = repo_root()

doc_targets = [
    rel("README.md"),
    rel("CHANGELOG.md"),
    rel("CONTRIBUTING.md"),
    rel("GOVERNANCE.md"),
    rel("MAINTAINERS.md"),
    rel("SECURITY.md"),
    rel("SUPPORT.md"),
    rel("TRADEMARK.md"),
    rel("EXECUTION_PLAN_STATUS.md"),
    rel(".github/pull_request_template.md"),
]
doc_targets.extend(
    sorted(path for path in rel("Docs").rglob("*.md") if "Docs/archive/" not in path.as_posix())
)

link_pattern = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
absolute_path_pattern = re.compile(r"(?<!\w)(/Users/[^)\s`]+|file://[^\s)`]+)")


def normalize_target(raw_target: str) -> str:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1].strip()
    if " " in target and not target.startswith(("http://", "https://", "mailto:", "tel:")):
        target = target.split(" ", 1)[0]
    return target


def is_external(target: str) -> bool:
    return bool(re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target))


def resolve_repo_target(source: Path, target: str) -> Path:
    link_target = target.split("#", 1)[0].split("?", 1)[0]
    source_relative = (source.parent / link_target).resolve()
    if source_relative.exists():
        return source_relative
    return (root / link_target).resolve()


for path in doc_targets:
    if not path.exists():
        errors.append(f"Missing required documentation path: {path}")
        continue

    text = path.read_text(encoding="utf-8")
    for match in absolute_path_pattern.finditer(text):
        errors.append(f"{path}: forbidden absolute-path documentation reference {match.group(1)!r}")

    for raw_target in link_pattern.findall(text):
        target = normalize_target(raw_target)
        if not target or target.startswith("#"):
            continue
        if is_external(target):
            continue
        if target.startswith("/"):
            errors.append(f"{path}: forbidden absolute-path link target {target!r}")
            continue

        resolved = resolve_repo_target(path, target)
        try:
            resolved.relative_to(root)
        except ValueError:
            errors.append(f"{path}: link escapes repository root: {target!r}")
            continue

        if not resolved.exists():
            errors.append(f"{path}: repo-relative link target missing: {target!r}")

fail(errors)
print("Docs portability guard passed.")
