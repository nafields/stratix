// SampleBufferDisplayView.swift
// Defines the sample buffer display view used in the Streaming / UIKitAdapters surface.
//

#if WEBRTC_AVAILABLE && canImport(UIKit) && canImport(AVFoundation)
import UIKit
@preconcurrency import AVFoundation

final class SampleBufferDisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    var displayTargetDimensions: (width: Int?, height: Int?) {
        if let screen = window?.windowScene?.screen {
            let nativeBounds = screen.nativeBounds
            let width = Int(nativeBounds.width.rounded())
            let height = Int(nativeBounds.height.rounded())
            if width > 0, height > 0 {
                return (width, height)
            }
        }

        let scale = max(window?.screen.nativeScale ?? contentScaleFactor, layer.contentsScale, 1)
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        return (
            width: width > 0 ? width : nil,
            height: height > 0 ? height : nil
        )
    }
}
#endif
