#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

AUDIT_ROOT="${1:-}"
OUTPUT_PATH="${2:-}"

if [[ -z "$AUDIT_ROOT" ]]; then
  AUDIT_ROOT="$(find "$REPO_ROOT/Docs/archive/reviews/2026-03-28/review_artifacts" -mindepth 1 -maxdepth 1 -type d -name '*finished_branch_audit' | sort | tail -n 1)"
fi

if [[ -z "$AUDIT_ROOT" || ! -d "$AUDIT_ROOT" ]]; then
  echo "Error: could not determine audit directory." >&2
  exit 1
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="$AUDIT_ROOT/04_validation_summary.md"
fi

LANE_RESULTS="$AUDIT_ROOT/03_lane_results.tsv"
SUMMARY_SOURCE="$AUDIT_ROOT/00_summary.md"
GOAL_MATRIX="$AUDIT_ROOT/02_goal_matrix.md"

if [[ ! -f "$LANE_RESULTS" ]]; then
  echo "Error: lane results not found at $LANE_RESULTS" >&2
  exit 1
fi

python3 - "$AUDIT_ROOT" "$LANE_RESULTS" "$SUMMARY_SOURCE" "$GOAL_MATRIX" "$OUTPUT_PATH" <<'PY'
from __future__ import annotations

import csv
import sys
from collections import Counter
from pathlib import Path

audit_root = Path(sys.argv[1])
lane_results = Path(sys.argv[2])
summary_source = Path(sys.argv[3])
goal_matrix = Path(sys.argv[4])
output_path = Path(sys.argv[5])

rows: list[dict[str, str]] = []
with lane_results.open() as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    for row in reader:
        rows.append(row)

counts = Counter("PASS" if row["exit_status"] == "0" else "FAIL" for row in rows)
category_counts: dict[str, Counter[str]] = {}
for row in rows:
    category_counts.setdefault(row["category"], Counter())
    category_counts[row["category"]]["PASS" if row["exit_status"] == "0" else "FAIL"] += 1

failing_rows = [row for row in rows if row["exit_status"] != "0"]

lines: list[str] = []
lines.append("# Validation Summary")
lines.append("")
lines.append(f"- Audit root: `{audit_root}`")
lines.append(f"- Total lanes: `{len(rows)}`")
lines.append(f"- Passing lanes: `{counts['PASS']}`")
lines.append(f"- Failing lanes: `{counts['FAIL']}`")
lines.append("")
lines.append("## Category Summary")
lines.append("")
lines.append("| Category | Pass | Fail |")
lines.append("| --- | --- | --- |")
for category in sorted(category_counts):
    lines.append(f"| {category} | {category_counts[category]['PASS']} | {category_counts[category]['FAIL']} |")
lines.append("")
lines.append("## Failing Lanes")
lines.append("")
if failing_rows:
    for row in failing_rows:
        lines.append(f"- `{row['lane_id']}` `{row['category']}` `{row['label']}`")
        lines.append(f"  - evidence: `{row['log_path']}`")
else:
    lines.append("- None")
lines.append("")
lines.append("## Approval Posture")
lines.append("")
if failing_rows:
    lines.append("- Current posture: not ready for approval")
    lines.append("- Reason: one or more required lanes are failing on the current head")
else:
    lines.append("- Current posture: lane matrix is green at the audit layer")
    lines.append("- Final approval still depends on docs truth, release-bundle generation, and any required hardware/profile evidence")
lines.append("")
lines.append("## Evidence")
lines.append("")
if summary_source.exists():
    lines.append(f"- Audit summary: `{summary_source}`")
if goal_matrix.exists():
    lines.append(f"- Goal matrix: `{goal_matrix}`")
lines.append(f"- Lane matrix: `{lane_results}`")
lines.append("")

output_path.write_text("\n".join(lines) + "\n")
PY

echo "Wrote validation summary to $OUTPUT_PATH"
