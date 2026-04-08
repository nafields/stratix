#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

xcodebuild \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-ReleaseRun \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/stratix_release_run \
  -clonedSourcePackagesDirPath /tmp/stratix_release_run_spm \
  build
