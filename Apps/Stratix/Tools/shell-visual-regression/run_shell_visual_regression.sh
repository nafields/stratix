#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/Apps/Stratix/Stratix.xcodeproj"
SCHEME="Stratix"
DESTINATION="${DESTINATION:-platform=tvOS Simulator,name=Apple TV 4K (3rd generation)}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/StratixUITestsDerivedData}"
CAPTURE_DIR="${CAPTURE_DIR:-/tmp/stratix-shell-checkpoints}"
DIFF_DIR="${DIFF_DIR:-/tmp/stratix-shell-checkpoints-diff}"
REFERENCE_DIR="${1:-}"
MIN_SSIM="${MIN_SSIM:-0.93}"

if [[ -z "$REFERENCE_DIR" ]]; then
  echo "usage: $0 <reference-dir-with-home-search-library-png>"
  echo "example: $0 /Users/nicholas/Desktop/stratix/Apps/Stratix/Tools/shell-visual-regression/reference"
  exit 1
fi

mkdir -p "$CAPTURE_DIR" "$DIFF_DIR"
rm -f "$CAPTURE_DIR"/home.png "$CAPTURE_DIR"/search.png "$CAPTURE_DIR"/library.png

hydrate_capture_dir_from_simulator_cache() {
  [[ -f "$CAPTURE_DIR/home.png" && -f "$CAPTURE_DIR/search.png" && -f "$CAPTURE_DIR/library.png" ]] && return 0

  local newest_dir=""
  local newest_mtime=0
  local candidate_dir
  while IFS= read -r candidate_dir; do
    [[ -f "$candidate_dir/home.png" && -f "$candidate_dir/search.png" && -f "$candidate_dir/library.png" ]] || continue
    local candidate_mtime
    candidate_mtime="$(stat -f '%m' "$candidate_dir/home.png" 2>/dev/null || echo 0)"
    if [[ "$candidate_mtime" -gt "$newest_mtime" ]]; then
      newest_dir="$candidate_dir"
      newest_mtime="$candidate_mtime"
    fi
  done < <(find "$HOME/Library/Developer/CoreSimulator/Devices" -type d -path '*/Library/Caches/stratix-shell-checkpoints' 2>/dev/null)

  [[ -n "$newest_dir" ]] || return 0

  cp "$newest_dir/home.png" "$CAPTURE_DIR/home.png"
  cp "$newest_dir/search.png" "$CAPTURE_DIR/search.png"
  cp "$newest_dir/library.png" "$CAPTURE_DIR/library.png"
}

echo "Running UI checkpoint capture tests..."
STRATIX_CHECKPOINT_DIR="$CAPTURE_DIR" \
STRATIX_SHELL_CAPTURE_DIR="$CAPTURE_DIR" \
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:StratixUITests/ShellCheckpointUITests/testCaptureHomeSearchLibraryCheckpoints \
  test

hydrate_capture_dir_from_simulator_cache

echo "Comparing checkpoints..."
python3 "$PROJECT_ROOT/Apps/Stratix/Tools/shell-visual-regression/compare_checkpoints.py" \
  --reference-dir "$REFERENCE_DIR" \
  --capture-dir "$CAPTURE_DIR" \
  --output-dir "$DIFF_DIR" \
  --min-ssim "$MIN_SSIM"

echo "Done."
echo "Captured checkpoints: $CAPTURE_DIR"
echo "Diff/report output:   $DIFF_DIR"
