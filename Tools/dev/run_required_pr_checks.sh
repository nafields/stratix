#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

bash Tools/dev/run_pre_push_checks.sh
bash Tools/dev/run_app_smoke.sh
bash Tools/dev/run_runtime_safety.sh
bash Tools/dev/run_shell_ui_checks.sh
bash Tools/dev/run_stage4_shell_tests.sh
bash Tools/test/run_shell_regression_checks.sh
bash Tools/test/run_production_hardening_checks.sh
