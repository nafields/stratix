// UpscaleCapabilityResolverTests.swift
// Exercises upscale capability resolver behavior.
//

import Metal
import Testing
@testable import VideoRenderingKit

struct MockUpscaleCapabilityProbe: UpscaleCapabilityProbing {
    var metal4FX: Bool = false
    var scaleFactors: [Float] = []
    var vtFrameInterpolation: Bool = false
    var metalFX: Bool = false

    func supportsMetal4FXSpatial(device: any MTLDevice) -> Bool { metal4FX }
    func vtSuperResolutionScaleFactors(sourceW: Int, sourceH: Int) -> [Float] { scaleFactors }
    func supportsVTFrameInterpolation(sourceW: Int, sourceH: Int) -> Bool { vtFrameInterpolation }
    func supportsMetalFXSpatial(device: any MTLDevice) -> Bool { metalFX }
}

@Suite struct UpscaleCapabilityResolverTests {
    let device: any MTLDevice = MTLCreateSystemDefaultDevice()!

    func makeResolver(_ probe: MockUpscaleCapabilityProbe) -> UpscaleCapabilityResolver {
        UpscaleCapabilityResolver(probe: probe)
    }

    @Test func noUpscaleNeeded_returnsPassthrough() {
        let resolver = makeResolver(
            MockUpscaleCapabilityProbe(metal4FX: true, scaleFactors: [2.0], vtFrameInterpolation: true, metalFX: true)
        )
        let result = resolver.resolve(device: device, sourceW: 1920, sourceH: 1080, targetW: 1920, targetH: 1080)
        #expect(result == .passthrough)
    }

    @Test func sourceLargerThanTarget_passthrough() {
        let resolver = makeResolver(
            MockUpscaleCapabilityProbe(metal4FX: true, scaleFactors: [2.0], vtFrameInterpolation: true, metalFX: true)
        )
        let result = resolver.resolve(device: device, sourceW: 3840, sourceH: 2160, targetW: 1920, targetH: 1080)
        #expect(result == .passthrough)
    }

