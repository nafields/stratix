#!/usr/bin/env bash
# build_webrtc_tvos.sh — Build WebRTC for tvOS device (arm64) and simulator (arm64 only).
#
# Note: x86_64 simulator is intentionally skipped. WebRTC's GN toolchain for x64 simulator
# uses ios_clang_x64 which stamps NASM objects as "iOS Simulator" platform, causing the
# tvOS Simulator linker to reject them (platform mismatch). Apple Silicon Macs run
# arm64 simulator natively so x86_64 is not needed.
#
# Prerequisites:
#   - Run sync_webrtc.sh first to fetch source
#   - depot_tools on PATH
#   - Xcode.app selected via xcode-select
#
# Output:
#   $OUT_DIR/tvos_arm64/      — device framework
#   $OUT_DIR/tvos_sim_arm64/  — simulator arm64 (Apple Silicon host)
#
# Usage:
#   WEBRTC_SRC_DIR=/path/to/webrtc/src ./build_webrtc_tvos.sh
#   (also accepts WEBRTC_SRC_DIR=/path/to/webrtc/src/src)
#   WEBRTC_REFRESH_BEFORE_PATCHES=0 ./build_webrtc_tvos.sh   # skip pre-patch reset
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEBRTC_SRC_BASE="${WEBRTC_SRC_DIR:-$ROOT_DIR/.cache/webrtc/src}"
if [ -d "$WEBRTC_SRC_BASE/src" ] && [ -f "$WEBRTC_SRC_BASE/.gclient" ]; then
    SRC_DIR="$WEBRTC_SRC_BASE/src"
elif [ -d "$WEBRTC_SRC_BASE/build" ] && [ -f "$WEBRTC_SRC_BASE/DEPS" ]; then
    # Caller already passed the checkout root (contains BUILD.gn/DEPS).
    SRC_DIR="$WEBRTC_SRC_BASE"
else
    echo "[build_webrtc] ERROR: could not locate WebRTC checkout under WEBRTC_SRC_DIR=$WEBRTC_SRC_BASE" >&2
    echo "[build_webrtc] Expected either <dir>/.gclient + <dir>/src/ or direct checkout root with DEPS/build/." >&2
    exit 1
fi
OUT_DIR="${WEBRTC_OUT_DIR:-$ROOT_DIR/.cache/webrtc/out}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-$ROOT_DIR/.cache/depot_tools}"
PATCHES_DIR="$SCRIPT_DIR/patches"
WEBRTC_REFRESH_BEFORE_PATCHES="${WEBRTC_REFRESH_BEFORE_PATCHES:-1}"

# depot_tools must be on PATH for gclient helpers, but we invoke gn and ninja
# via their wrapper scripts directly to avoid the autoninja/siso indirection.
export PATH="$DEPOT_TOOLS_DIR:$PATH"

# gn and ninja are both bundled in the source tree.
# We invoke ninja directly to avoid the autoninja/Siso cloud-build indirection
# (autoninja now defaults to Siso which requires a Google build account).
GN="$SRC_DIR/buildtools/mac/gn"
NINJA="$SRC_DIR/third_party/ninja/ninja"

echo "[build_webrtc] SRC_DIR=$SRC_DIR"
echo "[build_webrtc] OUT_DIR=$OUT_DIR"

refresh_checkout_before_patching() {
    local refresh_flag_lower
    refresh_flag_lower="$(echo "$WEBRTC_REFRESH_BEFORE_PATCHES" | tr '[:upper:]' '[:lower:]')"

    case "$refresh_flag_lower" in
        0|false|no)
            echo "[build_webrtc] Skipping source refresh before patching (WEBRTC_REFRESH_BEFORE_PATCHES=$WEBRTC_REFRESH_BEFORE_PATCHES)"
            return
            ;;
    esac

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[build_webrtc] ERROR: $SRC_DIR is not a git checkout; cannot refresh before patching." >&2
        exit 1
    fi

    echo "[build_webrtc] Refreshing source checkout before patching..."
    if git diff --quiet && git diff --cached --quiet; then
        echo "  source tree already clean"
        return
    fi

    git reset --hard HEAD >/dev/null
    echo "  reset tracked local changes to HEAD"
}

