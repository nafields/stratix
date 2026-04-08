#!/usr/bin/env bash
# sync_webrtc.sh — Fetch Google WebRTC source using depot_tools.
#
# Prerequisites:
#   - depot_tools on PATH (https://chromium.googlesource.com/chromium/tools/depot_tools)
#   - Xcode.app installed and selected: xcode-select -s /Applications/Xcode.app
#   - ~10 GB free disk space
#
# Usage:
#   WEBRTC_SRC_DIR=/path/to/src ./sync_webrtc.sh
#
# After this runs, the WebRTC source is at $SRC_DIR.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_DIR="${WEBRTC_SRC_DIR:-$ROOT_DIR/.cache/webrtc/src}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-$ROOT_DIR/.cache/depot_tools}"

echo "[sync_webrtc] ROOT_DIR=$ROOT_DIR"
echo "[sync_webrtc] SRC_DIR=$SRC_DIR"

# --- Install depot_tools if not present ---
if [ ! -d "$DEPOT_TOOLS_DIR" ]; then
    echo "[sync_webrtc] Cloning depot_tools..."
    git clone --depth=1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
fi
export PATH="$DEPOT_TOOLS_DIR:$PATH"

# --- Fetch WebRTC source (iOS target — we patch for tvOS afterwards) ---
mkdir -p "$SRC_DIR"
cd "$SRC_DIR"

if [ ! -f "$SRC_DIR/.gclient" ]; then
    echo "[sync_webrtc] Configuring gclient for iOS WebRTC..."
    cat > "$SRC_DIR/.gclient" <<GCLIENT
solutions = [
  {
    "name": "src",
    "url": "https://webrtc.googlesource.com/src.git",
    "managed": False,
    "custom_deps": {},
    "deps_file": "DEPS",
  },
]
target_os = ["ios", "mac"]
GCLIENT
fi

echo "[sync_webrtc] Running gclient sync (this takes a while)..."
gclient sync --with_branch_heads --with_tags -D

echo "[sync_webrtc] Done. Source at: $SRC_DIR/src"
