// LibraryHydrationStartupRestoreWorkflow.swift
// Defines library hydration startup restore workflow for the Hydration surface.
//

import Foundation

protocol LibraryHydrationStartupRestoring: Sendable {
    func run(
        request: LibraryHydrationRequest,
        planner: any LibraryHydrationPlanning,
        worker: any LibraryHydrationWorking,
        shouldLoadProductDetails: Bool,
        shouldLoadSections: Bool,
        expectedCacheVersion: Int
    ) async -> LibraryStartupRestoreResult
}

struct LibraryHydrationStartupRestoreWorkflow: LibraryHydrationStartupRestoring {
    func run(
        request: LibraryHydrationRequest,
        planner: any LibraryHydrationPlanning,
        worker: any LibraryHydrationWorking,
        shouldLoadProductDetails: Bool,
        shouldLoadSections: Bool,
        expectedCacheVersion: Int
    ) async -> LibraryStartupRestoreResult {
        guard request.allowCacheRestore else {
            return LibraryStartupRestoreResult(productDetails: nil, sections: nil)
        }

        let startupCachePayload = await worker.loadStartupCachePayload(
            loadProductDetails: shouldLoadProductDetails,
            loadSections: shouldLoadSections
        )

        return planner.makeStartupRestoreResult(
            payload: startupCachePayload,
            shouldLoadProductDetails: shouldLoadProductDetails,
            shouldLoadSections: shouldLoadSections,
            expectedCacheVersion: expectedCacheVersion
        )
    }
}