apply_patch_file() {
    local patch="$1"
    local patch_name
    patch_name="$(basename "$patch")"

    if [ "$patch_name" = "0005-tvos-remove-use-blink-assertion.patch" ]; then
        # Newer/previously-patched trees may already have this assertion removed.
        if [ ! -f "$SRC_DIR/build/config/apple/mobile_config.gni" ]; then
            echo "  skipped (upstream no longer has build/config/apple/mobile_config.gni)"
            return
        fi
        if ! grep -Fq 'assert(use_blink, "tvOS builds require use_blink=true")' "$SRC_DIR/build/config/apple/mobile_config.gni"; then
            echo "  already applied (tvOS use_blink assertion not present)"
            return
        fi
    fi

    if git apply --ignore-whitespace --check "$patch" 2>/dev/null; then
        git apply --ignore-whitespace "$patch"
        echo "  applied"
        return
    fi

    # Already applied is acceptable (idempotent behavior).
    if git apply --ignore-whitespace --reverse --check "$patch" 2>/dev/null; then
        echo "  already applied"
        return
    fi

    echo "  ERROR: failed to apply $(basename "$patch") and it does not appear to be already applied" >&2
    echo "  Hint: WebRTC upstream likely changed; refresh this patch in Tools/webrtc-build/patches/." >&2
    exit 1
}

# --- Apply tvOS patches ---
echo "[build_webrtc] Applying tvOS patches..."
cd "$SRC_DIR"
refresh_checkout_before_patching

for patch in "$PATCHES_DIR"/*.patch; do
    echo "  Applying: $(basename "$patch")"
    apply_patch_file "$patch"
done

# --- GN args common to all tvOS targets ---
# Key decisions (see ADR-0002 and research):
#   target_os="ios"                   — GN uses "ios" for all Apple mobile targets
#   target_platform="tvos"            — Selects tvOS SDK (appletvos/appletvsimulator)
#   target_environment="device"       — GN env values: "device" or "simulator" (NOT SDK names)
#   (rtc_use_metal_rendering omitted) — obsolete/unused in current WebRTC GN args
#   (use_goma omitted)                — removed from WebRTC; ninja invoked directly
#   rtc_libvpx_build_vp9=false        — Reduces build size; app uses H264
#   enable_ios_bitcode                — removed; no longer in WebRTC build system (Xcode 14+)
#   is_debug=false                    — Release build for framework
#   use_rtti=true                     — Required for some ObjC++ bridge code
#   use_blink=true                    — Satisfies upstream tvOS GN assertion in mobile_config.gni
#                                       (assertion removed by patch 0005, kept for safety)

GN_ARGS_BASE='
  target_os="ios"
  target_platform="tvos"
  ios_deployment_target="17.0"
  is_debug=false
  rtc_enable_protobuf=false
  rtc_use_h264=true
  rtc_libvpx_build_vp9=false
  ios_enable_code_signing=false
  use_rtti=true
  rtc_enable_objc_symbol_export=true
  use_blink=true
'
# Note: target_platform="tvos" uses target_environment="device"/"simulator"
# (NOT "appletvos"/"appletvsimulator" — those are SDK names, not GN env values).
# Keep use_blink=true as a compatibility guard for upstream tvOS GN assertion checks.
#
# rtc_enable_objc_symbol_export=true: Required so ObjC class symbols (RTCConfiguration,
# RTCPeerConnectionFactory, etc.) are exported from the dylib with default visibility.
# Without this flag, RTC_OBJC_EXPORT expands to empty and all symbols are hidden.

# --- Build: tvOS device (arm64) ---
echo "[build_webrtc] Configuring tvOS device (arm64)..."
mkdir -p "$OUT_DIR/tvos_arm64"
$GN gen "$OUT_DIR/tvos_arm64" --args="$GN_ARGS_BASE target_cpu=\"arm64\" target_environment=\"device\""
echo "[build_webrtc] Building tvOS device (arm64)..."
"$NINJA" -C "$OUT_DIR/tvos_arm64" framework_objc

# x86_64 simulator is intentionally skipped — see header comment for why.

# --- Build: tvOS simulator arm64 (Apple Silicon Macs) ---
echo "[build_webrtc] Configuring tvOS simulator (arm64)..."
mkdir -p "$OUT_DIR/tvos_sim_arm64"
$GN gen "$OUT_DIR/tvos_sim_arm64" --args="$GN_ARGS_BASE target_cpu=\"arm64\" target_environment=\"simulator\""
echo "[build_webrtc] Building tvOS simulator (arm64)..."
"$NINJA" -C "$OUT_DIR/tvos_sim_arm64" framework_objc

echo "[build_webrtc] All builds complete. Run package_xcframework.sh to create WebRTC.xcframework"