    @Test func allUnavailable_returnsPassthrough() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe())
        let result = resolver.resolve(device: device, sourceW: 1920, sourceH: 1080, targetW: 3840, targetH: 2160)
        #expect(result == .passthrough)
    }

    @Test func onlyMetalFX_returnsMetalFXSpatial() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(metalFX: true))
        let result = resolver.resolve(device: device, sourceW: 1920, sourceH: 1080, targetW: 3840, targetH: 2160)
        #expect(result == .metalFXSpatial)
    }

    @Test func metal4FXBeatsMetalFX() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(metal4FX: true, metalFX: true))
        let result = resolver.resolve(device: device, sourceW: 1920, sourceH: 1080, targetW: 3840, targetH: 2160)
        #expect(result == .metal4FXSpatial)
    }

    @Test func llsrBeatsMetalFX() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(scaleFactors: [2.0], metalFX: true))
        let result = resolver.resolve(device: device, sourceW: 1920, sourceH: 1080, targetW: 3840, targetH: 2160)
        #expect(result == .vtSuperResolution(scaleFactor: 2.0))
    }

    @Test func metal4FXBeatsLLSR() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(metal4FX: true, scaleFactors: [2.0]))
        let result = resolver.resolve(device: device, sourceW: 1920, sourceH: 1080, targetW: 3840, targetH: 2160)
        #expect(result == .metal4FXSpatial)
    }

    @Test func llfiBeatsMetalFXOnTrueTwoXTarget() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(vtFrameInterpolation: true, metalFX: true))
        let result = resolver.resolve(device: device, sourceW: 1920, sourceH: 1080, targetW: 3840, targetH: 2160)
        #expect(result == .vtFrameInterpolation)
    }

    @Test func llsrBeatsLLFIOnTrueTwoXTarget() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(scaleFactors: [2.0], vtFrameInterpolation: true))
        let result = resolver.resolve(device: device, sourceW: 1920, sourceH: 1080, targetW: 3840, targetH: 2160)
        #expect(result == .vtSuperResolution(scaleFactor: 2.0))
    }

    @Test func llsrSelectsLargestScaleFactorThatFitsTarget() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(scaleFactors: [1.25, 1.5, 2.0]))
        let result = resolver.resolve(device: device, sourceW: 1280, sourceH: 720, targetW: 1920, targetH: 1080)
        #expect(result == .vtSuperResolution(scaleFactor: 1.5))
    }

    @Test func llfiSkippedWhenTargetIsNotTrueTwoX() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(vtFrameInterpolation: true, metalFX: true))
        let result = resolver.resolve(device: device, sourceW: 1280, sourceH: 720, targetW: 1920, targetH: 1080)
        #expect(result == .metalFXSpatial)
    }

    @Test func resolveCandidates_returnsTargetAwarePriorityOrder() {
        let resolver = makeResolver(
            MockUpscaleCapabilityProbe(
                metal4FX: true,
                scaleFactors: [1.25, 1.5, 2.0],
                vtFrameInterpolation: true,
                metalFX: true
            )
        )

        let result = resolver.resolveCandidates(
            device: device,
            sourceW: 1280,
            sourceH: 720,
            targetW: 1920,
            targetH: 1080
        )

        #expect(
            result == [
                .metal4FXSpatial,
                .vtSuperResolution(scaleFactor: 1.5),
                .metalFXSpatial,
                .passthrough
            ]
        )
    }

    @Test func resolveCandidateResolution_reportsSkippedReasons() {
        let resolver = makeResolver(MockUpscaleCapabilityProbe(scaleFactors: [2.0], vtFrameInterpolation: true))
        let result = resolver.resolveCandidateResolution(
            device: nil,
            sourceW: 1280,
            sourceH: 720,
            targetW: 1920,
            targetH: 1080
        )

        #expect(result.candidates == [.passthrough])
        #expect(result.skippedRungReasons["metal4fx"] == "Metal device unavailable")
        #expect(result.skippedRungReasons["llsr"] == "supportedScaleFactors=[2] overshoot target 1920x1080")
        #expect(result.skippedRungReasons["llfi"] == "requires a true 2x target; desired scale=1.50")
        #expect(result.skippedRungReasons["metalfx"] == "Metal device unavailable")
    }
}

@Suite struct RenderLadderPlannerTests {
    let device: any MTLDevice = MTLCreateSystemDefaultDevice()!

    func makePlanner(_ probe: MockUpscaleCapabilityProbe) -> RenderLadderPlanner {
        RenderLadderPlanner(resolver: UpscaleCapabilityResolver(probe: probe))
    }

