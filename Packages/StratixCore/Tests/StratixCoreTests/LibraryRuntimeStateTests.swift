// LibraryRuntimeStateTests.swift
// Exercises library runtime state behavior.
//

import Foundation
@testable import StratixCore
import Testing
import StratixModels

@Suite
struct LibraryRuntimeStateTests {
    @Test
    func init_providesExpectedInitialValues() {
        let state = LibraryRuntimeState()

        #expect(state.hasPerformedNetworkHydrationThisSession == false)
        #expect(state.hasLoadedProductDetailsCache == false)
        #expect(state.hasLoadedSectionsCache == false)
        #expect(state.isArtworkPrefetchDisabledForSession == false)
        #expect(state.isSuspendedForStreaming == false)
        #expect(state.lastArtworkPrefetchStartedAt == nil)
        #expect(state.artworkPrefetchLastCompletedAtByURL.isEmpty)
        #expect(state.cachedHomeMerchandisingDiscovery == nil)
    }

    @Test
    func runtimeReducer_appliesHydrationAndCacheLoadFlags() {
        let initial = LibraryRuntimeState()

        let hydrated = LibraryRuntimeReducer.reduce(
            state: initial,
            action: .networkHydrationPerformedSet(true)
        )
        #expect(hydrated.hasPerformedNetworkHydrationThisSession == true)
        #expect(hydrated.hasLoadedProductDetailsCache == false)
        #expect(hydrated.hasLoadedSectionsCache == false)

        let productCacheLoaded = LibraryRuntimeReducer.reduce(
            state: hydrated,
            action: .loadedProductDetailsCacheSet(true)
        )
        #expect(productCacheLoaded.hasPerformedNetworkHydrationThisSession == true)
        #expect(productCacheLoaded.hasLoadedProductDetailsCache == true)
        #expect(productCacheLoaded.hasLoadedSectionsCache == false)

        let sectionsCacheLoaded = LibraryRuntimeReducer.reduce(
            state: productCacheLoaded,
            action: .loadedSectionsCacheSet(true)
        )
        #expect(sectionsCacheLoaded.hasPerformedNetworkHydrationThisSession == true)
        #expect(sectionsCacheLoaded.hasLoadedProductDetailsCache == true)
        #expect(sectionsCacheLoaded.hasLoadedSectionsCache == true)

        let artworkDisabled = LibraryRuntimeReducer.reduce(
            state: sectionsCacheLoaded,
            action: .artworkPrefetchDisabledForSessionSet(true)
        )
        #expect(artworkDisabled.isArtworkPrefetchDisabledForSession == true)

        let startedAt = Date(timeIntervalSince1970: 456)
        let prefetchStarted = LibraryRuntimeReducer.reduce(
            state: artworkDisabled,
            action: .artworkPrefetchStartedAtSet(startedAt)
        )
        #expect(prefetchStarted.lastArtworkPrefetchStartedAt == startedAt)

        let completionMap = ["https://example.com/a.png": Date(timeIntervalSince1970: 789)]
        let completionUpdated = LibraryRuntimeReducer.reduce(
            state: prefetchStarted,
            action: .artworkPrefetchLastCompletedAtByURLSet(completionMap)
        )
        #expect(completionUpdated.artworkPrefetchLastCompletedAtByURL == completionMap)

        let suspended = LibraryRuntimeReducer.reduce(
            state: completionUpdated,
            action: .suspendedForStreamingSet(true)
        )
        #expect(suspended.isSuspendedForStreaming == true)
    }

    @MainActor
    @Test
    func runtimeSidecars_doNotBecomeCanonicalLibraryState() {
        let controller = LibraryController()
        let baselineState = controller.state
        let cachedDiscovery = HomeMerchandisingDiscoveryCachePayload(
            entries: [],
            savedAt: Date(timeIntervalSince1970: 456)
        )

        controller.hasPerformedNetworkHydrationThisSession = true
        controller.hasLoadedProductDetailsCache = true
        controller.hasLoadedSectionsCache = true
        controller.isArtworkPrefetchDisabledForSession = true
        controller.isSuspendedForStreaming = true
        controller.lastArtworkPrefetchStartedAt = Date(timeIntervalSince1970: 123)
        controller.artworkPrefetchLastCompletedAtByURL = ["https://example.com/art.png": .now]
        controller.cachedHomeMerchandisingDiscovery = cachedDiscovery

        #expect(controller.state == baselineState)
        #expect(controller.sections.isEmpty)
        #expect(controller.itemsByTitleID.isEmpty)
        #expect(controller.productDetails.isEmpty)
        #expect(controller.homeMerchandising == nil)
        #expect(controller.discoveryEntries.isEmpty)
        #expect(controller.cachedHomeMerchandisingDiscovery == cachedDiscovery)
    }
}
