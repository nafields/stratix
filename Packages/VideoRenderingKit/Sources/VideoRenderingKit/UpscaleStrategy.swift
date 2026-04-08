// UpscaleStrategy.swift
// Defines upscale strategy.
//

import Metal

// MARK: - UpscaleStrategy

/// Priority-ordered upscale strategy resolved per device at runtime.
///
/// Resolution order (highest → lowest):
///   1. `metal4FXSpatial`     — MTL4FXSpatialScaler (A15+, tvOS 26)
///   2. `vtSuperResolution`   — VTLowLatencySuperResolutionScaler (420v required)
///   3. `vtFrameInterpolation`— VTLowLatencyFrameInterpolation ×2 (420v required, +33 ms)
///   4. `metalFXSpatial`      — MTLFXSpatialScaler (A12+, current renderer)
///   5. `passthrough`         — blit only, scaleAspectFit handles display scaling
public enum UpscaleStrategy: Equatable, Sendable {
    case metal4FXSpatial
    case vtSuperResolution(scaleFactor: Float)
    case vtFrameInterpolation
    case metalFXSpatial
    case passthrough
}

// MARK: - UpscaleCapabilityProbing

/// Injectable interface for querying device upscale capabilities.
/// Concrete implementations: `LiveUpscaleCapabilityProbe` and test mocks.
public protocol UpscaleCapabilityProbing: Sendable {
    /// Returns `true` when the device supports `MTL4FXSpatialScaler`.
    func supportsMetal4FXSpatial(device: any MTLDevice) -> Bool

    /// Returns the supported VT super-resolution scale factors for the given source dimensions,
    /// or empty when LLSR is unavailable on this device.
    func vtSuperResolutionScaleFactors(sourceW: Int, sourceH: Int) -> [Float]

    /// Returns `true` when VT frame interpolation (spatialScaleFactor: 2) is supported
    /// for the given source dimensions.
    func supportsVTFrameInterpolation(sourceW: Int, sourceH: Int) -> Bool

    /// Returns `true` when the device supports `MTLFXSpatialScaler`.
    func supportsMetalFXSpatial(device: any MTLDevice) -> Bool
}
