//
//  CASShader.metal
//  Stratix
//
//  NV12 → BGRA compute kernel for the Metal video pipeline.
//  Handles both full-range (420f) and limited-range (420v) input detected per-frame.
//
//  Input:
//    texture(0)  yPlane    — R8Unorm,  full-resolution luma (Y plane of NV12)
//    texture(1)  cbcrPlane — RG8Unorm, half-resolution chroma (CbCr plane of NV12)
//    buffer(2)   isFullRange — uint32, 1 = 420f (full range), 0 = 420v (limited range)
//
//  Output:
//    texture(2)  output    — BGRA8Unorm, full-resolution linear RGB frame
//
//  Pipeline:
//    WebRTC frame (RTCCVPixelBuffer NV12)
//      ↓ CVMetalTextureCacheCreateTextureFromImage (zero-copy)
//      ↓ nv12ToBGRA compute shader (NV12 → BGRA, BT.709, auto range)
//      ↓ optional MTLFXSpatialScaler (frame → display-sized texture)
//      ↓ blit to MTKView drawable
//

#include <metal_stdlib>
using namespace metal;

// MARK: - NV12 → RGB (BT.709, range-aware)
//
// fullRange = true  → 420f: Y in [0,1] maps to [0,255], UV centre-only offset.
// fullRange = false → 420v: Y in [0,1] maps to [16,235] (studio swing).
//
// xCloud H.264 streams: RTCVideoDecoderH264 currently hardcodes 420f output.
// Once patch 0003 lands (decoder → 420v), fullRange will be false in production.
static float3 nv12ToRGB(float y, float2 cbcr, bool fullRange) {
    float yS, cb, cr;
    if (fullRange) {
        // Full range: Y directly usable, UV only needs centre offset.
        yS = y;
        cb = cbcr.x - 128.0 / 255.0;
        cr = cbcr.y - 128.0 / 255.0;
    } else {
        // Limited range (studio swing): rescale Y [16-235] and UV [16-240].
        yS = (y     - 16.0  / 255.0) * (255.0 / 219.0);
        cb = (cbcr.x - 128.0 / 255.0) * (255.0 / 224.0);
        cr = (cbcr.y - 128.0 / 255.0) * (255.0 / 224.0);
    }

    // BT.709 matrix (identical for both ranges — only the Y/UV scaling differs above).
    float r = yS                + 1.5748 * cr;
    float g = yS - 0.1873 * cb - 0.4681 * cr;
    float b = yS + 1.8556 * cb;

    return clamp(float3(r, g, b), 0.0, 1.0);
}

// MARK: - Passthrough kernel

kernel void nv12ToBGRA(
    texture2d<float, access::read>  yPlane      [[texture(0)]],
    texture2d<float, access::read>  cbcrPlane   [[texture(1)]],
    texture2d<float, access::write> output      [[texture(2)]],
    constant uint32_t              &isFullRange  [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }

    float  y    = yPlane.read(gid).r;
    float2 cbcr = cbcrPlane.read(uint2(gid.x / 2, gid.y / 2)).rg;

    float3 rgb = nv12ToRGB(y, cbcr, isFullRange != 0);
    output.write(float4(rgb, 1.0), gid);
}
