#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DESTINATION="${DESTINATION:-platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/stratix_shell_visual_regression_$$}"
CLONED_SOURCE_PACKAGES_DIR_PATH="${CLONED_SOURCE_PACKAGES_DIR_PATH:-/tmp/stratix_shell_visual_regression_spm_$$}"
CAPTURE_DIR="${CAPTURE_DIR:-/tmp/stratix-shell-checkpoints-$$}"
DIFF_DIR="${DIFF_DIR:-/tmp/stratix-shell-checkpoints-diff-$$}"
REFERENCE_DIR="${REFERENCE_DIR:-$REPO_ROOT/Apps/Stratix/Tools/shell-visual-regression/reference}"
MIN_SSIM="${MIN_SSIM:-0.93}"

command -v ffmpeg >/dev/null 2>&1 || {
  echo "ffmpeg is required for shell visual regression"
  exit 1
}

mkdir -p "$CAPTURE_DIR" "$DIFF_DIR"
rm -f "$CAPTURE_DIR"/home.png "$CAPTURE_DIR"/search.png "$CAPTURE_DIR"/library.png
rm -rf "$DERIVED_DATA_PATH" "$CLONED_SOURCE_PACKAGES_DIR_PATH"

resolve_newest_simulator_capture_dir() {
  local newest_home=""
  newest_home="$(find "$HOME/Library/Developer/CoreSimulator/Devices" -type f -path '*/Library/Caches/stratix-shell-checkpoints/home.png' -print 2>/dev/null | tail -n 1)"
  [[ -n "$newest_home" ]] || return 0
  dirname "$newest_home"
}

hydrate_capture_dir_from_simulator_cache() {
  [[ -f "$CAPTURE_DIR/home.png" && -f "$CAPTURE_DIR/search.png" && -f "$CAPTURE_DIR/library.png" ]] && return 0

  local newest_dir=""
  newest_dir="$(resolve_newest_simulator_capture_dir)"
  [[ -n "$newest_dir" ]] || return 0
  [[ -f "$newest_dir/home.png" && -f "$newest_dir/search.png" && -f "$newest_dir/library.png" ]] || return 0

  echo "Hydrating shell checkpoints from simulator cache: $newest_dir"
  cp "$newest_dir/home.png" "$CAPTURE_DIR/home.png"
  cp "$newest_dir/search.png" "$CAPTURE_DIR/search.png"
  cp "$newest_dir/library.png" "$CAPTURE_DIR/library.png"
}

effective_capture_dir() {
  if [[ -f "$CAPTURE_DIR/home.png" && -f "$CAPTURE_DIR/search.png" && -f "$CAPTURE_DIR/library.png" ]]; then
    echo "$CAPTURE_DIR"
    return 0
  fi

  local newest_dir=""
  newest_dir="$(resolve_newest_simulator_capture_dir)"
  if [[ -n "$newest_dir" && -f "$newest_dir/home.png" && -f "$newest_dir/search.png" && -f "$newest_dir/library.png" ]]; then
    echo "$newest_dir"
    return 0
  fi

  echo "$CAPTURE_DIR"
}

bash Tools/dev/run_shell_ui_checks.sh

STRATIX_CHECKPOINT_DIR="$CAPTURE_DIR" \
STRATIX_SHELL_CAPTURE_DIR="$CAPTURE_DIR" \
xcodebuild \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-ShellUI \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR_PATH" \
  -only-testing:StratixUITests/ShellCheckpointUITests/testCaptureHomeSearchLibraryCheckpoints \
  test

hydrate_capture_dir_from_simulator_cache

EFFECTIVE_CAPTURE_DIR="$(effective_capture_dir)"
echo "Using shell checkpoint capture dir: $EFFECTIVE_CAPTURE_DIR"

python3 "$REPO_ROOT/Apps/Stratix/Tools/shell-visual-regression/compare_checkpoints.py" \
  --reference-dir "$REFERENCE_DIR" \
  --capture-dir "$EFFECTIVE_CAPTURE_DIR" \
  --output-dir "$DIFF_DIR" \
  --min-ssim "$MIN_SSIM"

echo "Captured checkpoints: $CAPTURE_DIR"
echo "Diff/report output:   $DIFF_DIR"
