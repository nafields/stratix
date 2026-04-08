# AGENTS.override.md — Tools/

Tools/ contains build infrastructure and CI support scripts. Nothing here is compiled into the app.

**Modernization contract reference:** If tool or CI support work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Subdirectories

### Tools/webrtc-build/

Scripts and patches for building WebRTC from source for tvOS.

| Item | Role |
|------|------|
| `build_webrtc_tvos.sh` | Main build script. Compiles WebRTC from source for tvOS device + simulator. |
| `package_xcframework.sh` | Packages the built libraries into `WebRTC.xcframework`. |
| `sync_webrtc.sh` | Syncs the WebRTC source tree from Chromium. |
| `README.md` | Instructions for the build pipeline. Read this before running any script. |
| `patches/` | 12 patches applied to the WebRTC source for tvOS compatibility. |

**Patch inventory:**

| Patch | What it fixes |
|-------|--------------|
| `0001-tvos-audio-session.patch` | tvOS AVAudioSession configuration |
| `0002-tvos-disable-video-capture.patch` | Disables camera capture (not available on tvOS) |
| `0003-tvos-remove-opengl.patch` | Removes OpenGL (deprecated on Apple platforms) |
| `0005-tvos-remove-use-blink-assertion.patch` | Removes Blink engine assertion |
| `0006-tvos-fix-xctest-module-target.patch` | Fixes XCTest module for tvOS |
| `0007-tvos-output-only-audio-unit.patch` | Output-only audio unit for tvOS |
| `0008-tvos-skip-input-available-check.patch` | Skips microphone availability check |
| `0009-tvos-fix-metal-renderer-uiview.patch` | Fixes Metal renderer UIView base class for tvOS |
| `0010-tvos-neteq-max-delay.patch` | Adjusts NetEQ max delay for streaming |
| `0011-tvos-stereo-audio-channels.patch` | Enables stereo audio output |
| `0012-tvos-fix-decoder-pixel-buffer-attributes.patch` | Fixes pixel buffer attributes for tvOS decoder |

These patches correspond directly to the behavior in `Integration/WebRTC/WebRTCClientImpl+TVOSAudio.swift`. If you change audio handling in the app, check whether a corresponding patch needs updating.

### Tools/ci/

Python CI helper scripts. These are called by `.github/workflows/` YAML files. Do not modify these without understanding which workflow calls them and what they validate.

---

## Rules

1. Do not run `build_webrtc_tvos.sh` in CI without confirming the WebRTC source is synced. See `sync_webrtc.sh` first.
2. The pre-built `ThirdParty/WebRTC/WebRTC.xcframework` is what the app compiles against. Only rebuild WebRTC when the source or patches change.
3. If a new tvOS-specific WebRTC behavior requires a patch, add it as a new numbered patch file in `patches/` and document it in the patch inventory above.
4. CI scripts in `Tools/ci/` must not be called directly in production code paths.

---

## Reference image location rule

Reference images for visual regression tests must be stored in **one canonical location**:

```
Apps/Stratix/Tools/shell-visual-regression/reference/
```

**Current status (confirmed by audit):** `Tools/reference/` does NOT exist. There is no duplicate reference image directory problem at this time. The canonical path is clean.

Do not create any alternative reference image directory (e.g., `Tools/reference/`, `Tools/screenshots/`, or any path outside `Apps/Stratix/Tools/shell-visual-regression/reference/`). If one is created accidentally, consolidate to the canonical path and update all CI scripts and test helpers.

The CI workflow `ci-shell-visual-regression.yml` depends on this location being canonical.
