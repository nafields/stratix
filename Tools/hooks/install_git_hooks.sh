#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

git config core.hooksPath Tools/hooks
chmod +x Tools/hooks/pre-commit Tools/hooks/pre-push
chmod +x Tools/dev/*.sh
chmod +x Tools/docs/*.sh
chmod +x Tools/test/run_shell_visual_regression.sh

echo "Configured git hooks to use Tools/hooks"
