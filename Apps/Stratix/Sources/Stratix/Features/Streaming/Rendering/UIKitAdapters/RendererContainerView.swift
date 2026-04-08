// RendererContainerView.swift
// Defines the renderer container view used in the Streaming / UIKitAdapters surface.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(Metal)
import UIKit
import MetalKit

final class RendererContainerView: UIView {
    weak var mtkView: MTKView?
    weak var sampleBufferView: SampleBufferDisplayView?
    private var didLogFirstLayout = false

    override func layoutSubviews() {
        super.layoutSubviews()
        if let mtkView {
            mtkView.frame = bounds
            mtkView.setNeedsLayout()
        }
        if let sampleBufferView {
            sampleBufferView.frame = bounds
            sampleBufferView.setNeedsLayout()
            sampleBufferView.layoutIfNeeded()
        }
        if !didLogFirstLayout, window != nil {
            didLogFirstLayout = true
            let mtkWidth = Int(mtkView?.bounds.width ?? 0)
            let mtkHeight = Int(mtkView?.bounds.height ?? 0)
            streamLog("[StreamView] RendererContainerView first layout bounds=\(Int(bounds.width))x\(Int(bounds.height)) mtkView=\(mtkWidth)x\(mtkHeight)")
        }
    }
}
#endif
