#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

xcodebuild -quiet \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/stratix_runtime_safety \
  -clonedSourcePackagesDirPath /tmp/stratix_runtime_safety_spm \
  -only-testing:StratixTests/WebRTCClientImplSafetyTests \
  test
