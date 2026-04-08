// RouteSwitchPerformanceTests.swift
// Exercises route switch performance behavior.
//

import Metal
import VideoRenderingKit
import XCTest

final class RouteSwitchPerformanceTests: XCTestCase {
    func testRenderLadderFallbackBookkeepingPerformance() {
        let planner = makeMetalProfilePlanner()
        let plan = planner.makePlan(
            device: MTLCreateSystemDefaultDevice(),
            sourceW: 1920,
            sourceH: 1080,
            targetW: 3840,
            targetH: 2160,
            upscalingEnabled: true,
            floorBehavior: .metalFloor
        )
        let orderedFailures = plan.eligibleRungs.isEmpty ? [RenderLadderRung.sampleBuffer] : plan.eligibleRungs

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()],
            options: makePerformanceMeasureOptions(iterationCount: 5)
        ) {
            for _ in 0..<2_000 {
                var deadRungs: Set<RenderLadderRung> = []
                var failureCounts: [RenderLadderRung: Int] = [:]

                for rung in orderedFailures {
                    failureCounts = planner.failureCountsAfterFailure(
                        rung,
                        existingFailureCounts: failureCounts
                    )
                    deadRungs = planner.deadRungs(from: failureCounts, maxFailures: 1)
                    _ = planner.nextCandidate(in: plan, deadRungs: deadRungs)
                }
            }
        }
    }
}
