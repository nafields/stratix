#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

xcodebuild \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-Validation \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/stratix_validation_lane \
  -clonedSourcePackagesDirPath /tmp/stratix_validation_lane_spm \
  test
