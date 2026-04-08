# AGENTS.override.md — Packages/DiagnosticsKit/

DiagnosticsKit owns stream metrics collection, logging, and telemetry pipeline infrastructure.

**Modernization contract reference:** If diagnostics work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Files

| File | Role |
|------|------|
| `Logger.swift` | Shared logger configuration. |
| `StatsCollector.swift` | Collects raw stats from the streaming layer. |
| `StreamMetricsExportWriter.swift` | Exports collected metrics to a writable format. |
| `StreamMetricsPipeline.swift` | Pipeline that processes, aggregates, and routes metrics. |
| `StreamMetricsSnapshot.swift` | Value type snapshot of collected metrics at a point in time. |
| `StreamPerformanceTracker.swift` | Tracks frame timing, render latency, and related performance counters. |

---

## Tests

`Tests/DiagnosticsKitTests/`:
- `DiagnosticsKitSmokeTests.swift`
- `StreamMetricsExportWriterTests.swift`
- `StreamMetricsPipelineTests.swift`
- `StreamMetricsSnapshotTests.swift`

---

## Rules

1. No UIKit, no SwiftUI, no AppKit imports here.
2. Logging infrastructure (signposts, OSLog categories) in `RemoteImagePipeline` in the app target is a candidate for migration here. When that migration happens, add a new file (`ArtworkTelemetry.swift` or similar) rather than expanding an existing file.
3. `StreamMetricsPipeline` is a candidate for Swift Async Algorithms adoption (Execution Contract): its aggregation loop can be replaced with a typed async sequence pipeline with debounce/throttle operators instead of bespoke timing logic.
4. Actor-first: if `StatsCollector` or `StreamMetricsPipeline` hold shared mutable state accessed from multiple isolation contexts, they must be actors.
