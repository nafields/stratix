// UpscaleCapabilityResolver.swift
// Defines upscale capability resolver.
//

import Foundation
import Metal

// MARK: - UpscaleCapabilityResolver

public struct UpscaleCandidateResolution: Equatable, Sendable {
    public let candidates: [UpscaleStrategy]
    public let skippedRungReasons: [String: String]

    public init(
        candidates: [UpscaleStrategy],
        skippedRungReasons: [String: String]
    ) {
        self.candidates = candidates
        self.skippedRungReasons = skippedRungReasons
    }
}

/// Resolves the best available upscale strategy for the current device and source dimensions.
///
/// The resolver is stateless and cheap to call — run it once whenever source resolution
/// changes (i.e. in `configurePresentationResources`, not per frame).
///
/// Usage:
/// ```swift
/// let resolver = UpscaleCapabilityResolver(probe: LiveUpscaleCapabilityProbe())
/// let strategy = resolver.resolve(device: device,
///                                 sourceW: 1920, sourceH: 1080,
///                                 targetW: 3840, targetH: 2160)
/// ```
public struct UpscaleCapabilityResolver: Sendable {

    public let probe: any UpscaleCapabilityProbing

    public init(probe: any UpscaleCapabilityProbing) {
        self.probe = probe
    }

    /// Returns the highest-priority `UpscaleStrategy` available for the given device and dimensions.
    ///
    /// - Returns `.passthrough` when `source >= target` in both dimensions or no upscaler is available.
    public func resolve(device: any MTLDevice,
                        sourceW: Int, sourceH: Int,
                        targetW: Int, targetH: Int) -> UpscaleStrategy {
        resolveCandidateResolution(
            device: device,
            sourceW: sourceW,
            sourceH: sourceH,
            targetW: targetW,
            targetH: targetH
        ).candidates.first ?? .passthrough
    }

    /// Returns all eligible strategies in descending priority order for the given device and dimensions.
    public func resolveCandidates(
        device: any MTLDevice,
        sourceW: Int,
        sourceH: Int,
        targetW: Int,
        targetH: Int
    ) -> [UpscaleStrategy] {
        resolveCandidateResolution(
            device: device,
            sourceW: sourceW,
            sourceH: sourceH,
            targetW: targetW,
            targetH: targetH
        ).candidates
    }

    public func resolveCandidateResolution(
        device: (any MTLDevice)?,
        sourceW: Int,
        sourceH: Int,
        targetW: Int,
        targetH: Int
    ) -> UpscaleCandidateResolution {
        guard sourceW > 0, sourceH > 0, targetW > 0, targetH > 0 else {
            return invalidDimensionsResolution()
        }

        guard targetW > sourceW || targetH > sourceH else {
            return passthroughResolution()
        }

        var candidates: [UpscaleStrategy] = []
        var skippedRungReasons: [String: String] = [:]

        appendMetalCandidate(
            device: device,
            candidate: .metal4FXSpatial,
            skippedRungKey: "metal4fx",
            candidates: &candidates,
            skippedRungReasons: &skippedRungReasons
        ) { probe.supportsMetal4FXSpatial(device: $0) }
        appendSuperResolutionCandidate(
            sourceW: sourceW,
            sourceH: sourceH,
            targetW: targetW,
            targetH: targetH,
            candidates: &candidates,
            skippedRungReasons: &skippedRungReasons
        )
        appendFrameInterpolationCandidate(
            sourceW: sourceW,
            sourceH: sourceH,
            targetW: targetW,
            targetH: targetH,
            candidates: &candidates,
            skippedRungReasons: &skippedRungReasons
        )
        appendMetalCandidate(
            device: device,
            candidate: .metalFXSpatial,
            skippedRungKey: "metalfx",
            candidates: &candidates,
            skippedRungReasons: &skippedRungReasons
        ) { probe.supportsMetalFXSpatial(device: $0) }

        candidates.append(.passthrough)
        return UpscaleCandidateResolution(
            candidates: candidates,
            skippedRungReasons: skippedRungReasons
        )
    }

