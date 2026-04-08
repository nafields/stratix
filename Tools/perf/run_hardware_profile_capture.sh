#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' was not found in PATH." >&2
    exit 1
  fi
}

for cmd in date git mkdir python3 xcodebuild xcrun; do
  require_command "$cmd"
done

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Error: run this inside the stratix repo." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

ARCHIVE_ROOT="$REPO_ROOT/Docs/archive/reviews/2026-03-28/runtime_profiles"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
OUTPUT_DIR="$ARCHIVE_ROOT/$TIMESTAMP"
DERIVED_DATA_PATH="/tmp/hardware_profile_capture_build"
CLONED_PACKAGES_PATH="/tmp/hardware_profile_capture_spm"
HARDWARE_DEVICE_ID="${HARDWARE_DEVICE_ID:-${TVOS_HARDWARE_DEVICE_ID:-}}"
HARDWARE_DEVICECTL_ID="${HARDWARE_DEVICECTL_ID:-${TVOS_HARDWARE_DEVICECTL_ID:-$HARDWARE_DEVICE_ID}}"
if [[ -z "$HARDWARE_DEVICE_ID" ]]; then
  echo "Error: set HARDWARE_DEVICE_ID or TVOS_HARDWARE_DEVICE_ID before running hardware profile capture." >&2
  exit 1
fi
BUNDLE_ID="${BUNDLE_ID:-com.stratix.appletv}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-appletvos/Stratix.app"

BUILD_LOG="$OUTPUT_DIR/build.log"
INSTALL_LOG="$OUTPUT_DIR/install.log"
LAUNCH_JSON="$OUTPUT_DIR/devicectl_launch.json"
TIME_TRACE="$OUTPUT_DIR/time_profiler_hardware.trace"
SWIFTUI_TRACE="$OUTPUT_DIR/swiftui_hardware.trace"
TIME_TOC_XML="$OUTPUT_DIR/time_profiler_hardware_toc.xml"
SWIFTUI_TOC_XML="$OUTPUT_DIR/swiftui_hardware_toc.xml"
SWIFTUI_HITCHES_XML="$OUTPUT_DIR/swiftui_hitches.xml"
SWIFTUI_UPDATES_XML="$OUTPUT_DIR/swiftui_updates.xml"
SUMMARY_MD="$OUTPUT_DIR/summary.md"

mkdir -p "$OUTPUT_DIR"

echo "Building Stratix-Debug for hardware device..."
xcodebuild \
  -workspace Stratix.xcworkspace \
  -scheme Stratix-Debug \
  -destination "id=$HARDWARE_DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$CLONED_PACKAGES_PATH" \
  build >"$BUILD_LOG" 2>&1

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: built app not found at $APP_PATH" >&2
  exit 1
fi

echo "Installing app on hardware device..."
xcrun devicectl device install app \
  --device "$HARDWARE_DEVICECTL_ID" \
  "$APP_PATH" >"$INSTALL_LOG" 2>&1

echo "Launching installed app on hardware device..."
xcrun devicectl device process launch \
  --device "$HARDWARE_DEVICECTL_ID" \
  --terminate-existing \
  --activate \
  --json-output "$LAUNCH_JSON" \
  "$BUNDLE_ID"

echo "Recording Time Profiler trace..."
xcrun xctrace record \
  --template "Time Profiler" \
  --device "$HARDWARE_DEVICE_ID" \
  --output "$TIME_TRACE" \
  --time-limit 20s \
  --launch -- "$BUNDLE_ID"

echo "Recording SwiftUI trace..."
xcrun xctrace record \
  --template "SwiftUI" \
  --device "$HARDWARE_DEVICE_ID" \
  --output "$SWIFTUI_TRACE" \
  --time-limit 15s \
  --launch -- "$BUNDLE_ID"

echo "Exporting trace metadata..."
xcrun xctrace export --input "$TIME_TRACE" --toc >"$TIME_TOC_XML"
xcrun xctrace export --input "$SWIFTUI_TRACE" --toc >"$SWIFTUI_TOC_XML"
xcrun xctrace export --input "$SWIFTUI_TRACE" --xpath '/trace-toc/run/data/table[@schema="hitches"]' >"$SWIFTUI_HITCHES_XML"
xcrun xctrace export --input "$SWIFTUI_TRACE" --xpath '/trace-toc/run/data/table[@schema="swiftui-updates"]' >"$SWIFTUI_UPDATES_XML"

