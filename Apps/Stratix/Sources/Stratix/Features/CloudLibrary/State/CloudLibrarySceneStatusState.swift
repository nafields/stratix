// CloudLibrarySceneStatusState.swift
// Defines the cloud library scene status state.
//

import StratixCore
import StratixModels

struct CloudLibrarySceneStatusState {
    var hasCompletedInitialLibraryLoad = false
    var homeMerchandisingReady = false
    var homeMerchandisingStateValue = "uninitialized"

    static func signature(
        isHomeRoute: Bool,
        loadState: CloudLibraryLoadState,
        sections: [CloudLibrarySection],
        hasCompletedInitialHomeMerchandising: Bool,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool,
        hasHomeMerchandisingSnapshot: Bool,
        homeState: CloudLibraryHomeViewState
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(isHomeRoute)
        hasher.combine(loadState)
        hasher.combine(sections.isEmpty)
        hasher.combine(sections.reduce(0) { $0 + $1.items.count })
        hasher.combine(hasCompletedInitialHomeMerchandising)
        hasher.combine(hasRecoveredLiveHomeMerchandisingThisSession)
        hasher.combine(hasHomeMerchandisingSnapshot)
        hasher.combine(homeState.carouselItems.count)
        hasher.combine(homeState.sections.count)
        hasher.combine(homeState.sections.reduce(0) { $0 + $1.items.count })
        return hasher.finalize()
    }

    static func resolve(
        current: CloudLibrarySceneStatusState,
        isHomeRoute: Bool,
        loadState: CloudLibraryLoadState,
        sections: [CloudLibrarySection],
        hasCompletedInitialHomeMerchandising: Bool,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool,
        hasHomeMerchandisingSnapshot: Bool,
        homeState: CloudLibraryHomeViewState
    ) -> Self {
        let hasCompletedInitialLibraryLoad =
            current.hasCompletedInitialLibraryLoad || loadState.hasCompletedInitialLoad

        let homeMerchandisingReady = computeHomeMerchandisingReady(
            isHomeRoute: isHomeRoute,
            loadState: loadState,
            hasCompletedInitialLibraryLoad: hasCompletedInitialLibraryLoad,
            hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
            hasRecoveredLiveHomeMerchandisingThisSession: hasRecoveredLiveHomeMerchandisingThisSession,
            hasHomeMerchandisingSnapshot: hasHomeMerchandisingSnapshot,
            homeState: homeState
        )

        return .init(
            hasCompletedInitialLibraryLoad: hasCompletedInitialLibraryLoad,
            homeMerchandisingReady: homeMerchandisingReady,
            homeMerchandisingStateValue: makeHomeMerchandisingStateValue(
                isHomeRoute: isHomeRoute,
                isReady: homeMerchandisingReady,
                loadState: loadState,
                sections: sections,
                hasCompletedInitialLibraryLoad: hasCompletedInitialLibraryLoad,
                hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
                hasRecoveredLiveHomeMerchandisingThisSession: hasRecoveredLiveHomeMerchandisingThisSession,
                hasHomeMerchandisingSnapshot: hasHomeMerchandisingSnapshot,
                homeState: homeState
            )
        )
    }

    private static func computeHomeMerchandisingReady(
        isHomeRoute: Bool,
        loadState: CloudLibraryLoadState,
        hasCompletedInitialLibraryLoad: Bool,
        hasCompletedInitialHomeMerchandising: Bool,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool,
        hasHomeMerchandisingSnapshot: Bool,
        homeState: CloudLibraryHomeViewState
    ) -> Bool {
        guard isHomeRoute,
              hasCompletedInitialLibraryLoad,
              hasCompletedInitialHomeMerchandising,
              hasRecoveredLiveHomeMerchandisingThisSession,
              hasHomeMerchandisingSnapshot,
              loadState.isLiveFresh else {
            return false
        }

        return !homeState.carouselItems.isEmpty
            || homeState.sections.contains(where: { !$0.items.isEmpty })
    }

    private static func makeHomeMerchandisingStateValue(
        isHomeRoute: Bool,
        isReady: Bool,
        loadState: CloudLibraryLoadState,
        sections: [CloudLibrarySection],
        hasCompletedInitialLibraryLoad: Bool,
        hasCompletedInitialHomeMerchandising: Bool,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool,
        hasHomeMerchandisingSnapshot: Bool,
        homeState: CloudLibraryHomeViewState
    ) -> String {
        let catalogItemCount = sections.reduce(0) { $0 + $1.items.count }
        return [
            "route=\(isHomeRoute ? "home" : "other")",
            "ready=\(isReady ? 1 : 0)",
            "loadState=\(loadState.diagnosticsValue)",
            "libraryLoaded=\(hasCompletedInitialLibraryLoad ? 1 : 0)",
            "initial=\(hasCompletedInitialHomeMerchandising ? 1 : 0)",
            "live=\(hasRecoveredLiveHomeMerchandisingThisSession ? 1 : 0)",
            "snapshot=\(hasHomeMerchandisingSnapshot ? 1 : 0)",
            "catalogSections=\(sections.count)",
            "catalogItems=\(catalogItemCount)",
            "carousel=\(homeState.carouselItems.count)",
            "rails=\(homeState.sections.count)"
        ].joined(separator: ";")
    }
}