    private func invalidDimensionsResolution() -> UpscaleCandidateResolution {
        let invalidDimensionReason = "invalid source or target dimensions"
        return UpscaleCandidateResolution(
            candidates: [.passthrough],
            skippedRungReasons: [
                "metal4fx": invalidDimensionReason,
                "llsr": invalidDimensionReason,
                "llfi": invalidDimensionReason,
                "metalfx": invalidDimensionReason
            ]
        )
    }

    private func passthroughResolution(
        skippedRungReasons: [String: String] = [:]
    ) -> UpscaleCandidateResolution {
        UpscaleCandidateResolution(
            candidates: [.passthrough],
            skippedRungReasons: skippedRungReasons
        )
    }

    private func appendMetalCandidate(
        device: (any MTLDevice)?,
        candidate: UpscaleStrategy,
        skippedRungKey: String,
        candidates: inout [UpscaleStrategy],
        skippedRungReasons: inout [String: String],
        isSupported: (any MTLDevice) -> Bool
    ) {
        guard let device else {
            skippedRungReasons[skippedRungKey] = "Metal device unavailable"
            return
        }
        guard isSupported(device) else {
            skippedRungReasons[skippedRungKey] = "unsupported on this device"
            return
        }
        candidates.append(candidate)
    }

    private func appendSuperResolutionCandidate(
        sourceW: Int,
        sourceH: Int,
        targetW: Int,
        targetH: Int,
        candidates: inout [UpscaleStrategy],
        skippedRungReasons: inout [String: String]
    ) {
        let scaleFactors = probe.vtSuperResolutionScaleFactors(sourceW: sourceW, sourceH: sourceH).sorted()
        let fittingScaleFactors = scaleFactors.filter {
            scaledDimensionsFitWithinTarget(
                sourceW: sourceW,
                sourceH: sourceH,
                scaleFactor: $0,
                targetW: targetW,
                targetH: targetH
            )
        }

        if let scaleFactor = fittingScaleFactors.max() {
            candidates.append(.vtSuperResolution(scaleFactor: scaleFactor))
        } else if scaleFactors.isEmpty {
            skippedRungReasons["llsr"] = "unsupported for \(sourceW)x\(sourceH)"
        } else {
            skippedRungReasons["llsr"] = "supportedScaleFactors=\(scaleFactorListDescription(scaleFactors)) overshoot target \(targetW)x\(targetH)"
        }
    }

    private func appendFrameInterpolationCandidate(
        sourceW: Int,
        sourceH: Int,
        targetW: Int,
        targetH: Int,
        candidates: inout [UpscaleStrategy],
        skippedRungReasons: inout [String: String]
    ) {
        guard targetW >= sourceW * 2, targetH >= sourceH * 2 else {
            let requiredScaleW = Double(targetW) / Double(sourceW)
            let requiredScaleH = Double(targetH) / Double(sourceH)
            let requiredScale = min(requiredScaleW, requiredScaleH)
            skippedRungReasons["llfi"] = "requires a true 2x target; desired scale=\(formattedScale(requiredScale))"
            return
        }

        guard probe.supportsVTFrameInterpolation(sourceW: sourceW, sourceH: sourceH) else {
            skippedRungReasons["llfi"] = "unsupported for \(sourceW)x\(sourceH) at 2x target"
            return
        }

        candidates.append(.vtFrameInterpolation)
    }

    private func scaledDimensionsFitWithinTarget(
        sourceW: Int,
        sourceH: Int,
        scaleFactor: Float,
        targetW: Int,
        targetH: Int
    ) -> Bool {
        let scaledWidth = Int((Double(sourceW) * Double(scaleFactor)).rounded())
        let scaledHeight = Int((Double(sourceH) * Double(scaleFactor)).rounded())
        return scaledWidth <= targetW && scaledHeight <= targetH
    }

    private func scaleFactorListDescription(_ factors: [Float]) -> String {
        "[" + factors.map { formattedScale(Double($0)) }.joined(separator: ", ") + "]"
    }

    private func formattedScale(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if abs(rounded.rounded() - rounded) < 0.001 {
            return String(Int(rounded.rounded()))
        }
        return String(format: "%.2f", rounded)
    }
}
