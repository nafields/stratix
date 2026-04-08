# Package Platform Audit

This audit records the package-platform posture after the Stage 8 modernization wave.

Conclusions:
- No package manifest was lowered in Stage 8.
- Every package manifest remains on `swift-tools-version 6.2`.
- The app project still targets `tvOS 26.0`.

| Package | Platforms | Notes |
|---|---|---|
| DiagnosticsKit | `.macOS(.v14)`, `.tvOS(.v26)`, `.iOS(.v17)` | Matches current `Package.swift`; includes `swift-async-algorithms` without lowering the platform floor. |
| StratixCore | `.macOS(.v14)`, `.tvOS(.v26)`, `.iOS(.v17)` | Matches current `Package.swift`; SwiftData-backed hydration work did not change the package platform set. |
| StratixModels | `.macOS(.v14)`, `.tvOS(.v26)`, `.iOS(.v17)` | Matches current `Package.swift`; remains the leaf shared-model package. |
| InputBridge | `.macOS(.v14)`, `.tvOS(.v26)`, `.iOS(.v17)` | Matches current `Package.swift`; no platform drift. |
| StreamingCore | `.macOS(.v14)`, `.tvOS(.v26)`, `.iOS(.v17)` | Matches current `Package.swift`; streaming/runtime work preserved the existing package floor. |
| VideoRenderingKit | `.macOS(.v14)`, `.tvOS(.v26)` | Matches current `Package.swift`; remains tvOS/macOS-only. |
| XCloudAPI | `.macOS(.v14)`, `.tvOS(.v26)`, `.iOS(.v17)` | Matches current `Package.swift`; network-layer modernization did not alter supported platforms. |

Verification basis:
- `Packages/*/Package.swift`
- `Apps/Stratix/Stratix.xcodeproj/project.pbxproj`
