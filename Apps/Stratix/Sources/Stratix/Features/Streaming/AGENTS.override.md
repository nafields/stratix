# AGENTS.override.md — Features/Streaming/

The Streaming feature owns the stream view, overlay controls, diagnostics HUD, and render-surface coordination. It does not own the concrete WebRTC bridge implementation; that remains in `Integration/WebRTC/`.

**Modernization contract reference:** For modernization work in streaming, use `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix.

---

## Directory map

```
Features/Streaming/
├── Diagnostics/
│   ├── StreamCompactStatsHUD.swift
│   └── StreamDebugLogging.swift
├── Overlay/
│   ├── StreamOverlay.swift
│   ├── StreamOverlayComposition.swift
│   ├── StreamOverlayDiagnosticsPanel.swift
│   ├── StreamOverlayDisconnectControls.swift
│   └── StreamOverlayHUDStats.swift
├── Rendering/
│   ├── RenderSurfaceCoordinator.swift
│   ├── RendererAttachmentCoordinator.swift
│   ├── UIKitAdapters/
│   │   ├── RendererContainerView.swift
│   │   ├── SampleBufferDisplayView.swift
│   │   └── FrameProbeRenderer.swift
│   ├── SampleBufferDisplayRenderer.swift
│   ├── SampleBufferDisplayRendererLifecycle.swift
│   ├── SampleBufferDisplayRendererLowLatencyFrameInterpolation.swift
│   ├── SampleBufferDisplayRendererLowLatencySuperResolution.swift
│   ├── SampleBufferDisplayRendererLowLatencySupport.swift
│   ├── SampleBufferDisplayRendererPlainPipeline.swift
│   └── WebRTCVideoSurfaceView.swift
├── State/
│   ├── StreamOverlayState.swift
│   └── StreamSurfaceModel.swift
├── StreamControllerInputHost.swift
└── StreamView.swift
```

---

## Rendering responsibilities

### RenderSurfaceCoordinator

`RenderSurfaceCoordinator` selects which renderer path should be active. Keep it Swift-only and policy-focused.

### RendererAttachmentCoordinator

`RendererAttachmentCoordinator` owns renderer attachment, lifecycle, fallback, and telemetry dispatch. The old UIKit/probe support types are already extracted to `Rendering/UIKitAdapters/`; do not push them back into the coordinator root.

### UIKitAdapters

`RendererContainerView`, `SampleBufferDisplayView`, and `FrameProbeRenderer` are support infrastructure, not feature-root coordination types. Keep them in `Rendering/UIKitAdapters/`.

### SampleBufferDisplayRenderer

The sample-buffer renderer is intentionally split across substantive extension files. Keep that split. Do not reintroduce one-function telemetry or wrapper shards around it.

---

## State

- `StreamSurfaceModel` is `@MainActor` and `@Observable`. It owns renderer telemetry snapshot and renderer selection state.
- `StreamOverlayState` is `@MainActor` and `@Observable`. It owns HUD visibility, overlay expansion, and disconnect-confirmation state.

---

## Tests

- `StratixTests/RenderSurfaceCoordinatorTests.swift`
- `StratixTests/StreamOverlayStateTests.swift`
- `StratixTests/StreamSurfaceModelTests.swift`

---

## Concurrency rules

1. `RendererAttachmentCoordinator` is `@MainActor`. Do not weaken this.
2. `SampleBufferDisplayRenderer`, `MetalVideoRenderer`, and `FrameProbeRenderer` receive callbacks off the main thread. Route UI-facing mutation back to `@MainActor`.
3. `FrameProbeRenderer` must remain strict-concurrency safe. Actor isolation is preferred; `@unchecked Sendable` plus explicit locking is only acceptable with a documented reason.
4. Do not call `StreamSurfaceModel` mutation methods from off-main-thread without an explicit `await MainActor.run`.
