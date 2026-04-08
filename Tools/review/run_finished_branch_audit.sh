#!/usr/bin/env bash
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' was not found in PATH." >&2
    exit 1
  fi
}

for cmd in bash date git mkdir python3 sed tr; do
  require_command "$cmd"
done

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Error: run this inside the stratix repo." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

ARCHIVE_ROOT="$REPO_ROOT/Docs/archive/reviews/2026-03-28"
REVIEW_ROOT="$ARCHIVE_ROOT/review_artifacts"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
OUT_DIR="$REVIEW_ROOT/${TIMESTAMP}_finished_branch_audit"
LANE_DIR="$OUT_DIR/lanes"
LANE_STATUS_DIR="$OUT_DIR/lane_status"
VALIDATION_SUMMARY_PATH="$OUT_DIR/04_validation_summary.md"

mkdir -p "$LANE_DIR" "$LANE_STATUS_DIR"

SUMMARY="$OUT_DIR/00_summary.md"
LANE_MATRIX="$OUT_DIR/01_lane_matrix.md"
GOAL_MATRIX="$OUT_DIR/02_goal_matrix.md"
LANE_RESULTS="$OUT_DIR/03_lane_results.tsv"

safe_slug() {
  printf '%s' "$1" | tr ' /:' '___' | tr -cd '[:alnum:]_.-'
}

lane_log_path() {
  local id="$1"
  local label="$2"
  printf '%s/%s_%s.log' "$LANE_DIR" "$id" "$(safe_slug "$label")"
}

lane_meta_path() {
  local id="$1"
  local label="$2"
  printf '%s/%s_%s.meta' "$LANE_STATUS_DIR" "$id" "$(safe_slug "$label")"
}

lane_status_path() {
  local id="$1"
  local label="$2"
  printf '%s/%s_%s.status' "$LANE_STATUS_DIR" "$id" "$(safe_slug "$label")"
}

run_lane() {
  local id="$1"
  local category="$2"
  local label="$3"
  local cmd="$4"
  local log_path meta_path status_path start_ts end_ts status

  log_path="$(lane_log_path "$id" "$label")"
  meta_path="$(lane_meta_path "$id" "$label")"
  status_path="$(lane_status_path "$id" "$label")"
  start_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  {
    echo "lane_id=$id"
    echo "category=$category"
    echo "label=$label"
    echo "cwd=$REPO_ROOT"
    echo "command=$cmd"
    echo "started_at=$start_ts"
    echo
    echo "\$ $cmd"
    echo
  } > "$log_path"

  bash -lc "cd \"$REPO_ROOT\" && export PATH=\"$PATH\" && $cmd" >> "$log_path" 2>&1
  status=$?
  end_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  {
    echo "lane_id=$id"
    echo "category=$category"
    echo "label=$label"
    echo "status=$status"
    echo "cwd=$REPO_ROOT"
    echo "command=$cmd"
    echo "log_path=$log_path"
    echo "started_at=$start_ts"
    echo "finished_at=$end_ts"
  } > "$meta_path"
  printf '%s\n' "$status" > "$status_path"
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$category" "$label" "$status" "$log_path" >> "$LANE_RESULTS"
}

lane_status() {
  local id="$1"
  local label="$2"
  cat "$(lane_status_path "$id" "$label")"
}

lane_status_word() {
  local status="$1"
  if [[ "$status" == "0" ]]; then
    printf 'PASS'
  else
    printf 'FAIL'
  fi
}

lane_evidence_path() {
  lane_log_path "$1" "$2"
}

all_lanes_pass() {
  local pair id label status
  for pair in "$@"; do
    id="${pair%%::*}"
    label="${pair#*::}"
    status="$(lane_status "$id" "$label")"
    if [[ "$status" != "0" ]]; then
      return 1
    fi
  done
  return 0
}

write_goal_row() {
  local stage="$1"
  local goal="$2"
  shift 2

  local pair id label status evidence refs ref
  refs=""
  evidence=""
  for pair in "$@"; do
    id="${pair%%::*}"
    label="${pair#*::}"
    status="$(lane_status "$id" "$label")"
    ref="$id ($(lane_status_word "$status"))"
    if [[ -n "$refs" ]]; then
      refs="$refs, "
      evidence="$evidence; "
    fi
    refs="$refs$ref"
    evidence="$evidence$(lane_evidence_path "$id" "$label")"
  done

  if all_lanes_pass "$@"; then
    printf '| %s | %s | PASS | %s | %s |\n' "$stage" "$goal" "$refs" "$evidence" >> "$GOAL_MATRIX"
  else
    printf '| %s | %s | FAIL | %s | %s |\n' "$stage" "$goal" "$refs" "$evidence" >> "$GOAL_MATRIX"
  fi
}

