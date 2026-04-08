// CloudLibraryHeroBackgroundState.swift
// Defines the cloud library hero background state.
//

import Foundation

struct CloudLibraryHeroBackgroundState {
    var shellHeroBackgroundURL: URL?
    var lastSignature: Int?

    static func signature(inputs: CloudLibrarySceneModel.HeroBackgroundInputs) -> Int {
        var hasher = Hasher()
        hasher.combine(inputs.route.rawValue)
        hasher.combine(inputs.utilityRouteVisible)
        hasher.combine(inputs.detailHeroBackgroundURL?.absoluteString)
        hasher.combine(inputs.homeFocusedHeroBackgroundURL?.absoluteString)
        hasher.combine(inputs.libraryFocusedHeroBackgroundURL?.absoluteString)
        hasher.combine(inputs.homeHeroBackgroundURL?.absoluteString)
        hasher.combine(inputs.libraryHeroBackgroundURL?.absoluteString)
        hasher.combine(inputs.searchHeroBackgroundURL?.absoluteString)
        return hasher.finalize()
    }

    static func resolve(inputs: CloudLibrarySceneModel.HeroBackgroundInputs) -> Self {
        .init(
            shellHeroBackgroundURL: resolvedShellHeroBackgroundURL(inputs: inputs)
        )
    }

    private static func resolvedShellHeroBackgroundURL(
        inputs: CloudLibrarySceneModel.HeroBackgroundInputs
    ) -> URL? {
        guard inputs.utilityRouteVisible || inputs.route != .home else {
            return nil
        }

        if let detailHeroBackgroundURL = inputs.detailHeroBackgroundURL {
            return detailHeroBackgroundURL
        }

        switch inputs.route {
        case .home:
            return inputs.homeFocusedHeroBackgroundURL ?? inputs.homeHeroBackgroundURL
        case .library:
            return inputs.libraryFocusedHeroBackgroundURL ?? inputs.libraryHeroBackgroundURL
        case .search:
            return inputs.searchHeroBackgroundURL
        case .consoles:
            return nil
        }
    }
}

extension CloudLibrarySceneModel {
    struct HeroBackgroundInputs: Equatable {
        let route: HeroBackgroundRoute
        let utilityRouteVisible: Bool
        let detailHeroBackgroundURL: URL?
        let homeFocusedHeroBackgroundURL: URL?
        let libraryFocusedHeroBackgroundURL: URL?
        let homeHeroBackgroundURL: URL?
        let libraryHeroBackgroundURL: URL?
        let searchHeroBackgroundURL: URL?
    }

    enum HeroBackgroundRoute: String {
        case home
        case library
        case search
        case consoles
    }

    static func heroBackgroundTaskID(inputs: HeroBackgroundInputs) -> Int {
        CloudLibraryHeroBackgroundState.signature(inputs: inputs)
    }
}
