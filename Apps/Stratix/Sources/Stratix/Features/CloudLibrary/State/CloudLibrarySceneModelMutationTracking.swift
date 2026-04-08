// CloudLibrarySceneModelMutationTracking.swift
// Defines cloud library scene model mutation tracking for the Features / CloudLibrary surface.
//

import StratixCore
import StratixModels

struct CloudLibrarySceneMutationState {
    var lastSceneMutationSignature: Int?
    var lastHydrationMarker: Date?
}

@MainActor
extension CloudLibrarySceneModel {
    func noteHydrationMarker(_ marker: Date?) {
        mutationState.lastHydrationMarker = marker
    }

    func isMajorLibraryRefresh(
        oldSections: [CloudLibrarySection],
        newSections: [CloudLibrarySection],
        currentHydratedAt: Date?
    ) -> Bool {
        guard !oldSections.isEmpty else {
            mutationState.lastHydrationMarker = currentHydratedAt
            return false
        }
        defer { mutationState.lastHydrationMarker = currentHydratedAt }
        if currentHydratedAt != mutationState.lastHydrationMarker {
            return true
        }

        let oldTitleIDs = Set(CloudLibraryDataSource.allLibraryItems(from: oldSections).map(\.typedTitleID))
        let newTitleIDs = Set(CloudLibraryDataSource.allLibraryItems(from: newSections).map(\.typedTitleID))
        return oldTitleIDs.symmetricDifference(newTitleIDs).count >= max(8, oldTitleIDs.count / 3)
    }

    func sceneMutationTaskID(
        libraryStateInputs: CloudLibraryStateSnapshot,
        queryState: LibraryQueryState,
        showsContinueBadge: Bool
    ) -> Int {
        sceneMutationSignature(
            catalogRevision: libraryStateInputs.catalogRevision,
            detailRevision: libraryStateInputs.detailRevision,
            homeRevision: libraryStateInputs.homeRevision,
            sceneContentRevision: libraryStateInputs.sceneContentRevision,
            queryState: queryState,
            showsContinueBadge: showsContinueBadge
        )
    }

    func applySceneMutation(
        libraryStateInputs: CloudLibraryStateSnapshot,
        queryState: LibraryQueryState,
        showsContinueBadge: Bool,
        viewModel: CloudLibraryViewModel
    ) {
        let signature = sceneMutationSignature(
            catalogRevision: libraryStateInputs.catalogRevision,
            detailRevision: libraryStateInputs.detailRevision,
            homeRevision: libraryStateInputs.homeRevision,
            sceneContentRevision: libraryStateInputs.sceneContentRevision,
            queryState: queryState,
            showsContinueBadge: showsContinueBadge
        )
        guard signature != mutationState.lastSceneMutationSignature else { return }
        mutationState.lastSceneMutationSignature = signature

        viewModel.applySceneMutation(
            inputs: CloudLibrarySceneInputs(
                library: libraryStateInputs,
                queryState: queryState,
                showsContinueBadge: showsContinueBadge
            )
        )
    }

    func sceneMutationSignature(
        catalogRevision: UInt64,
        detailRevision: UInt64,
        homeRevision: UInt64,
        sceneContentRevision: UInt64,
        queryState: LibraryQueryState,
        showsContinueBadge: Bool
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(catalogRevision)
        hasher.combine(detailRevision)
        hasher.combine(homeRevision)
        hasher.combine(sceneContentRevision)
        hasher.combine(queryStateToken(queryState))
        hasher.combine(showsContinueBadge)
        return hasher.finalize()
    }

    private func queryStateToken(_ queryState: LibraryQueryState) -> Int {
        var hasher = Hasher()
        hasher.combine(queryState.searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        hasher.combine(queryState.selectedTabID)
        hasher.combine(queryState.sortOption.rawValue)
        hasher.combine(queryState.displayMode.rawValue)
        for filterID in queryState.activeFilterIDs.sorted() {
            hasher.combine(filterID)
        }
        if let scopedCategory = queryState.scopedCategory {
            hasher.combine(scopedCategory.alias)
            hasher.combine(scopedCategory.label)
            for titleID in scopedCategory.allowedTitleIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
                hasher.combine(titleID.rawValue)
            }
        } else {
            hasher.combine("no_scoped_category")
        }
        return hasher.finalize()
    }
}
