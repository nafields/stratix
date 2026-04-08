// AppCoordinatorTestingSupport.swift
// Provides shared support for the App surface.
//

import Foundation
import XCloudAPI

#if DEBUG
@MainActor
extension AppCoordinator {
    func testingApplyTokensFull(_ tokens: StreamTokens) async {
        await sessionController.applyTokensFromCoordinator(tokens, mode: .full)
    }

    func testingApplyTokensStreamRefresh(_ tokens: StreamTokens) async {
        await sessionController.applyTokensFromCoordinator(tokens, mode: .streamRefresh)
    }

    func testingEffectivePreferredRegionId() -> String? {
        StreamRegionSelectionPolicy()
            .effectiveSelection(
                streamSettings: settingsStore.stream,
                availableRegions: sessionController.xcloudRegions
            )
            .regionId
    }

    func testingSetXCloudRegions(_ regions: [LoginRegion]) {
        sessionController.testingSetXCloudRegions(regions)
    }

    func testingSetIsStartingStream(_ value: Bool) {
        streamController.testingSetIsStartingStream(value)
    }

    func testingIsCloudLibraryLoadTaskActive() async -> Bool {
        await libraryController.testingIsLoadTaskActive()
    }

    var testingPostStreamRefreshInvocationCount: Int {
        streamPriorityShellController.invocationCount
    }

    var testingPostStreamDeltaAttemptCount: Int {
        streamPriorityShellController.deltaAttemptCount
    }

    var testingPostStreamFullRefreshFallbackCount: Int {
        streamPriorityShellController.fullRefreshFallbackCount
    }

    func testingSetPostStreamDeltaRefreshOverride(
        _ action: (@MainActor () async -> PostStreamRefreshResult)?
    ) {
        streamPriorityShellController.testingPostStreamDeltaRefreshOverride = action
    }

    func testingSetPostStreamFullRefreshOverride(
        _ action: (@MainActor () async -> Void)?
    ) {
        streamPriorityShellController.testingPostStreamFullRefreshOverride = action
    }
}
#endif
