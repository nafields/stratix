// VideoCapabilitiesBootstrapProbe.swift
// Defines video capabilities bootstrap probe.
//

import Foundation
import Metal
import DiagnosticsKit
import VideoRenderingKit

@MainActor
final class VideoCapabilitiesBootstrapProbe {
    struct Dependencies {
        let makeDevice: @MainActor () -> MTLDevice?
        let makeProbe: @MainActor () -> LiveUpscaleCapabilityProbe
        let makeResolver: @MainActor (LiveUpscaleCapabilityProbe) -> UpscaleCapabilityResolver
        let logInfo: @MainActor (String) -> Void
        let logWarning: @MainActor (String) -> Void
    }

    private var hasLoggedStartupVideoCapabilities = false

    func runIfNeeded(
        dependencies: Dependencies
    ) {
        guard !hasLoggedStartupVideoCapabilities else { return }
        hasLoggedStartupVideoCapabilities = true

        guard let device = dependencies.makeDevice() else {
            dependencies.logWarning("Startup video capability probe: no Metal device available; assuming passthrough rendering")
            return
        }

        let sourceW = 1920
        let sourceH = 1080
        let targetW = 3840
        let targetH = 2160

        let probe = dependencies.makeProbe()
        let resolver = dependencies.makeResolver(probe)

        let metal4FX = probe.supportsMetal4FXSpatial(device: device)
        let llsrScaleFactors = probe.vtSuperResolutionScaleFactors(sourceW: sourceW, sourceH: sourceH)
        let llfi = probe.supportsVTFrameInterpolation(sourceW: sourceW, sourceH: sourceH)
        let metalFX = probe.supportsMetalFXSpatial(device: device)
        let strategy = resolver.resolve(
            device: device,
            sourceW: sourceW,
            sourceH: sourceH,
            targetW: targetW,
            targetH: targetH
        )

        let scaleFactorSummary = llsrScaleFactors.isEmpty
            ? "none"
            : llsrScaleFactors.map { String(format: "%.2f", $0) }.joined(separator: ", ")

        dependencies.logInfo(
            """
            Startup video capability probe: metalDevice=\(device.name) \
            source=\(sourceW)x\(sourceH) target=\(targetW)x\(targetH) \
            metal4FX=\(metal4FX) llsrScaleFactors=[\(scaleFactorSummary)] \
            llfi=\(llfi) metalFX=\(metalFX) selected=\(describe(strategy))
            """
        )
    }

    private func describe(_ strategy: UpscaleStrategy) -> String {
        switch strategy {
        case .metal4FXSpatial:
            return "metal4FXSpatial"
        case .vtSuperResolution(let scaleFactor):
            return "vtSuperResolution(scaleFactor: \(String(format: "%.2f", scaleFactor)))"
        case .vtFrameInterpolation:
            return "vtFrameInterpolation"
        case .metalFXSpatial:
            return "metalFXSpatial"
        case .passthrough:
            return "passthrough"
        }
    }
}
