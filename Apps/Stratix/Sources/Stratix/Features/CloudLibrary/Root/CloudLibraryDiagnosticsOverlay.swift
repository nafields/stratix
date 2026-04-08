// CloudLibraryDiagnosticsOverlay.swift
// Defines cloud library diagnostics overlay for the CloudLibrary / Root surface.
//

import SwiftUI

struct CloudLibraryDiagnosticsOverlay: View {
    let browseRouteRawValue: String
    let homeLoadStateValue: String
    let routeRestoreStateValue: String
    let homeMerchandisingReady: Bool
    let homeMerchandisingStateValue: String

    var body: some View {
        Group {
            Text("home_merchandising_state")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("home_merchandising_state")
                .accessibilityValue(homeMerchandisingStateValue)

            Text("browse_route_state")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("browse_route_state")
                .accessibilityValue(browseRouteRawValue)

            Text("home_load_state")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("home_load_state")
                .accessibilityValue(homeLoadStateValue)

            Text("route_restore_state")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("route_restore_state")
                .accessibilityValue(routeRestoreStateValue)

            if homeMerchandisingReady {
                Text("home_merchandising_ready")
                    .font(.caption2)
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("home_merchandising_ready")
                    .accessibilityValue("ready")
            }
        }
    }
}
