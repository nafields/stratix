// RenderLadderPlanner.swift
// Defines render ladder planner.
//

import Metal

/// Chooses which non-upscaled floor the renderer should fall back to when higher rungs fail.
public enum RenderLadderFloorBehavior: String, CaseIterable, Sendable {
    case sampleFloor
    case metalFloor
}

/// Pixel dimensions for a source frame, processing target, or display target in the ladder plan.
public struct RenderLadderDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Represents one rendering or upscaling path the app can attempt for a stream.
public enum RenderLadderRung: Hashable, Sendable {
    case sampleBuffer
    case metal4FXSpatial
    case vtSuperResolution(scaleFactor: Float)
    case vtFrameInterpolation
    case metalFXSpatial
    case passthrough

    /// Stable diagnostics/export name used by renderer telemetry and fallback tracking.
    public var rawName: String {
        switch self {
        case .sampleBuffer:
            return "sampleBuffer"
        case .metal4FXSpatial:
            return "metal4fx"
        case .vtSuperResolution:
            return "llsr"
        case .vtFrameInterpolation:
            return "llfi"
        case .metalFXSpatial:
            return "metalfx"
        case .passthrough:
            return "passthrough"
        }
    }
}

/// Describes the active rung, fallback floor, and candidate ladder for a renderer session.
public struct RenderLadderPlan: Equatable, Sendable {
    public let activeRung: RenderLadderRung
    public let sourceDimensions: RenderLadderDimensions
    public let displayTargetDimensions: RenderLadderDimensions
    public let desiredProcessingTarget: RenderLadderDimensions
    public let eligibleRungs: [RenderLadderRung]
    public let skippedRungReasons: [String: String]
    public let floorRung: RenderLadderRung

    public init(
        activeRung: RenderLadderRung,
        sourceDimensions: RenderLadderDimensions,
        displayTargetDimensions: RenderLadderDimensions,
        desiredProcessingTarget: RenderLadderDimensions,
        eligibleRungs: [RenderLadderRung],
        skippedRungReasons: [String: String] = [:],
        floorRung: RenderLadderRung
    ) {
        self.activeRung = activeRung
        self.sourceDimensions = sourceDimensions
        self.displayTargetDimensions = displayTargetDimensions
        self.desiredProcessingTarget = desiredProcessingTarget
        self.eligibleRungs = eligibleRungs
        self.skippedRungReasons = skippedRungReasons
        self.floorRung = floorRung
    }
}

/// Translates capability resolution into an ordered render ladder the app can walk during failures.
public struct RenderLadderPlanner: Sendable {
    public let resolver: UpscaleCapabilityResolver

    public init(resolver: UpscaleCapabilityResolver) {
        self.resolver = resolver
    }

    /// Builds the initial ladder from source dimensions, display target, and current device capability.
    public func makePlan(
        device: (any MTLDevice)?,
        sourceW: Int,
        sourceH: Int,
        targetW: Int,
        targetH: Int,
        upscalingEnabled: Bool,
        floorBehavior: RenderLadderFloorBehavior
    ) -> RenderLadderPlan {
        let sourceDimensions = RenderLadderDimensions(
            width: max(1, sourceW),
            height: max(1, sourceH)
        )
        let displayTargetDimensions = resolvedDisplayTargetDimensions(
            sourceDimensions: sourceDimensions,
            targetW: targetW,
            targetH: targetH
        )
        let desiredProcessingTarget = desiredProcessingTarget(
            sourceDimensions: sourceDimensions,
            displayTargetDimensions: displayTargetDimensions
        )

        guard upscalingEnabled else {
            return makePlan(
                activeRung: .sampleBuffer,
                sourceDimensions: sourceDimensions,
                displayTargetDimensions: displayTargetDimensions,
                desiredProcessingTarget: desiredProcessingTarget,
                eligibleRungs: [],
                skippedRungReasons: [:],
                floorRung: .sampleBuffer
            )
        }

        let resolution = resolver.resolveCandidateResolution(
            device: device,
            sourceW: sourceDimensions.width,
            sourceH: sourceDimensions.height,
            targetW: desiredProcessingTarget.width,
            targetH: desiredProcessingTarget.height
        )

        let floorRung: RenderLadderRung = floorBehavior == .metalFloor && device != nil ? .passthrough : .sampleBuffer
        var candidates = resolution.candidates.compactMap(Self.ladderRung(from:)).filter { $0 != .passthrough }
        var skippedRungReasons = resolution.skippedRungReasons
        if floorBehavior == .metalFloor && device == nil {
            skippedRungReasons["passthrough"] = "Metal device unavailable"
        }
        if floorRung == .passthrough {
            candidates.append(.passthrough)
        }

        return makePlan(
            activeRung: .sampleBuffer,
            sourceDimensions: sourceDimensions,
            displayTargetDimensions: displayTargetDimensions,
            desiredProcessingTarget: desiredProcessingTarget,
            eligibleRungs: candidates,
            skippedRungReasons: skippedRungReasons,
            floorRung: floorRung
        )
    }