{
  echo -e "lane_id\tcategory\tlabel\texit_status\tlog_path"
} > "$LANE_RESULTS"

run_lane "01" "guard" "F1/F2 Decomposition Floor" "python3 Tools/ci/check_f1_f2_decomposition_floor.py"
run_lane "02" "guard" "E5 Hydration Boundary" "python3 Tools/ci/check_e5_hydration_boundary.py"
run_lane "03" "guard" "F10/E11 Library State Boundary" "python3 Tools/ci/check_f10_e11_library_state_boundary.py"
run_lane "03a" "guard" "E5 Hydration Metadata" "python3 Tools/ci/check_e5_hydration_metadata.py"
run_lane "04" "guard" "F1/F3 No Umbrella Types" "python3 Tools/ci/check_f1_f3_no_umbrella_types.py"
run_lane "05" "guard" "E11 Shell Seam" "python3 Tools/ci/check_e11_shell_seam.py"
run_lane "06" "guard" "F10 Typed IDs" "python3 Tools/ci/check_f10_typed_ids.py"
run_lane "07" "guard" "F10/E11 Load State Contract" "python3 Tools/ci/check_f10_e11_load_state_contract.py"
run_lane "08" "guard" "E9/E11 Stream Boundary" "python3 Tools/ci/check_e9_e11_stream_boundary.py"
run_lane "09" "guard" "E1 Off-Main Helpers" "python3 Tools/ci/check_e1_off_main_helpers.py"
run_lane "10" "guard" "E9/E10 Runtime Metrics Boundary" "python3 Tools/ci/check_e9_e10_runtime_metrics_boundary.py"
run_lane "12" "guard" "E11 Coordinator Composition" "python3 Tools/ci/check_e11_coordinator_composition.py"
run_lane "14" "guard" "F8/E11 Package Boundaries" "python3 Tools/ci/check_f8_e11_package_boundaries.py"
run_lane "15" "guard" "F10 Typed ID Completion" "python3 Tools/ci/check_f10_typed_id_completion.py"
run_lane "17" "guard" "F8 Package Platform Audit" "python3 Tools/ci/check_f8_package_platform_audit.py"
run_lane "18" "guard" "Docs Truth Sync" "python3 Tools/ci/check_docs_truth_sync.py"
run_lane "19" "guard" "E1/E8 Concurrency Exceptions" "python3 Tools/ci/check_e1_e8_concurrency_exceptions.py"
run_lane "20" "guard" "Repo Hygiene" "python3 Tools/ci/check_repo_hygiene.py"
run_lane "20a" "guard" "All Contracts" "python3 Tools/ci/check_floor_and_execution_contracts.py"

run_lane "21" "package" "StratixModels Tests" "swift test --package-path Packages/StratixModels"
run_lane "22" "package" "DiagnosticsKit Tests" "swift test --package-path Packages/DiagnosticsKit"
run_lane "23" "package" "DesignSystemTV Tests" "swift test --package-path Packages/DesignSystemTV"
run_lane "24" "package" "InputBridge Tests" "swift test --package-path Packages/InputBridge"
run_lane "25" "package" "XCloudAPI Tests" "swift test --package-path Packages/XCloudAPI"
run_lane "26" "package" "StreamingCore Tests" "swift test --package-path Packages/StreamingCore"
run_lane "27" "package" "VideoRenderingKit Tests" "swift test --package-path Packages/VideoRenderingKit"
run_lane "28" "package" "StratixCore Tests" "swift test --package-path Packages/StratixCore"

