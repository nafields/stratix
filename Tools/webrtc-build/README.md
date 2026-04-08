# WebRTC tvOS Build Pipeline

This directory contains the scripts and patch set used to build the committed `WebRTC.xcframework` that Stratix ships and validates against.

## What This Pipeline Produces

| Output | Purpose |
| --- | --- |
| `ThirdParty/WebRTC/WebRTC.xcframework` | Device and simulator WebRTC binary used by the app target. |
| `ThirdParty/WebRTC/webrtc-version.json` | Build metadata including revision, build time, toolchain, and applied patches. |
| `.cache/webrtc/out/tvos_arm64` | Device build artifacts. |
| `.cache/webrtc/out/tvos_sim_arm64` | Simulator build artifacts. |

## Build Steps

```bash
Tools/webrtc-build/sync_webrtc.sh
Tools/webrtc-build/build_webrtc_tvos.sh
Tools/webrtc-build/package_xcframework.sh
```

## Current Expectations

- Apple Silicon host
- Xcode selected via `xcode-select`
- Python 3 on `PATH`
- enough free space for the WebRTC checkout and build artifacts
- working internet access for the source sync step

## Current Patch Set

The authoritative patch list is the contents of `Tools/webrtc-build/patches/`. On the current head the pipeline applies `11` patches:

- `0001-tvos-audio-session.patch`
- `0002-tvos-disable-video-capture.patch`
- `0003-tvos-remove-opengl.patch`
- `0005-tvos-remove-use-blink-assertion.patch`
- `0006-tvos-fix-xctest-module-target.patch`
- `0007-tvos-output-only-audio-unit.patch`
- `0008-tvos-skip-input-available-check.patch`
- `0009-tvos-fix-metal-renderer-uiview.patch`
- `0010-tvos-neteq-max-delay.patch`
- `0011-tvos-stereo-audio-channels.patch`
- `0012-tvos-fix-decoder-pixel-buffer-attributes.patch`

`package_xcframework.sh` refreshes `webrtc-version.json` from that patch directory so the committed metadata stays aligned with the actual build inputs.

## Build Notes

- `build_webrtc_tvos.sh` can refresh the source tree before patching so repeated builds do not drift on partially-applied patch state.
- the current GN args target tvOS builds with `target_platform="tvos"` and `rtc_enable_objc_symbol_export=true`
- the GN deployment target inside the build script is currently `17.0`, while the app/package floor for Stratix itself is `tvOS 26.0`
- x86_64 simulator support is intentionally not part of the active pipeline

## When To Update This Directory

Update this directory whenever:

- a patch is added, removed, or changed
- the pinned WebRTC revision changes
- output paths or metadata expectations change
- the build instructions in [../../Docs/WEBRTC_GUIDE.md](../../Docs/WEBRTC_GUIDE.md) need to change to match the script behavior
