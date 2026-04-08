// CloudLibraryUtilityRouteActions.swift
// Defines cloud library utility route actions for the Features / CloudLibrary surface.
//

struct CloudLibraryUtilityRouteActions {
    let openConsoles: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    let refreshProfileData: @MainActor () -> Void
    let refreshFriends: @MainActor () -> Void
    let refreshCloudLibrary: @MainActor () -> Void
    let refreshConsoles: @MainActor () -> Void
    let signOut: @MainActor () -> Void
    let requestSideRailEntry: @MainActor () -> Void
    let exportPreviewDump: @MainActor () async -> String
}