    @Test func startSafeBeginsOnSampleBuffer() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(metalFX: true))
        let plan = planner.makePlan(
            device: device,
            sourceW: 1920,
            sourceH: 1080,
            targetW: 3840,
            targetH: 2160,
            upscalingEnabled: true,
            floorBehavior: .sampleFloor
        )

        #expect(plan.activeRung == .sampleBuffer)
        #expect(plan.floorRung == .sampleBuffer)
        #expect(plan.eligibleRungs == [.metalFXSpatial])
        #expect(plan.desiredProcessingTarget == RenderLadderDimensions(width: 3840, height: 2160))
    }

    @Test func desiredProcessingTargetAspectFitsDisplayTarget() {
        let planner = makePlanner(MockUpscaleCapabilityProbe())
        let desired = planner.desiredProcessingTarget(
            sourceDimensions: RenderLadderDimensions(width: 1920, height: 800),
            displayTargetDimensions: RenderLadderDimensions(width: 3840, height: 2160)
        )

        #expect(desired == RenderLadderDimensions(width: 3840, height: 1600))
    }

    @Test func sampleFloorDoesNotAutoAppendPassthrough() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(metalFX: true))
        let plan = planner.makePlan(
            device: device,
            sourceW: 1920,
            sourceH: 1080,
            targetW: 3840,
            targetH: 2160,
            upscalingEnabled: true,
            floorBehavior: .sampleFloor
        )

        #expect(plan.eligibleRungs.contains(.passthrough) == false)
    }

    @Test func metalFloorAppendsPassthroughAfterEnhancementRungs() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(scaleFactors: [2.0], metalFX: true))
        let plan = planner.makePlan(
            device: device,
            sourceW: 1920,
            sourceH: 1080,
            targetW: 3840,
            targetH: 2160,
            upscalingEnabled: true,
            floorBehavior: .metalFloor
        )

        #expect(
            plan.eligibleRungs == [
                .vtSuperResolution(scaleFactor: 2.0),
                .metalFXSpatial,
                .passthrough
            ]
        )
        #expect(plan.floorRung == .passthrough)
    }

    @Test func metalFloorWithoutMetalDeviceStaysOnSampleBufferFloor() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(scaleFactors: [1.5], vtFrameInterpolation: true))
        let plan = planner.makePlan(
            device: nil,
            sourceW: 1280,
            sourceH: 720,
            targetW: 1920,
            targetH: 1080,
            upscalingEnabled: true,
            floorBehavior: .metalFloor
        )

        #expect(plan.floorRung == .sampleBuffer)
        #expect(plan.eligibleRungs == [.vtSuperResolution(scaleFactor: 1.5)])
        #expect(plan.skippedRungReasons["passthrough"] == "Metal device unavailable")
    }

    @Test func deadRungMemoryReturnsNextCandidateOnly() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(scaleFactors: [2.0], vtFrameInterpolation: true, metalFX: true))
        let plan = planner.makePlan(
            device: device,
            sourceW: 1920,
            sourceH: 1080,
            targetW: 3840,
            targetH: 2160,
            upscalingEnabled: true,
            floorBehavior: .sampleFloor
        )

        let dead = planner.deadRungsAfterFailure(.vtSuperResolution(scaleFactor: 2.0), existingDeadRungs: [])
        let next = planner.nextCandidate(in: plan, deadRungs: dead)

        #expect(next == .vtFrameInterpolation)
    }

    @Test func rungNeedsThreeFailuresBeforeItIsDead() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(scaleFactors: [2.0], vtFrameInterpolation: true))
        let plan = planner.makePlan(
            device: device,
            sourceW: 1920,
            sourceH: 1080,
            targetW: 3840,
            targetH: 2160,
            upscalingEnabled: true,
            floorBehavior: .sampleFloor
        )

        let rung = RenderLadderRung.vtSuperResolution(scaleFactor: 2.0)
        var failureCounts: [RenderLadderRung: Int] = [:]

        failureCounts = planner.failureCountsAfterFailure(rung, existingFailureCounts: failureCounts)
        #expect(planner.deadRungs(from: failureCounts, maxFailures: 3).isEmpty)
        #expect(planner.nextCandidate(in: plan, deadRungs: planner.deadRungs(from: failureCounts, maxFailures: 3)) == rung)

        failureCounts = planner.failureCountsAfterFailure(rung, existingFailureCounts: failureCounts)
        #expect(planner.deadRungs(from: failureCounts, maxFailures: 3).isEmpty)
        #expect(planner.nextCandidate(in: plan, deadRungs: planner.deadRungs(from: failureCounts, maxFailures: 3)) == rung)

        failureCounts = planner.failureCountsAfterFailure(rung, existingFailureCounts: failureCounts)
        let deadRungs = planner.deadRungs(from: failureCounts, maxFailures: 3)
        #expect(deadRungs.contains(rung))
        #expect(planner.nextCandidate(in: plan, deadRungs: deadRungs) == .vtFrameInterpolation)
    }

    @Test func llfiFailureAdvancesToMetalFXAfterThreeStrikes() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(vtFrameInterpolation: true, metalFX: true))
        let plan = planner.makePlan(
            device: device,
            sourceW: 1920,
            sourceH: 1080,
            targetW: 3840,
            targetH: 2160,
            upscalingEnabled: true,
            floorBehavior: .sampleFloor
        )

        var failureCounts: [RenderLadderRung: Int] = [:]
        failureCounts = planner.failureCountsAfterFailure(.vtFrameInterpolation, existingFailureCounts: failureCounts)
        failureCounts = planner.failureCountsAfterFailure(.vtFrameInterpolation, existingFailureCounts: failureCounts)
        #expect(
            planner.nextCandidate(
                in: plan,
                deadRungs: planner.deadRungs(from: failureCounts, maxFailures: 3)
            ) == .vtFrameInterpolation
        )

        failureCounts = planner.failureCountsAfterFailure(.vtFrameInterpolation, existingFailureCounts: failureCounts)
        let deadRungs = planner.deadRungs(from: failureCounts, maxFailures: 3)
        #expect(deadRungs.contains(.vtFrameInterpolation))
        #expect(planner.nextCandidate(in: plan, deadRungs: deadRungs) == .metalFXSpatial)
    }

    @Test func metalFloorStopsAfterThreeFailuresWhenOnlyPassthroughRemains() {
        let planner = makePlanner(MockUpscaleCapabilityProbe())
        let plan = RenderLadderPlan(
            activeRung: .sampleBuffer,
            sourceDimensions: RenderLadderDimensions(width: 1920, height: 1080),
            displayTargetDimensions: RenderLadderDimensions(width: 3840, height: 2160),
            desiredProcessingTarget: RenderLadderDimensions(width: 3840, height: 2160),
            eligibleRungs: [.passthrough],
            floorRung: .passthrough
        )

        var failureCounts: [RenderLadderRung: Int] = [:]
        failureCounts = planner.failureCountsAfterFailure(.passthrough, existingFailureCounts: failureCounts)
        failureCounts = planner.failureCountsAfterFailure(.passthrough, existingFailureCounts: failureCounts)
        #expect(planner.nextCandidate(in: plan, deadRungs: planner.deadRungs(from: failureCounts, maxFailures: 3)) == .passthrough)

        failureCounts = planner.failureCountsAfterFailure(.passthrough, existingFailureCounts: failureCounts)
        let deadRungs = planner.deadRungs(from: failureCounts, maxFailures: 3)
        #expect(deadRungs.contains(.passthrough))
        #expect(planner.nextCandidate(in: plan, deadRungs: deadRungs) == nil)
    }

    @Test func upscalingDisabledLeavesOnlySampleBuffer() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(metal4FX: true, scaleFactors: [2.0], vtFrameInterpolation: true, metalFX: true))
        let plan = planner.makePlan(
            device: device,
            sourceW: 1920,
            sourceH: 1080,
            targetW: 3840,
            targetH: 2160,
            upscalingEnabled: false,
            floorBehavior: .metalFloor
        )

        #expect(plan.activeRung == .sampleBuffer)
        #expect(plan.eligibleRungs.isEmpty)
        #expect(plan.floorRung == .sampleBuffer)
    }

    @Test func sourceAtOrAboveDesiredTargetProducesNoUpscaleRungs() {
        let planner = makePlanner(MockUpscaleCapabilityProbe(metal4FX: true, scaleFactors: [2.0], vtFrameInterpolation: true, metalFX: true))
        let plan = planner.makePlan(
            device: device,
            sourceW: 1920,
            sourceH: 1080,
            targetW: 1280,
            targetH: 720,
            upscalingEnabled: true,
            floorBehavior: .sampleFloor
        )

        #expect(plan.eligibleRungs.isEmpty)
        #expect(plan.desiredProcessingTarget == RenderLadderDimensions(width: 1280, height: 720))
    }
}
