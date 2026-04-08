#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

REPO_ROOT = Path(__file__).resolve().parents[2]

UNCHECKED_SENDABLE_ALLOWLIST = {
    "Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/SampleBufferDisplayRenderer.swift": [
        "RTCVideoRenderer",
        "AVSampleBufferDisplayLayer",
    ],
    "Apps/Stratix/Sources/Stratix/Integration/WebRTC/MetalVideoRenderer.swift": [
        "RTCVideoRenderer",
        "MTKViewDelegate",
    ],
    "Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImpl.swift": [
        "NSObject",
        "WebRTCBridge",
    ],
}

SWIFT_FILE_PATTERN = "*.swift"
UNCHECKED_SENDABLE_PATTERN = re.compile(r"@unchecked\s+Sendable")
NONISOLATED_UNSAFE_PATTERN = re.compile(r"nonisolated\s*\(\s*unsafe\s*\)")


def iter_production_swift_files() -> list[Path]:
    files: list[Path] = []

    app_root = REPO_ROOT / "Apps" / "Stratix" / "Sources"
    files.extend(sorted(app_root.rglob(SWIFT_FILE_PATTERN)))

    for package_sources in sorted((REPO_ROOT / "Packages").glob("*/Sources")):
        files.extend(sorted(package_sources.rglob(SWIFT_FILE_PATTERN)))

    return files


def rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def main() -> int:
    errors: list[str] = []

    for path in iter_production_swift_files():
        text = path.read_text()
        relative_path = rel(path)

        if NONISOLATED_UNSAFE_PATTERN.search(text):
            errors.append(
                f"{relative_path}: production code must not use nonisolated(unsafe)"
            )

        if UNCHECKED_SENDABLE_PATTERN.search(text) and relative_path not in UNCHECKED_SENDABLE_ALLOWLIST:
            errors.append(
                f"{relative_path}: production code must not use @unchecked Sendable outside the approved WebRTC/renderer bridge allowlist"
            )

        if relative_path in UNCHECKED_SENDABLE_ALLOWLIST:
            for needle in UNCHECKED_SENDABLE_ALLOWLIST[relative_path]:
                if needle not in text:
                    errors.append(
                        f"{relative_path}: approved @unchecked Sendable boundary drifted; missing expected marker {needle!r}"
                    )

    documented_allowlist = sorted(UNCHECKED_SENDABLE_ALLOWLIST)
    discovered_allowlist = sorted(
        rel(path)
        for path in iter_production_swift_files()
        if UNCHECKED_SENDABLE_PATTERN.search(path.read_text())
    )

    if discovered_allowlist != documented_allowlist:
        errors.append(
            "Production @unchecked Sendable allowlist drift detected:\n"
            f"  expected: {documented_allowlist}\n"
            f"  found:    {discovered_allowlist}"
        )

    if errors:
        print("Concurrency exception guard failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("Concurrency exception guard passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
