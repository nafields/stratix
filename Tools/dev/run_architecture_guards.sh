#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

guards=(
  Tools/ci/check_f1_f2_decomposition_floor.py
  Tools/ci/check_e5_hydration_boundary.py
  Tools/ci/check_f10_e11_library_state_boundary.py
  Tools/ci/check_f1_f3_no_umbrella_types.py
  Tools/ci/check_e11_shell_seam.py
  Tools/ci/check_f10_typed_ids.py
  Tools/ci/check_f10_e11_load_state_contract.py
  Tools/ci/check_e9_e11_stream_boundary.py
  Tools/ci/check_e1_off_main_helpers.py
  Tools/ci/check_e9_e10_runtime_metrics_boundary.py
  Tools/ci/check_e11_coordinator_composition.py
  Tools/ci/check_f8_e11_package_boundaries.py
  Tools/ci/check_f10_typed_id_completion.py
  Tools/ci/check_f8_package_platform_audit.py
  Tools/ci/check_e1_e8_concurrency_exceptions.py
)

if [[ -f Tools/ci/check_e5_hydration_metadata.py ]]; then
  guards+=(Tools/ci/check_e5_hydration_metadata.py)
fi

for guard in "${guards[@]}"; do
  echo "python3 $guard"
  python3 "$guard"
done
