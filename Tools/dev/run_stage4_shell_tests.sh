#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

xcodebuild -quiet \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-Debug \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
  -derivedDataPath /tmp/stratix_stage4_shell \
  -clonedSourcePackagesDirPath /tmp/stratix_stage4_shell_spm \
  -only-testing:StratixTests/CloudLibraryStateSnapshotTests \
  -only-testing:StratixTests/CloudLibraryLoadStateTests \
  -only-testing:StratixTests/CloudLibraryRouteStateTests \
  -only-testing:StratixTests/CloudLibraryFocusStateTests \
  -only-testing:StratixTests/CloudLibraryBackActionPolicyTests \
  -only-testing:StratixTests/CloudLibraryShellHostActionTests \
  -only-testing:StratixTests/CloudLibraryRoutePresentationBuilderTests \
  -only-testing:StratixTests/CloudLibraryShellHostTests \
  test