    /// Returns the next eligible rung that has not already been marked dead by prior failures.
    public func nextCandidate(
        in plan: RenderLadderPlan,
        deadRungs: Set<RenderLadderRung>
    ) -> RenderLadderRung? {
        plan.eligibleRungs.first { !deadRungs.contains($0) }
    }

    /// Marks one rung as dead after a runtime failure so later selection skips it.
    public func deadRungsAfterFailure(
        _ failedRung: RenderLadderRung,
        existingDeadRungs: Set<RenderLadderRung>
    ) -> Set<RenderLadderRung> {
        var updated = existingDeadRungs
        updated.insert(failedRung)
        return updated
    }

    /// Increments the retry budget consumed by a rung after one failed activation attempt.
    public func failureCountsAfterFailure(
        _ failedRung: RenderLadderRung,
        existingFailureCounts: [RenderLadderRung: Int]
    ) -> [RenderLadderRung: Int] {
        var updated = existingFailureCounts
        updated[failedRung, default: 0] += 1
        return updated
    }

    /// Converts per-rung failure counts into the set that should no longer be retried.
    public func deadRungs(
        from failureCounts: [RenderLadderRung: Int],
        maxFailures: Int
    ) -> Set<RenderLadderRung> {
        let threshold = max(1, maxFailures)
        return Set(
            failureCounts.compactMap { rung, count in
                count >= threshold ? rung : nil
            }
        )
    }

    private static func ladderRung(from strategy: UpscaleStrategy) -> RenderLadderRung? {
        switch strategy {
        case .metal4FXSpatial:
            return .metal4FXSpatial
        case .vtSuperResolution(let scaleFactor):
            return .vtSuperResolution(scaleFactor: scaleFactor)
        case .vtFrameInterpolation:
            return .vtFrameInterpolation
        case .metalFXSpatial:
            return .metalFXSpatial
        case .passthrough:
            return .passthrough
        }
    }

    private func resolvedDisplayTargetDimensions(
        sourceDimensions: RenderLadderDimensions,
        targetW: Int,
        targetH: Int
    ) -> RenderLadderDimensions {
        guard targetW > 0, targetH > 0 else {
            return sourceDimensions
        }
        return RenderLadderDimensions(width: targetW, height: targetH)
    }

    /// Fits processing dimensions to the display target while preserving the source aspect ratio.
    public func desiredProcessingTarget(
        sourceDimensions: RenderLadderDimensions,
        displayTargetDimensions: RenderLadderDimensions
    ) -> RenderLadderDimensions {
        let widthScale = Double(displayTargetDimensions.width) / Double(sourceDimensions.width)
        let heightScale = Double(displayTargetDimensions.height) / Double(sourceDimensions.height)
        let scale = min(widthScale, heightScale)
        guard scale.isFinite, scale > 0 else {
            return sourceDimensions
        }

        let fittedWidth = max(1, min(displayTargetDimensions.width, Int((Double(sourceDimensions.width) * scale).rounded(.down))))
        let fittedHeight = max(1, min(displayTargetDimensions.height, Int((Double(sourceDimensions.height) * scale).rounded(.down))))
        return RenderLadderDimensions(width: fittedWidth, height: fittedHeight)
    }

    private func makePlan(
        activeRung: RenderLadderRung,
        sourceDimensions: RenderLadderDimensions,
        displayTargetDimensions: RenderLadderDimensions,
        desiredProcessingTarget: RenderLadderDimensions,
        eligibleRungs: [RenderLadderRung],
        skippedRungReasons: [String: String],
        floorRung: RenderLadderRung
    ) -> RenderLadderPlan {
        RenderLadderPlan(
            activeRung: activeRung,
            sourceDimensions: sourceDimensions,
            displayTargetDimensions: displayTargetDimensions,
            desiredProcessingTarget: desiredProcessingTarget,
            eligibleRungs: eligibleRungs,
            skippedRungReasons: skippedRungReasons,
            floorRung: floorRung
        )
    }
}
