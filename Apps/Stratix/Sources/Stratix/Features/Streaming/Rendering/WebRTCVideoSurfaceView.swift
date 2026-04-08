// WebRTCVideoSurfaceView.swift
// Defines the web rtc video surface view used in the Features / Streaming surface.
//

import SwiftUI
import StratixCore

#if WEBRTC_AVAILABLE && canImport(UIKit)
/// Bridges the stream's renderer coordinator into a UIKit-backed video surface.
struct WebRTCVideoSurfaceView: UIViewRepresentable {
    let videoTrack: AnyObject?
    let attachmentCoordinator: RendererAttachmentCoordinator
    let callbacks: RendererAttachmentCoordinator.Callbacks
    @Environment(SettingsStore.self) private var settingsStore

    /// Derives the renderer configuration from the current settings store and callbacks.
    private var configuration: RendererAttachmentCoordinator.Configuration {
        .make(settingsStore: settingsStore, callbacks: callbacks)
    }

    /// Reuses the supplied attachment coordinator as the UIKit representable coordinator.
    func makeCoordinator() -> RendererAttachmentCoordinator {
        attachmentCoordinator
    }

    /// Creates the host container and installs the renderer stack into it.
    func makeUIView(context: Context) -> UIView {
        let container = RendererContainerView()
        context.coordinator.install(in: container, configuration: configuration)
        context.coordinator.update(
            in: container,
            videoTrack: videoTrack,
            configuration: configuration
        )
        return container
    }

    /// Updates the host container when track or configuration state changes.
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(
            in: uiView,
            videoTrack: videoTrack,
            configuration: configuration
        )
    }

    /// Clears renderer attachments when the UIKit surface is torn down.
    static func dismantleUIView(_ uiView: UIView, coordinator: RendererAttachmentCoordinator) {
        coordinator.clear()
    }
}
#else
/// Fallback SwiftUI stub used when WebRTC or UIKit is unavailable.
struct WebRTCVideoSurfaceView: View {
    let videoTrack: AnyObject?
    let attachmentCoordinator: AnyObject
    let callbacks: AnyObject

    var body: some View {
        Color.black
    }
}
#endif