run_lane "29" "xcode" "Stratix-Debug Build" "xcodebuild -workspace Stratix.xcworkspace -scheme Stratix-Debug -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' -derivedDataPath /tmp/approval_debug_build -clonedSourcePackagesDirPath /tmp/approval_debug_build_spm build"
run_lane "30" "xcode" "App Smoke Tests" "xcodebuild -workspace Stratix.xcworkspace -scheme Stratix-Debug -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' -derivedDataPath /tmp/approval_app_smoke -clonedSourcePackagesDirPath /tmp/approval_app_smoke_spm -only-testing:StratixTests/AppSmokeTests test"
run_lane "31" "xcode" "Runtime Safety Tests" "xcodebuild -workspace Stratix.xcworkspace -scheme Stratix-Debug -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' -derivedDataPath /tmp/approval_runtime_safety -clonedSourcePackagesDirPath /tmp/approval_runtime_safety_spm -only-testing:StratixTests/WebRTCClientImplSafetyTests test"
run_lane "32" "xcode" "Shell UI Simulator Tests" "xcodebuild -workspace Stratix.xcworkspace -scheme Stratix-ShellUI -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' -derivedDataPath /tmp/approval_shell_ui -clonedSourcePackagesDirPath /tmp/approval_shell_ui_spm -only-testing:StratixUITests/ShellCheckpointUITests/testShellNavigationCheckpoints -only-testing:StratixUITests/ShellCheckpointUITests/testNoSceneBleedAcrossDestinationSwitches test"
run_lane "33" "xcode" "Perf Plan Tests" "xcodebuild -workspace Stratix.xcworkspace -scheme Stratix-Perf -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' -derivedDataPath /tmp/approval_perf -clonedSourcePackagesDirPath /tmp/approval_perf_spm test"
run_lane "34" "xcode" "Metal Profile Tests" "xcodebuild -workspace Stratix.xcworkspace -scheme Stratix-MetalProfile -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' -derivedDataPath /tmp/approval_metal_profile -clonedSourcePackagesDirPath /tmp/approval_metal_profile_spm test"
run_lane "35" "xcode" "Release Run Build" "xcodebuild -workspace Stratix.xcworkspace -scheme Stratix-ReleaseRun -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' -derivedDataPath /tmp/approval_release_run -clonedSourcePackagesDirPath /tmp/approval_release_run_spm build"
run_lane "36" "xcode" "Stratix Validation Tests" "xcodebuild -workspace Stratix.xcworkspace -scheme Stratix-Validation -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' -derivedDataPath /tmp/approval_validation -clonedSourcePackagesDirPath /tmp/approval_validation_spm test"
run_lane "37" "script" "Hardware Shell Checks" "bash Tools/dev/run_hardware_shell_checks.sh"

run_lane "38" "script" "Production Hardening Checks" "bash Tools/test/run_production_hardening_checks.sh"
run_lane "38a" "script" "Shell State Tests" "bash Tools/dev/run_shell_state_tests.sh"
run_lane "39" "script" "Hardware Profile Capture" "bash Tools/perf/run_hardware_profile_capture.sh"
run_lane "40" "script" "Validation Summary Generation" "bash Tools/docs/generate_validation_summary.sh '$OUT_DIR' '$VALIDATION_SUMMARY_PATH'"

