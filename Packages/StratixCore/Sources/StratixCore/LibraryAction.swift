// LibraryAction.swift
// Defines library action.
//

import Foundation
import StratixModels
import XCloudAPI

enum LibraryAction: Sendable, Equatable {
    case loadingStarted
    case loadingFinished
    case errorSet(String?)
    case needsReauthSet(Bool)

    case sectionsReplaced([CloudLibrarySection])
    case productDetailsReplaced([ProductID: CloudLibraryProductDetail])

    case homeMerchandisingSet(HomeMerchandisingSnapshot?)
    case discoveryEntriesSet([GamePassSiglDiscoveryEntry])
    case homeMerchandisingLoadingSet(Bool)
    case homeMerchandisingCompletionSet(Bool)
    case homeMerchandisingSessionSourceSet(HomeMerchandisingSessionSource)
    case liveHomeRecoverySet(Bool)

    case lastHydratedAtSet(Date?)
    case cacheSavedAtSet(Date?)
    case artworkPrefetchThrottleSet(Bool)

    case catalogRevisionIncremented
    case detailRevisionIncremented
    case homeRevisionIncremented
    case sceneContentRevisionIncremented

    case hydrationPublishedStateApplied(LibraryHydrationPublishedState)
    case hydrationProductDetailsStateApplied(LibraryHydrationProductDetailsState)

    case signedOutReset
}
