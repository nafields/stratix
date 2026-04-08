#!/usr/bin/env bash
# package_xcframework.sh — Combines tvOS and tvOS Simulator frameworks into WebRTC.xcframework.
#
# Run after build_webrtc_tvos.sh completes successfully.
#
# Output: ThirdParty/WebRTC/WebRTC.xcframework (ready to embed in Xcode)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${WEBRTC_OUT_DIR:-$ROOT_DIR/.cache/webrtc/out}"
DEST_DIR="$ROOT_DIR/ThirdParty/WebRTC"

DEVICE_FW="$OUT_DIR/tvos_arm64/WebRTC.framework"
SIM_ARM64_FW="$OUT_DIR/tvos_sim_arm64/WebRTC.framework"

# Note: x86_64 simulator slice is not included — WebRTC's GN ios_clang_x64 toolchain
# stamps NASM objects as "iOS Simulator", which the tvOS Simulator linker rejects.
# Apple Silicon Macs run arm64 simulator natively so x86_64 is not needed.

echo "[package_xcframework] Verifying build artifacts..."
for fw in "$DEVICE_FW" "$SIM_ARM64_FW"; do
    if [ ! -d "$fw" ]; then
        echo "ERROR: Missing framework: $fw"
        echo "Run build_webrtc_tvos.sh first."
        exit 1
    fi
done

# Verify tvOS slice is arm64
echo "[package_xcframework] Checking device slice..."
lipo -info "$DEVICE_FW/WebRTC" | grep -q "arm64" || { echo "ERROR: device framework missing arm64"; exit 1; }
echo "  Device: OK (arm64)"
echo "  Simulator: OK (arm64)"

# --- Create XCFramework ---
XCFW_DEST="$DEST_DIR/WebRTC.xcframework"
rm -rf "$XCFW_DEST"

xcodebuild -create-xcframework \
    -framework "$DEVICE_FW" \
    -framework "$SIM_ARM64_FW" \
    -output "$XCFW_DEST"

echo "[package_xcframework] WebRTC.xcframework created at: $XCFW_DEST"

# Verify slices
echo "[package_xcframework] Verifying xcframework slices..."
for slice_dir in "$XCFW_DEST"/*/; do
    fw=$(ls "$slice_dir"*.framework 2>/dev/null | head -1)
    if [ -n "$fw" ]; then
        echo "  Slice $(basename "$slice_dir"): $(lipo -info "$fw"/WebRTC 2>/dev/null || echo 'n/a')"
    fi
done

# --- Update version manifest ---
# Resolve SRC_DIR the same way build_webrtc_tvos.sh does.
_SRC_BASE="${WEBRTC_SRC_DIR:-$ROOT_DIR/.cache/webrtc/src}"
if [ -d "$_SRC_BASE/src" ]; then
    _SRC_DIR="$_SRC_BASE/src"
else
    _SRC_DIR="$_SRC_BASE"
fi
REVISION=$(git -C "$_SRC_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
PATCH_LIST_JSON="$(
    find "$ROOT_DIR/Tools/webrtc-build/patches" -maxdepth 1 -type f -name '*.patch' -print \
        | sort \
        | awk '
            BEGIN { first = 1 }
            {
                name = $0
                sub(".*/", "", name)
                if (!first) {
                    printf(",\n")
                }
                printf("    \"%s\"", name)
                first = 0
            }
        '
)"
cat > "$DEST_DIR/webrtc-version.json" <<JSON
{
  "source": "webrtc-googlesource",
  "revision": "$REVISION",
  "branch": "main",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "toolchain": "$(xcodebuild -version | head -1)",
  "patches": [
${PATCH_LIST_JSON}
  ]
}
JSON

echo "[package_xcframework] Done. Embed ThirdParty/WebRTC/WebRTC.xcframework in your Xcode project."
echo ""
echo "Xcode setup:"
echo "  1. Drag ThirdParty/WebRTC/WebRTC.xcframework into your project's Frameworks group"
echo "  2. Set 'Embed & Sign' for the tvOS app target"
echo "  3. Add a bridging header: #import <WebRTC/WebRTC.h>"
echo "  4. Enable SWIFT_OBJC_BRIDGING_HEADER in build settings"
