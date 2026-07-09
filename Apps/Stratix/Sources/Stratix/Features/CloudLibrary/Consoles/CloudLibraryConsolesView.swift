// CloudLibraryConsolesView.swift
// Defines the cloud library consoles view used in the CloudLibrary / Consoles surface.
//

import SwiftUI
import StratixCore

struct CloudLibraryConsolesView: View {
    var onRequestSideRailEntry: () -> Void = {}
    var focusHandoffRequest: CloudLibraryFocusState.ContentFocusRequest? = nil

    var body: some View {
        ConsoleListView(
            onRequestSideRailEntry: onRequestSideRailEntry,
            focusHandoffRequest: focusHandoffRequest
        )
    }
}

#if DEBUG
#Preview("CloudLibraryConsolesView", traits: .fixedLayout(width: 1920, height: 1080)) {
    let coordinator = AppCoordinator()
    ZStack {
        CloudLibraryAmbientBackground(imageURL: nil)
        CloudLibraryConsolesView()
            .environment(coordinator.consoleController)
            .environment(coordinator.streamController)
    }
}
#endif
