// StreamControllerInputHost.swift
// Defines stream controller input host for the Features / Streaming surface.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(GameController)
import GameController
#endif

#if os(tvOS) && canImport(UIKit) && canImport(GameController)
/// Root modal host for stream screens.
/// Uses GCEventViewController as the presented root to intercept controller menu/back presses
/// before tvOS dismisses the fullScreenCover.
struct StreamControllerInputHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let onOverlayToggle: (() -> Void)?
    let onMenuPress: (() -> Void)?

    init(
        onOverlayToggle: (() -> Void)? = nil,
        onMenuPress: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.onOverlayToggle = onOverlayToggle
        self.onMenuPress = onMenuPress
        self.content = content()
    }

    func makeUIViewController(context: Context) -> StreamControllerInputViewController<Content> {
        StreamControllerInputViewController(
            rootView: content,
            onOverlayToggle: onOverlayToggle,
            onMenuPress: onMenuPress
        )
    }

    func updateUIViewController(_ uiViewController: StreamControllerInputViewController<Content>, context: Context) {
        uiViewController.hostingController.rootView = content
        uiViewController.onOverlayToggle = onOverlayToggle
        uiViewController.onMenuPress = onMenuPress
    }
}

final class StreamControllerInputViewController<Content: View>: GCEventViewController {
    let hostingController: UIHostingController<Content>
    var onOverlayToggle: (() -> Void)?
    var onMenuPress: (() -> Void)?

    init(
        rootView: Content,
        onOverlayToggle: (() -> Void)? = nil,
        onMenuPress: (() -> Void)? = nil
    ) {
        self.hostingController = UIHostingController(rootView: rootView)
        self.onOverlayToggle = onOverlayToggle
        self.onMenuPress = onMenuPress
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.insetsLayoutMarginsFromSafeArea = false
        // Disable controller-driven tvOS UI commands while streaming (B/Menu/etc).
        // Game input still arrives via GCController APIs.
        controllerUserInteractionEnabled = false

        hostingController.view.backgroundColor = .clear
        hostingController.view.insetsLayoutMarginsFromSafeArea = false

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if shouldHandleOverlayPress(presses) { return }
        if shouldSwallowMenuPress(presses) { return }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if shouldHandleOverlayPress(presses) {
            onOverlayToggle?()
            return
        }
        if shouldSwallowMenuPress(presses) {
            // Still swallow so tvOS never dismisses the stream cover, but give the
            // Siri Remote's back button a job: surface (or hide) the stream overlay
            // instead of silently doing nothing.
            onMenuPress?()
            return
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if shouldHandleOverlayPress(presses) { return }
        if shouldSwallowMenuPress(presses) { return }
        super.pressesCancelled(presses, with: event)
    }

    private func shouldSwallowMenuPress(_ presses: Set<UIPress>) -> Bool {
        presses.contains { $0.type == .menu }
    }

    private func shouldHandleOverlayPress(_ presses: Set<UIPress>) -> Bool {
        presses.contains { $0.type == .playPause }
    }
}
#else
struct StreamControllerInputHost<Content: View>: View {
    let content: Content

    init(
        onOverlayToggle: (() -> Void)? = nil,
        onMenuPress: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        _ = onOverlayToggle
        _ = onMenuPress
        self.content = content()
    }

    var body: some View { content }
}
#endif
