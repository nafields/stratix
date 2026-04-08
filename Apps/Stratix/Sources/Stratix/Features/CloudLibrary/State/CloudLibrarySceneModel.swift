// CloudLibrarySceneModel.swift
// Defines the cloud library scene model.
//

import Foundation
import Observation
import StratixCore
import StratixModels

@Observable
@MainActor
/// Stores scene-level derived state that is rebuilt from route, status, and hero-background inputs.
final class CloudLibrarySceneModel {
    var statusState = CloudLibrarySceneStatusState()
    var routeState = CloudLibrarySceneRouteState()
    var heroBackgroundState = CloudLibraryHeroBackgroundState()
    var mutationState = CloudLibrarySceneMutationState()

    /// Marks the initial library load as complete once the load state reports the first finished pass.
    func reconcileInitialLibraryLoadState(loadState: CloudLibraryLoadState) {
        guard !statusState.hasCompletedInitialLibraryLoad else { return }
        if loadState.hasCompletedInitialLoad {
            statusState.hasCompletedInitialLibraryLoad = true
        }
    }

    /// Produces a stable task token for scene-status mutation work.
    func statusMutationTaskID(
        isHomeRoute: Bool,
        loadState: CloudLibraryLoadState,
        sections: [CloudLibrarySection],
        hasCompletedInitialHomeMerchandising: Bool,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool,
        hasHomeMerchandisingSnapshot: Bool,
        homeState: CloudLibraryHomeViewState
    ) -> Int {
        CloudLibrarySceneStatusState.signature(
            isHomeRoute: isHomeRoute,
            loadState: loadState,
            sections: sections,
            hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
            hasRecoveredLiveHomeMerchandisingThisSession: hasRecoveredLiveHomeMerchandisingThisSession,
            hasHomeMerchandisingSnapshot: hasHomeMerchandisingSnapshot,
            homeState: homeState
        )
    }

    /// Applies the latest status derivation while avoiding redundant publishes when nothing material changed.
    func applyStatusMutation(
        isHomeRoute: Bool,
        loadState: CloudLibraryLoadState,
        sections: [CloudLibrarySection],
        hasCompletedInitialHomeMerchandising: Bool,
        hasRecoveredLiveHomeMerchandisingThisSession: Bool,
        hasHomeMerchandisingSnapshot: Bool,
        homeState: CloudLibraryHomeViewState
    ) {
        reconcileInitialLibraryLoadState(loadState: loadState)

        let nextState = CloudLibrarySceneStatusState.resolve(
            current: statusState,
            isHomeRoute: isHomeRoute,
            loadState: loadState,
            sections: sections,
            hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
            hasRecoveredLiveHomeMerchandisingThisSession: hasRecoveredLiveHomeMerchandisingThisSession,
            hasHomeMerchandisingSnapshot: hasHomeMerchandisingSnapshot,
            homeState: homeState
        )
        guard nextState.hasCompletedInitialLibraryLoad != statusState.hasCompletedInitialLibraryLoad
            || nextState.homeMerchandisingReady != statusState.homeMerchandisingReady
            || nextState.homeMerchandisingStateValue != statusState.homeMerchandisingStateValue else {
            return
        }

        statusState.hasCompletedInitialLibraryLoad = nextState.hasCompletedInitialLibraryLoad
        statusState.homeMerchandisingReady = nextState.homeMerchandisingReady
        statusState.homeMerchandisingStateValue = nextState.homeMerchandisingStateValue
    }

    /// Produces a stable task token for scene-route mutation work.
    func routeMutationTaskID(
        browseRouteRawValue: String,
        utilityRouteRawValue: String?
    ) -> Int {
        CloudLibrarySceneRouteState.signature(
            browseRouteRawValue: browseRouteRawValue,
            utilityRouteRawValue: utilityRouteRawValue
        )
    }

    /// Rebuilds the scene route projection only when browse or utility route identity has materially changed.
    func applyRouteMutation(
        browseRouteRawValue: String,
        utilityRouteRawValue: String?
    ) {
        let signature = routeMutationTaskID(
            browseRouteRawValue: browseRouteRawValue,
            utilityRouteRawValue: utilityRouteRawValue
        )
        guard signature != routeState.lastSignature else { return }
        routeState.lastSignature = signature

        let nextState = CloudLibrarySceneRouteState.resolve(
            browseRouteRawValue: browseRouteRawValue,
            utilityRouteRawValue: utilityRouteRawValue
        )
        guard routeState.currentSurfaceID != nextState.currentSurfaceID
            || routeState.selectedSideRailNavID != nextState.selectedSideRailNavID else {
            return
        }

        routeState.currentSurfaceID = nextState.currentSurfaceID
        routeState.selectedSideRailNavID = nextState.selectedSideRailNavID
    }

    /// Produces a stable task token for hero-background mutation work.
    func heroBackgroundMutationTaskID(inputs: HeroBackgroundInputs) -> Int {
        CloudLibraryHeroBackgroundState.signature(inputs: inputs)
    }

    /// Commits the resolved shell hero background only after the inputs hash changes.
    func applyHeroBackgroundMutation(inputs: HeroBackgroundInputs) {
        let signature = heroBackgroundMutationTaskID(inputs: inputs)
        guard signature != heroBackgroundState.lastSignature else { return }
        heroBackgroundState.lastSignature = signature

        let nextState = CloudLibraryHeroBackgroundState.resolve(inputs: inputs)
        guard heroBackgroundState.shellHeroBackgroundURL != nextState.shellHeroBackgroundURL else { return }
        heroBackgroundState.shellHeroBackgroundURL = nextState.shellHeroBackgroundURL
    }
}
