#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

git diff --check
bash Tools/dev/run_architecture_guards.sh
bash Tools/docs/run_docs_checks.sh
