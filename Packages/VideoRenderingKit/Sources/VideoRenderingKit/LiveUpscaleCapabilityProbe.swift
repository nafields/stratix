// LiveUpscaleCapabilityProbe.swift
// Defines live upscale capability probe.
//

import Metal
#if canImport(MetalFX)
import MetalFX
#endif
import VideoToolbox
import OSLog

private let log = Logger(subsystem: "VideoRenderingKit", category: "CapabilityProbe")

// MARK: - LiveUpscaleCapabilityProbe

/// Real hardware capability probe used in production.
///
/// All checks are lightweight (no GPU work, no VT session creation beyond what the API
/// requires for a capability query). Safe to call on any thread.
public struct LiveUpscaleCapabilityProbe: UpscaleCapabilityProbing {

    public init() {}

    // MARK: Tier 1 — Metal4FX (A15+, tvOS 26)

    public func supportsMetal4FXSpatial(device: any MTLDevice) -> Bool {
        #if canImport(MetalFX)
        if #available(tvOS 26, macOS 26, *) {
            let supported = MTLFXSpatialScalerDescriptor.supportsMetal4FX(device)
            log.debug("Metal4FX spatial supported: \(supported)")
            return supported
        }
        return false
        #else
        return false
        #endif
    }

    // MARK: Tier 2 — VT Super Resolution
    // VTLowLatencySuperResolutionScalerConfiguration is real-device only (no simulator stub).

    public func vtSuperResolutionScaleFactors(sourceW: Int, sourceH: Int) -> [Float] {
#if !targetEnvironment(simulator)
        if #available(tvOS 18, macOS 26, *) {
            guard VTLowLatencySuperResolutionScalerConfiguration.isSupported else {
                log.debug("LLSR: not supported on this device")
                return []
            }
            let factors = VTLowLatencySuperResolutionScalerConfiguration
                .supportedScaleFactors(frameWidth: sourceW, frameHeight: sourceH)
                .map { Float($0) }
            log.debug("LLSR supported scale factors for \(sourceW)×\(sourceH): \(factors)")
            return factors
        }
        return []
#else
        return []
#endif
    }

    // MARK: Tier 3 — VT Frame Interpolation (spatialScaleFactor: 2)
    // VTLowLatencyFrameInterpolationConfiguration is real-device only (no simulator stub).

    public func supportsVTFrameInterpolation(sourceW: Int, sourceH: Int) -> Bool {
#if !targetEnvironment(simulator)
        if #available(tvOS 18, macOS 26, *) {
            guard VTLowLatencyFrameInterpolationConfiguration.isSupported else {
                log.debug("LLFI: not supported on this device")
                return false
            }
            // Probe the spatialScaleFactor: 2 path — this init returns nil on A10X.
            let config = VTLowLatencyFrameInterpolationConfiguration(
                frameWidth: sourceW,
                frameHeight: sourceH,
                spatialScaleFactor: 2
            )
            let supported = config != nil
            log.debug("LLFI spatialScale×2 for \(sourceW)×\(sourceH): \(supported)")
            return supported
        }
        return false
#else
        return false
#endif
    }

    // MARK: Tier 4 — MetalFX Spatial

    public func supportsMetalFXSpatial(device: any MTLDevice) -> Bool {
        #if canImport(MetalFX)
        let supported = MTLFXSpatialScalerDescriptor.supportsDevice(device)
        log.debug("MetalFX spatial supported: \(supported)")
        return supported
        #else
        return false
        #endif
    }
}
