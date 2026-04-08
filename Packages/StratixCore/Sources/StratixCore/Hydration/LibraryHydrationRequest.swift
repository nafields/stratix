// LibraryHydrationRequest.swift
// Defines library hydration request for the Hydration surface.
//

import Foundation

enum LibraryHydrationTrigger: Sendable, Equatable {
    case shellBoot
    case startupRestore
    case liveRefresh
    case postStreamDelta
    case foregroundResume
    case backgroundWarm
}

struct LibraryHydrationRequest: Sendable, Equatable {
    let trigger: LibraryHydrationTrigger
    let market: String
    let language: String
    let preferDeltaRefresh: Bool
    let forceFullRefresh: Bool
    let allowCacheRestore: Bool
    let allowPersistenceWrite: Bool
    let deferInitialRoutePublication: Bool
    let refreshReason: CloudLibraryRefreshReason?
    let sourceDescription: String
}
