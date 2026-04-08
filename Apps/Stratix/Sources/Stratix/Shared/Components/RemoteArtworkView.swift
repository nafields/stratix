// RemoteArtworkView.swift
// Defines the remote artwork view used in the Shared / Components surface.
//

import SwiftUI
import StratixCore

/// Thin shared wrapper that picks an artwork decode-size hint based on artwork role while
/// delegating the actual loading work to `CachedRemoteImage`.
struct RemoteArtworkView<Placeholder: View>: View {
    let url: URL?
    let kind: ArtworkKind
    let priority: ArtworkPriority
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    init(
        url: URL?,
        kind: ArtworkKind,
        priority: ArtworkPriority = .normal,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.kind = kind
        self.priority = priority
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        CachedRemoteImage(
            url: url,
            kind: kind,
            priority: priority,
            maxPixelSize: pixelSizeHint,
            contentMode: contentMode,
            placeholder: placeholder
        )
    }

    /// Keeps hero/poster/avatar requests on size-appropriate decode paths to reduce memory churn.
    private var pixelSizeHint: CGFloat? {
        switch kind {
        case .avatar:
            return 256
        case .poster:
            return 900
        case .hero:
            return 1_280
        }
    }
}

#if DEBUG
#Preview("RemoteArtworkView", traits: .fixedLayout(width: 1000, height: 560)) {
    RemoteArtworkView(
        url: nil,
        kind: .hero
    ) {
        ZStack {
            Color.gray.opacity(0.35)
            Image(systemName: "photo.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
#endif
