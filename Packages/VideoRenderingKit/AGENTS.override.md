# AGENTS.override.md — Packages/VideoRenderingKit/

VideoRenderingKit owns upscale strategy resolution and render ladder planning. It is queried by `RendererAttachmentCoordinator` in the app target to determine which upscale path to use for a given device.

**Modernization contract reference:** If rendering-strategy work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Files

| File | Role |
|------|------|
| `UpscaleStrategy.swift` | Enum defining available upscale strategies: Metal4FX, LLSR, LLFI, MetalFX, passthrough. |
| `UpscaleCapabilityResolver.swift` | Detects device capability and resolves the best available strategy. |
| `RenderLadderPlanner.swift` | Plans the render ladder (resolution steps) for a given strategy. |
| `LiveUpscaleCapabilityProbe.swift` | Runtime probe that detects actual GPU/VT capability. |

---

## Upscale priority (documented in MetalVideoRenderer)

```
Metal4FX → LLSR → LLFI → MetalFX → passthrough
```

Capability is detected at runtime via `LiveUpscaleCapabilityProbe`. The resolved strategy is passed to `RendererAttachmentCoordinator.Configuration`.

---

## Rules

1. No UIKit, no SwiftUI, no Metal imports. This package determines strategy; it does not execute rendering.
2. `UpscaleCapabilityResolver` must be callable from `@MainActor` context without blocking. If the probe requires I/O, make it async.
3. `RenderLadderFloorBehavior` is referenced in `RendererAttachmentCoordinator.Configuration`. Keep this type in VideoRenderingKit.
4. Tests live in `Tests/VideoRenderingKitTests/UpscaleCapabilityResolverTests.swift`.
