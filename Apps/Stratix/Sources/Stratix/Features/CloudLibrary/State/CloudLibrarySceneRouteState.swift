// CloudLibrarySceneRouteState.swift
// Defines the cloud library scene route state.
//

import StratixCore

struct CloudLibrarySceneRouteState {
    var currentSurfaceID = "home"
    var selectedSideRailNavID: SideRailNavID = .home
    var lastSignature: Int?

    static func signature(
        browseRouteRawValue: String,
        utilityRouteRawValue: String?
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(browseRouteRawValue)
        hasher.combine(utilityRouteRawValue ?? "")
        return hasher.finalize()
    }

    static func resolve(
        browseRouteRawValue: String,
        utilityRouteRawValue: String?
    ) -> Self {
        .init(
            currentSurfaceID: utilityRouteRawValue ?? browseRouteRawValue,
            selectedSideRailNavID: SideRailNavID(rawValue: browseRouteRawValue) ?? .home
        )
    }
}
