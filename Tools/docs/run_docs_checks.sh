#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

python3 Tools/ci/check_docs_portability.py
python3 Tools/ci/check_docs_truth_sync.py
python3 Tools/ci/check_repo_hygiene.py
