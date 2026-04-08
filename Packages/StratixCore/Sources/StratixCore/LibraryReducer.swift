// LibraryReducer.swift
// Defines library reducer.
//

import Foundation
import StratixModels

enum LibraryReducer {
    static func reduce(
        state: LibraryState,
        action: LibraryAction
    ) -> LibraryState {
        var next = state

        switch action {
        case .loadingStarted:
            next.isLoading = true

        case .loadingFinished:
            next.isLoading = false

        case .errorSet(let message):
            next.lastError = message

        case .needsReauthSet(let value):
            next.needsReauth = value

        case .sectionsReplaced(let sections):
            next.sections = sections
            let indexes = LibraryIndexBuilder.makeIndexes(from: sections)
            next.itemsByTitleID = indexes.byTitleID
            next.itemsByProductID = indexes.byProductID
            next.catalogRevision &+= 1
            next.sceneContentRevision &+= 1

        case .productDetailsReplaced(let details):
            next.productDetails = details
            next.detailRevision &+= 1
            next.sceneContentRevision &+= 1

        case .homeMerchandisingSet(let snapshot):
            next.homeMerchandising = snapshot
            next.homeRevision &+= 1
            next.sceneContentRevision &+= 1

        case .discoveryEntriesSet(let entries):
            next.discoveryEntries = entries
            next.homeRevision &+= 1
            next.sceneContentRevision &+= 1

        case .homeMerchandisingLoadingSet(let value):
            next.isHomeMerchandisingLoading = value

        case .homeMerchandisingCompletionSet(let value):
            next.hasCompletedInitialHomeMerchandising = value
            next.homeRevision &+= 1

        case .homeMerchandisingSessionSourceSet(let source):
            next.homeMerchandisingSessionSource = source
            next.hasRecoveredLiveHomeMerchandisingThisSession = (source == .liveRecovery)
            next.homeRevision &+= 1

        case .liveHomeRecoverySet(let value):
            next.hasRecoveredLiveHomeMerchandisingThisSession = value
            next.homeRevision &+= 1

        case .lastHydratedAtSet(let value):
            next.lastHydratedAt = value

        case .cacheSavedAtSet(let value):
            next.cacheSavedAt = value

        case .artworkPrefetchThrottleSet(let value):
            next.isArtworkPrefetchThrottled = value

        case .catalogRevisionIncremented:
            next.catalogRevision &+= 1

        case .detailRevisionIncremented:
            next.detailRevision &+= 1

        case .homeRevisionIncremented:
            next.homeRevision &+= 1

        case .sceneContentRevisionIncremented:
            next.sceneContentRevision &+= 1

        case .hydrationPublishedStateApplied(let published):
            next.sections = published.sections
            let indexes = LibraryIndexBuilder.makeIndexes(from: published.sections)
            next.itemsByTitleID = indexes.byTitleID
            next.itemsByProductID = indexes.byProductID
            next.homeMerchandising = published.homeMerchandising
            next.discoveryEntries = published.discovery?.entries ?? []
            next.hasCompletedInitialHomeMerchandising = published.isUnifiedHomeReady
            next.homeMerchandisingSessionSource = published.sessionSource
            next.hasRecoveredLiveHomeMerchandisingThisSession = (published.sessionSource == .liveRecovery)
            next.lastHydratedAt = published.savedAt
            next.cacheSavedAt = published.savedAt
            next.catalogRevision &+= 1
            next.homeRevision &+= 1
            next.sceneContentRevision &+= 1

        case .hydrationProductDetailsStateApplied(let detailsState):
            next.productDetails = detailsState.details
            next.detailRevision &+= 1
            next.sceneContentRevision &+= 1

        case .signedOutReset:
            next = .empty
        }

        return next
    }
}
