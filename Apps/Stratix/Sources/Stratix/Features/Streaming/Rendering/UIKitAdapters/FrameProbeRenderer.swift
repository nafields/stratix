// FrameProbeRenderer.swift
// Defines frame probe renderer for the Streaming / UIKitAdapters surface.
//

#if WEBRTC_AVAILABLE && canImport(UIKit)
import Foundation
import UIKit

final class FrameProbeRenderer: NSObject, RTCVideoRenderer {
    // WebRTC drives this ObjC protocol from its thread pool. This renderer cannot be
    // isolated as an actor while conforming to RTCVideoRenderer, so mutable state and
    // callback access stay serialized under stateLock instead.
    private let stateLock = NSLock()
    private var frameCount = 0
    private var lastSize: CGSize = .zero
    private var lastFrameTime: CFTimeInterval = 0
    private var lastRTPTimestamp: Double = 0
    private var onFirstFrameReceivedHandler: (@MainActor () -> Void)?

    var onFirstFrameReceived: (@MainActor () -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return onFirstFrameReceivedHandler
        }
        set {
            stateLock.lock()
            onFirstFrameReceivedHandler = newValue
            stateLock.unlock()
        }
    }

    func setSize(_ size: CGSize) {
        stateLock.lock()
        lastSize = size
        stateLock.unlock()
        streamLog("[StreamView] FrameProbe setSize: \(Int(size.width))x\(Int(size.height))")
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        let now = CACurrentMediaTime()

        var currentFrameCount = 0
        var currentSize = CGSize.zero
        var previousFrameTime: CFTimeInterval = 0
        var rtpDeltaMs = 0.0
        var firstFrameCallback: (@MainActor () -> Void)?

        stateLock.lock()
        frameCount += 1
        currentFrameCount = frameCount

        if let frame {
            currentSize = CGSize(width: Int(frame.width), height: Int(frame.height))
            lastSize = currentSize
            let rtpNowSec = Double(frame.timeStampNs) / 1_000_000_000
            rtpDeltaMs = lastRTPTimestamp > 0 ? (rtpNowSec - lastRTPTimestamp) * 1000 : 0
            lastRTPTimestamp = rtpNowSec

            switch currentFrameCount {
            case 1:
                firstFrameCallback = onFirstFrameReceivedHandler
                previousFrameTime = lastFrameTime
                lastFrameTime = now
            case 60, 300:
                previousFrameTime = lastFrameTime
                lastFrameTime = now
            default:
                if currentFrameCount % 120 == 0 {
                    previousFrameTime = lastFrameTime
                    lastFrameTime = now
                }
            }
        }
        stateLock.unlock()

        guard let frame else { return }

        let bufferType = (frame.buffer is RTCCVPixelBuffer) ? "CVPixelBuffer✅" : "I420⚠️"

        switch currentFrameCount {
        case 1:
            if let firstFrameCallback {
                Task { @MainActor in
                    firstFrameCallback()
                }
            }
            streamLog("[StreamView] first frame \(frame.width)x\(frame.height) buffer=\(bufferType)")
            logLumaSample(frame: frame, label: "first")
        case 60, 300:
            let elapsed = max(now - previousFrameTime, 0.000_001)
            let fps = Double(currentFrameCount == 60 ? 59 : 240) / elapsed
            streamLog("[StreamView] frame\(currentFrameCount) fps≈\(String(format: "%.1f", fps)) rtpDeltaMs=\(String(format: "%.1f", rtpDeltaMs)) buffer=\(bufferType)")
            logLumaSample(frame: frame, label: "frame\(currentFrameCount)")
        default:
            if currentFrameCount % 120 == 0 {
                let elapsed = max(now - previousFrameTime, 0.000_001)
                let fps = 120.0 / elapsed
                streamLog("[StreamView] heartbeat fc=\(currentFrameCount) fps≈\(String(format: "%.1f", fps)) rtpDeltaMs=\(String(format: "%.1f", rtpDeltaMs)) size=\(Int(currentSize.width))x\(Int(currentSize.height)) buffer=\(bufferType)")
            }
        }
    }

    private func logLumaSample(frame: RTCVideoFrame, label: String) {
        let i420Frame = frame.newI420()
        let buffer = i420Frame.buffer.toI420()
        let width = max(1, Int(buffer.width))
        let height = max(1, Int(buffer.height))
        let strideY = Int(buffer.strideY)
        let dataY = buffer.dataY
        let sampleCols = 16
        let sampleRows = 9
        var values: [Int] = []
        values.reserveCapacity(sampleCols * sampleRows)

        for row in 0..<sampleRows {
            let y = min(height - 1, (row * height) / sampleRows)
            for col in 0..<sampleCols {
                let x = min(width - 1, (col * width) / sampleCols)
                let value = Int(dataY[y * strideY + x])
                values.append(value)
            }
        }

        guard !values.isEmpty else { return }
        let minY = values.min() ?? 0
        let maxY = values.max() ?? 0
        let avgY = values.reduce(0, +) / values.count
        streamLog("[StreamView] FrameProbe luma \(label): avg=\(avgY) min=\(minY) max=\(maxY)")
    }
}
#endif
