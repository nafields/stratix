#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DESTINATION='platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest'

run_shell_ui_case() {
  local derived_data_root="$1"
  local cloned_spm_root="$2"
  local test_identifier="$3"

  xcodebuild -quiet \
    -workspace Stratix.xcworkspace \
    -scheme Stratix-ShellUI \
    -destination "$DESTINATION" \
    -derivedDataPath "$derived_data_root" \
    -clonedSourcePackagesDirPath "$cloned_spm_root" \
    -only-testing:"$test_identifier" \
    test
}

# These UI tests are stable in isolation but can become flaky when the simulator
# relaunches between unrelated shell routes inside a single xcodebuild session.
# Keep the proof surface deterministic by isolating each checkpoint.
run_shell_ui_case \
  /tmp/stratix_shell_checkpoints_nav \
  /tmp/stratix_shell_checkpoints_nav_spm \
  StratixUITests/ShellCheckpointUITests/testShellNavigationCheckpoints

run_shell_ui_case \
  /tmp/stratix_shell_checkpoints_scene_bleed \
  /tmp/stratix_shell_checkpoints_scene_bleed_spm \
  StratixUITests/ShellCheckpointUITests/testNoSceneBleedAcrossDestinationSwitches
