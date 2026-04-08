#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

usage() {
  cat <<'EOF'
usage: export_workflow_exports.sh <output_root> [--sha <git-sha>] [--repo <owner/name>]

Exports the required hosted workflow evidence for the requested candidate head into:
  <output_root>/
    ci-pr-fast-guards.txt
    ci-packages.txt
    ci-app-build-and-smoke.txt
    ci-runtime-safety.txt
    ci-shell-ui.txt
    ci-shell-visual-regression.txt
    ci-release-and-validation.txt
    ci-hardware-device.txt

Defaults:
  --sha  HEAD
  --repo inferred from git remote origin
EOF
}

OUTPUT_ROOT="${1:-}"
if [[ -z "$OUTPUT_ROOT" ]]; then
  usage
  exit 1
fi
shift || true

TARGET_SHA="$(git rev-parse HEAD)"

infer_repo() {
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ "$remote_url" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  return 1
}

REPO_SLUG="$(infer_repo || true)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sha)
      TARGET_SHA="${2:-}"
      shift 2
      ;;
    --repo)
      REPO_SLUG="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REPO_SLUG" ]]; then
  echo "failed to infer GitHub repo slug; pass --repo <owner/name>" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

mkdir -p "$OUTPUT_ROOT"

python3 - "$REPO_ROOT" "$OUTPUT_ROOT" "$REPO_SLUG" "$TARGET_SHA" "$(git rev-parse --abbrev-ref HEAD)" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
output_root = Path(sys.argv[2])
repo_slug = sys.argv[3]
target_sha = sys.argv[4]
branch = sys.argv[5]

workflow_pairs = [
    ("ci-pr-fast-guards.yml", "ci-pr-fast-guards.txt"),
    ("ci-packages.yml", "ci-packages.txt"),
    ("ci-app-build-and-smoke.yml", "ci-app-build-and-smoke.txt"),
    ("ci-runtime-safety.yml", "ci-runtime-safety.txt"),
    ("ci-shell-ui.yml", "ci-shell-ui.txt"),
    ("ci-shell-visual-regression.yml", "ci-shell-visual-regression.txt"),
    ("ci-release-and-validation.yml", "ci-release-and-validation.txt"),
    ("ci-hardware-device.yml", "ci-hardware-device.txt"),
]


def run_gh(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["gh", *args],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )


def workflow_name_for_file(workflow_file: str) -> str | None:
    path = repo_root / ".github" / "workflows" / workflow_file
    if not path.exists():
        return None
    for line in path.read_text().splitlines():
        if line.startswith("name:"):
            return line.split(":", 1)[1].strip()
    return None


def list_runs(workflow_selector: str, *, by_commit: bool) -> list[dict]:
    args = [
        "run",
        "list",
        "--repo",
        repo_slug,
        "--workflow",
        workflow_selector,
        "--limit",
        "50",
        "--json",
        "databaseId,workflowName,displayTitle,headSha,status,conclusion,url,createdAt,updatedAt",
    ]
    if by_commit:
        args.extend(["--commit", target_sha])
    else:
        args.extend(["--branch", branch])

    proc = run_gh(args)
    if proc.returncode != 0 or not proc.stdout.strip():
        return []

    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []


def select_run(workflow_file: str) -> dict | None:
    selectors = [workflow_file]
    workflow_name = workflow_name_for_file(workflow_file)
    if workflow_name and workflow_name not in selectors:
        selectors.append(workflow_name)

    for selector in selectors:
        runs = list_runs(selector, by_commit=True)
        if runs:
            completed = [run for run in runs if run.get("status") == "completed"]
            return completed[0] if completed else runs[0]

    for selector in selectors:
        runs = [run for run in list_runs(selector, by_commit=False) if run.get("headSha") == target_sha]
        if runs:
            completed = [run for run in runs if run.get("status") == "completed"]
            return completed[0] if completed else runs[0]

    return None


def write_missing(path: Path, workflow_file: str, reason: str) -> None:
    path.write_text(
        "\n".join(
            [
                f"Missing workflow export for {workflow_file}",
                f"repo: {repo_slug}",
                f"target_sha: {target_sha}",
                f"reason: {reason}",
                "",
            ]
        )
    )


for workflow_file, export_name in workflow_pairs:
    export_path = output_root / export_name
    run = select_run(workflow_file)
    if not run:
        write_missing(export_path, workflow_file, "no workflow run found for the requested commit")
        continue

    run_id = str(run["databaseId"])
    view_proc = run_gh(
        [
            "run",
            "view",
            run_id,
            "--repo",
            repo_slug,
            "--json",
            "databaseId,workflowName,displayTitle,headSha,status,conclusion,url,createdAt,updatedAt,jobs",
        ]
    )
    log_proc = run_gh(["run", "view", run_id, "--repo", repo_slug, "--log"])

    if view_proc.returncode != 0 or not view_proc.stdout.strip():
        write_missing(export_path, workflow_file, "gh run view returned no JSON payload")
        continue

    try:
        view = json.loads(view_proc.stdout)
    except json.JSONDecodeError:
        write_missing(export_path, workflow_file, "gh run view returned invalid JSON payload")
        continue

    lines = [
        f"workflow_file: {workflow_file}",
        f"workflow_name: {view.get('workflowName', 'unknown')}",
        f"run_id: {view.get('databaseId', 'unknown')}",
        f"repo: {repo_slug}",
        f"target_sha: {target_sha}",
        f"run_head_sha: {view.get('headSha', 'unknown')}",
        f"status: {view.get('status', 'unknown')}",
        f"conclusion: {view.get('conclusion', 'unknown')}",
        f"url: {view.get('url', 'unknown')}",
        f"created_at: {view.get('createdAt', 'unknown')}",
        f"updated_at: {view.get('updatedAt', 'unknown')}",
        "",
        "jobs:",
    ]

    jobs = view.get("jobs") or []
    if not jobs:
        lines.append("- none")
    else:
        for job in jobs:
            lines.append(
                f"- {job.get('name', 'unknown')} | status={job.get('status', 'unknown')} "
                f"| conclusion={job.get('conclusion', 'unknown')} | started={job.get('startedAt', 'unknown')} "
                f"| completed={job.get('completedAt', 'unknown')}"
            )

    lines.extend(["", "log:"])
    log_text = (log_proc.stdout or "").rstrip()
    lines.append(log_text if log_text else "log unavailable")
    lines.append("")
    export_path.write_text("\n".join(lines))
PY

echo "Exported workflow evidence into $OUTPUT_ROOT"
