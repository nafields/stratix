// CloudLibraryLoadStateTests.swift
// Exercises cloud library load state behavior.
//

import XCTest
import StratixModels
@testable import StratixCore

#if canImport(Stratix)
@testable import Stratix
#endif

final class CloudLibraryLoadStateTests: XCTestCase {
    func testInitialLoadResolutionMatchesLoadStateContract() {
        XCTAssertFalse(CloudLibraryLoadState.notLoaded.hasCompletedInitialLoad)
        XCTAssertTrue(CloudLibraryLoadState.restoredCached(ageSeconds: 1).hasCompletedInitialLoad)
        XCTAssertTrue(CloudLibraryLoadState.refreshingFromCache(ageSeconds: 1).hasCompletedInitialLoad)
        XCTAssertTrue(CloudLibraryLoadState.liveFresh.hasCompletedInitialLoad)
        XCTAssertTrue(CloudLibraryLoadState.degradedCached(error: "offline_error", ageSeconds: 1).hasCompletedInitialLoad)
        XCTAssertTrue(CloudLibraryLoadState.failedNoCache(error: "offline_error").hasCompletedInitialLoad)
    }

    @MainActor
    func testNotLoadedWhenNoSectionsNoMerchandisingNoErrorNoCache() {
        let builder = CloudLibraryLoadStateBuilder(now: { Date(timeIntervalSince1970: 100) })
        let state = CloudLibraryTestSupport.makeLibraryState()

        XCTAssertEqual(builder.makeLoadState(from: state), .notLoaded)
    }

    @MainActor
    func testRestoredCachedWhenStateHasDataAndCacheButNoLiveRecovery() {
        let builder = CloudLibraryLoadStateBuilder(now: { Date(timeIntervalSince1970: 160) })
        let snapshot = CloudLibraryTestSupport.makeLibraryStateSnapshot(
            sections: sampleSections(),
            cacheSavedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(builder.makeLoadState(from: snapshot), .restoredCached(ageSeconds: 60))
    }

    @MainActor
    func testRefreshingFromCacheWhenStateHasCachedDataAndIsLoading() {
        let builder = CloudLibraryLoadStateBuilder(now: { Date(timeIntervalSince1970: 160) })
        let state = CloudLibraryTestSupport.makeLibraryState(
            sections: sampleSections(),
            isLoading: true,
            cacheSavedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(builder.makeLoadState(from: state), .refreshingFromCache(ageSeconds: 60))
    }

    @MainActor
    func testLiveFreshWhenStateHasDataAndRecoveredLiveHomeMerchandising() {
        let builder = CloudLibraryLoadStateBuilder(now: { Date(timeIntervalSince1970: 160) })
        let state = CloudLibraryTestSupport.makeLibraryState(
            sections: sampleSections(),
            cacheSavedAt: Date(timeIntervalSince1970: 100),
            hasRecoveredLiveHomeMerchandisingThisSession: true
        )

        XCTAssertEqual(builder.makeLoadState(from: state), .liveFresh)
    }

    @MainActor
    func testDegradedCachedWhenStateHasCacheAndError() {
        let builder = CloudLibraryLoadStateBuilder(now: { Date(timeIntervalSince1970: 190) })
        let state = CloudLibraryTestSupport.makeLibraryState(
            sections: sampleSections(),
            lastError: "offline_error",
            cacheSavedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(builder.makeLoadState(from: state), .degradedCached(error: "offline_error", ageSeconds: 90))
    }

    @MainActor
    func testFailedNoCacheWhenStateHasNoDataAndError() {
        let builder = CloudLibraryLoadStateBuilder(now: { Date(timeIntervalSince1970: 190) })
        let state = CloudLibraryTestSupport.makeLibraryState(lastError: "offline_error")

        XCTAssertEqual(builder.makeLoadState(from: state), .failedNoCache(error: "offline_error"))
    }

    @MainActor
    private func sampleSections() -> [CloudLibrarySection] {
        [CloudLibrarySection(id: "library", name: "Library", items: [CloudLibraryTestSupport.makeItem()])]
    }
}
