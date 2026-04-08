#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess
import sys
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]


def repo_root() -> Path:
    return ROOT


def rel(*parts: str) -> Path:
    return ROOT.joinpath(*parts)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require_paths(paths: Iterable[Path]) -> list[str]:
    errors: list[str] = []
    for path in paths:
        if not path.exists():
            errors.append(f"Missing required path: {path}")
    return errors


def assert_contains(path: Path, needles: Iterable[str]) -> list[str]:
    text = read_text(path)
    errors: list[str] = []
    for needle in needles:
        if needle not in text:
            errors.append(f"{path}: expected to contain {needle!r}")
    return errors


def assert_not_contains(path: Path, needles: Iterable[str]) -> list[str]:
    text = read_text(path)
    errors: list[str] = []
    for needle in needles:
        if needle in text:
            errors.append(f"{path}: forbidden content {needle!r}")
    return errors


def count_occurrences(path: Path, needle: str) -> int:
    return read_text(path).count(needle)


def line_count(path: Path) -> int:
    return len(read_text(path).splitlines())


def run(cmd: list[str]) -> str:
    completed = subprocess.run(
        cmd,
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def merge_base(base_ref: str) -> str:
    return run(["git", "merge-base", f"origin/{base_ref}", "HEAD"])


def changed_files(base_ref: str) -> list[str]:
    base = merge_base(base_ref)
    output = run(["git", "diff", "--name-only", f"{base}...HEAD"])
    return [line.strip() for line in output.splitlines() if line.strip()]


def fail(errors: list[str]) -> None:
    if errors:
        print("\n".join(errors))
        sys.exit(1)
