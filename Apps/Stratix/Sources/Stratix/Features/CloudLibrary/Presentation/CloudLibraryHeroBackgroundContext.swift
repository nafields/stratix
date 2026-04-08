// CloudLibraryHeroBackgroundContext.swift
// Defines cloud library hero background context for the Features / CloudLibrary surface.
//

struct CloudLibraryHeroBackgroundContext: Equatable {
    let inputs: CloudLibrarySceneModel.HeroBackgroundInputs
    let taskID: Int

    static let empty = CloudLibraryHeroBackgroundContext(
        inputs: .init(
            route: .home,
            utilityRouteVisible: false,
            detailHeroBackgroundURL: nil,
            homeFocusedHeroBackgroundURL: nil,
            libraryFocusedHeroBackgroundURL: nil,
            homeHeroBackgroundURL: nil,
            libraryHeroBackgroundURL: nil,
            searchHeroBackgroundURL: nil
        ),
        taskID: -1
    )
}