echo "Writing stable profile summary..."
python3 - "$TIME_TOC_XML" "$SWIFTUI_TOC_XML" "$SWIFTUI_HITCHES_XML" "$SWIFTUI_UPDATES_XML" "$SUMMARY_MD" "$OUTPUT_DIR" "$BUILD_LOG" "$INSTALL_LOG" "$LAUNCH_JSON" "$TIME_TRACE" "$SWIFTUI_TRACE" "$BUNDLE_ID" <<'PY'
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def parse_toc(path: Path) -> dict[str, str]:
    root = ET.fromstring(path.read_text())
    run = root.find("./run")
    target = run.find("./info/target")
    summary = run.find("./info/summary")
    device = target.find("./device")
    process = target.find("./process")
    return {
        "device_name": device.attrib.get("name", ""),
        "device_uuid": device.attrib.get("uuid", ""),
        "device_model": device.attrib.get("model", ""),
        "platform": device.attrib.get("platform", ""),
        "os_version": device.attrib.get("os-version", ""),
        "process_name": process.attrib.get("name", ""),
        "process_pid": process.attrib.get("pid", ""),
        "duration": summary.findtext("duration", default=""),
        "start_date": summary.findtext("start-date", default=""),
        "end_date": summary.findtext("end-date", default=""),
        "template_name": summary.findtext("template-name", default=""),
        "time_limit": summary.findtext("time-limit", default=""),
        "end_reason": summary.findtext("end-reason", default=""),
    }


def parse_trace_query_rows(path: Path) -> tuple[int, int]:
    text = path.read_text()
    count = text.count("<row>")
    duration_total_ns = 0
    for raw_value in re.findall(r"<duration[^>]*>(\d+)</duration>", text):
        duration_total_ns += int(raw_value)
    return count, duration_total_ns


def fmt_ms(duration_ns: int) -> str:
    return f"{duration_ns / 1_000_000:.3f} ms"


time_toc = parse_toc(Path(sys.argv[1]))
swiftui_toc = parse_toc(Path(sys.argv[2]))
hitch_count, hitch_total_ns = parse_trace_query_rows(Path(sys.argv[3]))
update_count, update_total_ns = parse_trace_query_rows(Path(sys.argv[4]))
summary_path = Path(sys.argv[5])
output_dir = Path(sys.argv[6])
build_log = Path(sys.argv[7])
install_log = Path(sys.argv[8])
launch_json = Path(sys.argv[9])
time_trace = Path(sys.argv[10])
swiftui_trace = Path(sys.argv[11])
bundle_id = sys.argv[12]

summary = f"""# Hardware Profile Capture

- Archive root: `{output_dir}`
- Device: `{time_toc["device_name"]}` (`{time_toc["device_model"]}`)
- Device id: `{time_toc["device_uuid"]}`
- Platform: `{time_toc["platform"]}` `{time_toc["os_version"]}`
- Bundle id: `{bundle_id}`

## Capture

| Trace | Template | Duration | Time limit | End reason |
| --- | --- | --- | --- | --- |
| Time Profiler | `{time_toc["template_name"]}` | `{time_toc["duration"]}` | `{time_toc["time_limit"]}` | `{time_toc["end_reason"]}` |
| SwiftUI | `{swiftui_toc["template_name"]}` | `{swiftui_toc["duration"]}` | `{swiftui_toc["time_limit"]}` | `{swiftui_toc["end_reason"]}` |

## Stable Totals

| Metric | Value |
| --- | --- |
| SwiftUI hitch events | `{hitch_count}` |
| SwiftUI hitch total duration | `{fmt_ms(hitch_total_ns)}` |
| SwiftUI update events | `{update_count}` |
| SwiftUI update total duration | `{fmt_ms(update_total_ns)}` |

## Evidence

- Build log: `{build_log}`
- Install log: `{install_log}`
- Launch metadata: `{launch_json}`
- Time Profiler trace: `{time_trace}`
- SwiftUI trace: `{swiftui_trace}`
- Time Profiler TOC XML: `{Path(sys.argv[1])}`
- SwiftUI TOC XML: `{Path(sys.argv[2])}`
- SwiftUI hitches XML: `{Path(sys.argv[3])}`
- SwiftUI updates XML: `{Path(sys.argv[4])}`
"""

summary_path.write_text(summary)
PY

echo "Hardware profile capture written to: $OUTPUT_DIR"
echo "Summary: $SUMMARY_MD"
