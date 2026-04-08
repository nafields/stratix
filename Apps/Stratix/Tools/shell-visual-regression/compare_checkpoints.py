#!/usr/bin/env python3
"""Compare captured shell checkpoints against reference PNGs using FFmpeg SSIM."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


SSIM_PATTERN = re.compile(r"All:(?P<value>[0-9.]+)")
CHECKPOINTS = ("home", "search", "library")


@dataclass
class ComparisonResult:
    name: str
    ssim: float
    passed: bool
    reference: str
    capture: str
    diff: str


def run_ffmpeg_ssim(reference: Path, capture: Path) -> float:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "info",
        "-i",
        str(reference),
        "-i",
        str(capture),
        "-lavfi",
        "ssim",
        "-f",
        "null",
        "-",
    ]
    process = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    match = SSIM_PATTERN.search(process.stdout)
    if process.returncode != 0 or not match:
        raise RuntimeError(f"Unable to calculate SSIM for {reference.name}:\n{process.stdout}")
    return float(match.group("value"))


def write_diff_image(reference: Path, capture: Path, diff_output: Path) -> None:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(reference),
        "-i",
        str(capture),
        "-filter_complex",
        "[0:v][1:v]blend=all_mode=difference,eq=contrast=6:brightness=0.02",
        "-frames:v",
        "1",
        str(diff_output),
    ]
    process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    if process.returncode != 0:
        raise RuntimeError(f"Unable to write diff image {diff_output.name}: {process.stderr}")


def compare_all(reference_dir: Path, capture_dir: Path, output_dir: Path, min_ssim: float) -> list[ComparisonResult]:
    output_dir.mkdir(parents=True, exist_ok=True)
    results: list[ComparisonResult] = []
    for name in CHECKPOINTS:
        reference = reference_dir / f"{name}.png"
        capture = capture_dir / f"{name}.png"
        if not reference.exists():
            raise FileNotFoundError(f"Missing reference checkpoint: {reference}")
        if not capture.exists():
            raise FileNotFoundError(f"Missing captured checkpoint: {capture}")

        diff_output = output_dir / f"{name}.diff.png"
        ssim = run_ffmpeg_ssim(reference, capture)
        write_diff_image(reference, capture, diff_output)
        results.append(
            ComparisonResult(
                name=name,
                ssim=ssim,
                passed=ssim >= min_ssim,
                reference=str(reference),
                capture=str(capture),
                diff=str(diff_output),
            )
        )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare shell checkpoint screenshots.")
    parser.add_argument("--reference-dir", required=True, help="Directory containing reference home/search/library PNGs.")
    parser.add_argument("--capture-dir", required=True, help="Directory containing captured home/search/library PNGs.")
    parser.add_argument("--output-dir", required=True, help="Directory for diff outputs and JSON report.")
    parser.add_argument("--min-ssim", type=float, default=0.93, help="Minimum SSIM threshold required per checkpoint.")
    args = parser.parse_args()

    reference_dir = Path(args.reference_dir).expanduser().resolve()
    capture_dir = Path(args.capture_dir).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    results = compare_all(reference_dir, capture_dir, output_dir, args.min_ssim)

    report = {
        "min_ssim": args.min_ssim,
        "results": [
            {
                "checkpoint": result.name,
                "ssim": result.ssim,
                "passed": result.passed,
                "reference": result.reference,
                "capture": result.capture,
                "diff": result.diff,
            }
            for result in results
        ],
        "all_passed": all(result.passed for result in results),
    }
    report_path = output_dir / "comparison-report.json"
    report_path.write_text(json.dumps(report, indent=2))

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"{status} {result.name:<8} SSIM={result.ssim:.5f}")

    print(f"Report: {report_path}")
    return 0 if report["all_passed"] else 2


if __name__ == "__main__":
    sys.exit(main())
