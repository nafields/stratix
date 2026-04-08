// PostStreamFreshnessPerformanceTests.swift
// Exercises post stream freshness performance behavior.
//

import Metal
import VideoRenderingKit
import XCTest

final class PostStreamFreshnessPerformanceTests: XCTestCase {
    func testUpscaleCandidateResolutionPerformance() {
        let resolver = UpscaleCapabilityResolver(
            probe: TestUpscaleCapabilityProbe(
                supportsMetal4FX: true,
                supportsFrameInterpolation: true,
                supportsMetalFX: true,
                superResolutionScaleFactors: [1.25, 1.5, 1.75, 2.0]
            )
        )
        let device = MTLCreateSystemDefaultDevice()
        let options = PerformanceTestSupport.measureOptions(iterationCount: 5)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            for _ in 0..<500 {
                for scenario in metalProfileRenderScenarios {
                    _ = resolver.resolveCandidateResolution(
                        device: device,
                        sourceW: scenario.source.width,
                        sourceH: scenario.source.height,
                        targetW: scenario.target.width,
                        targetH: scenario.target.height
                    )
                }
            }
        }
    }
}