{
  echo "# Finished Branch Audit"
  echo
  echo "- Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "- Repo root: \`$REPO_ROOT\`"
  echo "- Audit output: \`$OUT_DIR\`"
  echo "- Validation summary: \`$VALIDATION_SUMMARY_PATH\`"
  echo "- Hosted workflow exports: run \`bash Tools/docs/export_workflow_exports.sh <workflow_export_root> --sha \"\$(git rev-parse HEAD)\"\` only after \`CI PR Fast Guards\`, \`CI Packages\`, \`CI App Build And Smoke\`, \`CI Runtime Safety\`, \`CI Shell UI\`, \`CI Shell State Tests\`, \`CI Release And Validation\`, and \`CI Hardware Device\` have all passed on this same SHA."
  echo
  echo "## Lane Results"
  echo
  echo "| Lane | Category | Result | Command | Evidence |"
  echo "| --- | --- | --- | --- | --- |"
} > "$SUMMARY"

{
  echo "# Validation Lane Matrix"
  echo
  echo "| Lane | Category | Label | Result | Evidence |"
  echo "| --- | --- | --- | --- | --- |"
} > "$LANE_MATRIX"

while IFS=$'\t' read -r id category label exit_status log_path; do
  [[ "$id" == "lane_id" ]] && continue
  result_word="$(lane_status_word "$exit_status")"
  meta_path="$(lane_meta_path "$id" "$label")"
  command_line="$(sed -n '6p' "$meta_path" | sed 's/^command=//')"
  printf '| %s | %s | %s | `%s` | `%s` |\n' "$id" "$category" "$label" "$result_word" "$log_path" >> "$LANE_MATRIX"
  printf '| %s | %s | %s | `%s` | `%s` |\n' "$id" "$category" "$result_word" "$command_line" "$log_path" >> "$SUMMARY"
done < "$LANE_RESULTS"

{
  echo
  echo "## Failing Lanes"
  echo
} >> "$SUMMARY"

failing_count=0
while IFS=$'\t' read -r id category label exit_status log_path; do
  [[ "$id" == "lane_id" ]] && continue
  if [[ "$exit_status" != "0" ]]; then
    meta_path="$(lane_meta_path "$id" "$label")"
    command_line="$(sed -n '6p' "$meta_path" | sed 's/^command=//')"
    echo "- Lane $id ($category) $label" >> "$SUMMARY"
    echo "  command: \`$command_line\`" >> "$SUMMARY"
    echo "  evidence: \`$log_path\`" >> "$SUMMARY"
    failing_count=$((failing_count + 1))
  fi
done < "$LANE_RESULTS"

if [[ "$failing_count" == "0" ]]; then
  echo "- None" >> "$SUMMARY"
fi

{
  echo
  echo "## Goal Matrix"
  echo
  echo "Generated only from executed lane results. A goal row passes only if every mapped lane passed."
  echo
  echo "| Stage | Goal | Result | Required Lanes | Evidence |"
  echo "| --- | --- | --- | --- | --- |"
} > "$GOAL_MATRIX"

write_goal_row "Stage 1" "G01 Break up giant domain files" \
  "01::Stage 1 Decomposition Floor" "21::StratixModels Tests" "29::Stratix-Debug Build" "38::Production Hardening Checks"
write_goal_row "Stage 7" "G02 AppCoordinator composition-only" \
  "12::Stage 7 Coordinator Composition" "13::Stage 7 Dependency Seams" "14::Stage 7 Package Boundaries" "28::StratixCore Tests" "29::Stratix-Debug Build" "36::Stratix Validation Tests"
write_goal_row "Stage 5" "G03 Move heavy logic off @MainActor" \
  "09::Stage 5 Off Main Helpers" "10::Stage 6 Runtime Boundary" "19::Concurrency Exceptions" "28::StratixCore Tests" "31::Runtime Safety Tests"
write_goal_row "Stage 2" "G04 Hydration subsystem boundary" \
  "02::Stage 2 Hydration Boundary" "28::StratixCore Tests" "36::Stratix Validation Tests"
write_goal_row "Stage 3" "G05 Canonical immutable domain state" \
  "03::Stage 3 Library State Boundary" "28::StratixCore Tests" "36::Stratix Validation Tests"
write_goal_row "Stage 4" "G06 Reduce environment/controller sprawl" \
  "04::Stage 4 No Umbrella Types" "05::Stage 4 Shell Seam" "30::App Smoke Tests" "32::Shell UI Simulator Tests"
write_goal_row "Stage 4" "G07 Separate render state from navigation/focus/runtime side effects" \
  "04::Stage 4 No Umbrella Types" "05::Stage 4 Shell Seam" "07::Stage 4 Load State Contract" "30::App Smoke Tests" "32::Shell UI Simulator Tests"
write_goal_row "Stage 4" "G08 Explicit stale-while-revalidate UI states" \
  "07::Stage 4 Load State Contract" "30::App Smoke Tests" "32::Shell UI Simulator Tests"
write_goal_row "Stage 3" "G09 Explicit hydration publish priorities" \
  "03::Stage 3 Library State Boundary" "28::StratixCore Tests" "36::Stratix Validation Tests"
write_goal_row "Stage 3" "G10 Integrity metadata on hydrated snapshots" \
  "03::Stage 3 Library State Boundary" "03a::Stage 3 Hydration Metadata" "28::StratixCore Tests" "36::Stratix Validation Tests"
write_goal_row "Stage 5" "G11 Stream runtime split from UI controller" \
  "08::Stage 5 Stream Split" "09::Stage 5 Off Main Helpers" "10::Stage 6 Runtime Boundary" "28::StratixCore Tests" "31::Runtime Safety Tests"
write_goal_row "Stage 6" "G12 Break up WebRTCClientImpl.swift" \
  "10::Stage 6 Runtime Boundary" "11::Stage 6 Metrics Pipeline" "31::Runtime Safety Tests" "34::Metal Profile Tests"
write_goal_row "Stage 5" "G13 Extract explicit stream policy objects" \
  "08::Stage 5 Stream Split" "09::Stage 5 Off Main Helpers" "28::StratixCore Tests" "31::Runtime Safety Tests"
write_goal_row "Stage 6" "G14 Streaming metrics pipeline" \
  "11::Stage 6 Metrics Pipeline" "22::DiagnosticsKit Tests" "26::StreamingCore Tests" "27::VideoRenderingKit Tests" "34::Metal Profile Tests"
write_goal_row "Stage 8" "G15 Revisit package platform minimums carefully" \
  "17::Stage 8 Package Platform Audit" "21::StratixModels Tests" "22::DiagnosticsKit Tests" "23::DesignSystemTV Tests" "24::InputBridge Tests" "25::XCloudAPI Tests" "26::StreamingCore Tests" "27::VideoRenderingKit Tests" "28::StratixCore Tests"
write_goal_row "Stage 7" "G16 Sharpen package boundaries" \
  "13::Stage 7 Dependency Seams" "14::Stage 7 Package Boundaries" "21::StratixModels Tests" "22::DiagnosticsKit Tests" "23::DesignSystemTV Tests" "24::InputBridge Tests" "25::XCloudAPI Tests" "26::StreamingCore Tests" "27::VideoRenderingKit Tests" "28::StratixCore Tests"
write_goal_row "Stage 7" "G17 Enforced architecture rules" \
  "12::Stage 7 Coordinator Composition" "13::Stage 7 Dependency Seams" "14::Stage 7 Package Boundaries" "18::Docs Truth Sync" "19::Concurrency Exceptions" "20::Repo Hygiene"
write_goal_row "Stage 8" "G18 Improve hydration/runtime/focus transition testing" \
  "18::Docs Truth Sync" "28::StratixCore Tests" "30::App Smoke Tests" "31::Runtime Safety Tests" "32::Shell UI Simulator Tests" "33::Perf Plan Tests" "34::Metal Profile Tests" "36::Stratix Validation Tests" "37::Hardware Shell Checks" "38a::Shell State Tests" "39::Hardware Profile Capture"
write_goal_row "Stage 8" "G19 Strong typed identifiers" \
  "06::Stage 4 Typed IDs" "15::Stage 8 Typed ID Completion" "28::StratixCore Tests" "29::Stratix-Debug Build" "30::App Smoke Tests" "36::Stratix Validation Tests"
write_goal_row "Stage 8" "G20 Immutable state plus reducers / explicit transitions" \
  "03::Stage 3 Library State Boundary" "15::Stage 8 Typed ID Completion" "28::StratixCore Tests" "36::Stratix Validation Tests"

{
  echo
  echo "## Outputs"
  echo
  echo "- Lane matrix: \`$LANE_MATRIX\`"
  echo "- Goal matrix: \`$GOAL_MATRIX\`"
  echo "- Lane results TSV: \`$LANE_RESULTS\`"
  echo
  echo "## Release Bundle Follow-up"
  echo
  echo "This audit is current-head local proof. It does not dispatch or wait for hosted GitHub Actions workflows."
  echo
  echo "Before treating a public release candidate as approval-ready:"
  echo
  echo "- collect hosted workflow evidence for the same commit with \`bash Tools/docs/export_workflow_exports.sh <workflow_export_root> --sha \"\$(git rev-parse HEAD)\"\` only after all eight required hosted workflows have passed on this same commit"
  echo "- generate the tagged release bundle with \`bash Tools/docs/generate_release_bundle.sh <tag> \"$OUT_DIR\" <fresh_profile_root> <workflow_export_root>\`"
} >> "$SUMMARY"

echo "Audit written to: $OUT_DIR"
echo "Summary: $SUMMARY"
echo "Lane matrix: $LANE_MATRIX"
echo "Goal matrix: $GOAL_MATRIX"
echo "Next release step: collect hosted workflow exports for this same commit with Tools/docs/export_workflow_exports.sh"
echo "Next bundle step: generate the tagged release bundle with Tools/docs/generate_release_bundle.sh"
