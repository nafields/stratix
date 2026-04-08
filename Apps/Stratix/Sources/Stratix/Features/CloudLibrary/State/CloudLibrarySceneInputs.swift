// CloudLibrarySceneInputs.swift
// Defines cloud library scene inputs for the Features / CloudLibrary surface.
//

struct CloudLibrarySceneInputs: Equatable {
    let library: CloudLibraryStateSnapshot
    let queryState: LibraryQueryState
    let showsContinueBadge: Bool
}
