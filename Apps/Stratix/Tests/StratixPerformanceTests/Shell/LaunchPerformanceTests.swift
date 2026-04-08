// LaunchPerformanceTests.swift
// Exercises launch performance behavior.
//

import Metal
import VideoRenderingKit
import XCTest

struct TestUpscaleCapabilityProbe: UpscaleCapabilityProbing {
    let supportsMetal4FX: Bool
    let supportsFrameInterpolation: Bool
    let supportsMetalFX: Bool
    let superResolutionScaleFactors: [Float]

    init(
        supportsMetal4FX: Bool = true,
        supportsFrameInterpolation: Bool = true,
        supportsMetalFX: Bool = true,
        superResolutionScaleFactors: [Float] = [1.25, 1.5, 2.0]
    ) {
        self.supportsMetal4FX = supportsMetal4FX
        self.supportsFrameInterpolation = supportsFrameInterpolation
        self.supportsMetalFX = supportsMetalFX
        self.superResolutionScaleFactors = superResolutionScaleFactors
    }

    func supportsMetal4FXSpatial(device: any MTLDevice) -> Bool { supportsMetal4FX }

    func vtSuperResolutionScaleFactors(sourceW: Int, sourceH: Int) -> [Float] {
        superResolutionScaleFactors
    }

    func supportsVTFrameInterpolation(sourceW: Int, sourceH: Int) -> Bool {
        supportsFrameInterpolation
    }

    func supportsMetalFXSpatial(device: any MTLDevice) -> Bool { supportsMetalFX }
}

let metalProfileRenderScenarios: [(source: RenderLadderDimensions, target: RenderLadderDimensions)] = [
    (.init(width: 1280, height: 720), .init(width: 1920, height: 1080)),
    (.init(width: 1600, height: 900), .init(width: 2560, height: 1440)),
    (.init(width: 1920, height: 1080), .init(width: 3840, height: 2160)),
    (.init(width: 1440, height: 1080), .init(width: 3840, height: 2160))
]

func makeMetalProfilePlanner() -> RenderLadderPlanner {
    RenderLadderPlanner(
        resolver: UpscaleCapabilityResolver(probe: TestUpscaleCapabilityProbe())
    )
}

final class LaunchPerformanceTests: XCTestCase {
    func testRenderLadderPlanGenerationPerformance() {
        let planner = makeMetalProfilePlanner()
        let device = MTLCreateSystemDefaultDevice()

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: PerformanceTestSupport.measureOptions(iterationCount: 5)
        ) {
            for _ in 0..<400 {
                for scenario in metalProfileRenderScenarios {
                    _ = planner.makePlan(
                        device: device,
                        sourceW: scenario.source.width,
                        sourceH: scenario.source.height,
                        targetW: scenario.target.width,
                        targetH: scenario.target.height,
                        upscalingEnabled: true,
                        floorBehavior: .metalFloor
                    )
                }
            }
        }
    }
}
