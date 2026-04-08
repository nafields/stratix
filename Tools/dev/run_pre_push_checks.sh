#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

bash Tools/dev/run_pre_commit_checks.sh
bash Tools/dev/run_package_sweep.sh
bash Tools/dev/run_debug_build.sh
