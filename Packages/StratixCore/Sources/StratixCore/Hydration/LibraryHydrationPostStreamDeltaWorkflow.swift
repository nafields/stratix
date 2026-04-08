// LibraryHydrationPostStreamDeltaWorkflow.swift
// Defines library hydration post stream delta workflow for the Hydration surface.
//

import Foundation
import StratixModels

protocol LibraryHydrationPostStreamDeltaRunning: Sendable {
    @MainActor
    func run(
        request: LibraryHydrationRequest,
        dependencies: LibraryHydrationPostStreamDeltaWorkflow.Dependencies
    ) async throws -> LibraryHydrationOrchestrationResult
}

@MainActor
struct LibraryHydrationPostStreamDeltaWorkflow: LibraryHydrationPostStreamDeltaRunning {
    struct Dependencies {
        let fetchLiveMRUEntries: () async throws -> [LibraryMRUEntry]
        let applySectionsDelta: (_ liveMRUEntries: [LibraryMRUEntry]) -> MRUDeltaSectionsResult
        let refreshMerchandising: (_ sections: [CloudLibrarySection], _ market: String, _ language: String) async -> HomeMerchandisingRefreshResult
        let now: () -> Date
        let logInfo: (String) -> Void
        let logWarning: (String) -> Void
        let logDebug: (String) -> Void
        let describeSections: ([CloudLibrarySection]) -> String
        let describeHomeMerchandising: (HomeMerchandisingSnapshot?) -> String
        let describeDiscovery: (HomeMerchandisingDiscoveryCachePayload?) -> String
        let formattedAge: (Date) -> String
    }

    func run(
        request: LibraryHydrationRequest,
        dependencies: Dependencies
    ) async throws -> LibraryHydrationOrchestrationResult {
        let liveMRUEntries = try await dependencies.fetchLiveMRUEntries()
        let updatedSections = dependencies.applySectionsDelta(liveMRUEntries)
        switch updatedSections {
        case .requiresFullRefresh(let reason):
            dependencies.logInfo("Post-stream MRU delta apply escalated to full refresh: \(reason)")
            return LibraryHydrationOrchestrationResult(
                actions: [],
                persistenceIntent: .none,
                cachedDiscovery: nil,
                source: .postStreamDelta,
                publicationPlan: LibraryHydrationPublicationPlan(stages: []),
                postStreamResult: .requiresFullRefresh(reason)
            )
        case .noChange:
            dependencies.logInfo("Post-stream MRU delta apply skipped: no section changes")
            return LibraryHydrationOrchestrationResult(
                actions: [],
                persistenceIntent: .none,
                cachedDiscovery: nil,
                source: .postStreamDelta,
                publicationPlan: LibraryHydrationPublicationPlan(stages: []),
                postStreamResult: .noChange
            )
        case .updated(let sections):
            let merchandisingResult = await dependencies.refreshMerchandising(
                sections,
                request.market,
                request.language
            )
            let savedAt = dependencies.now()
            let recoveryState = LibraryHydrationRecoveryState.postStreamDelta(
                sections: sections,
                homeMerchandising: merchandisingResult.snapshot,
                discovery: merchandisingResult.discovery,
                savedAt: savedAt
            )
            dependencies.logDebug(
                "post_stream_delta_applied age=\(dependencies.formattedAge(savedAt)) liveMRU=\(liveMRUEntries.count) \(dependencies.describeSections(sections)) \(dependencies.describeHomeMerchandising(merchandisingResult.snapshot)) \(dependencies.describeDiscovery(merchandisingResult.discovery))"
            )

            return LibraryHydrationOrchestrationResult(
                actions: [.hydrationPublishedStateApplied(recoveryState.publishedState)],
                persistenceIntent: request.allowPersistenceWrite
                    ? .unifiedSections(
                        LibraryHydrationPersistenceStore.makeUnifiedSectionsSnapshot(
                            sections: recoveryState.publishedState.sections,
                            homeMerchandising: recoveryState.publishedState.homeMerchandising,
                            discovery: recoveryState.publishedState.discovery,
                            savedAt: recoveryState.publishedState.savedAt,
                            isUnifiedHomeReady: recoveryState.publishedState.isUnifiedHomeReady,
                            refreshSource: String(describing: request.trigger),
                            trigger: String(describing: request.trigger),
                            publicationPlan: LibraryHydrationPublicationPlan(
                                stages: [.mruAndHero, .visibleRows, .backgroundArtwork]
                            )
                        )
                    )
                    : .none,
                cachedDiscovery: merchandisingResult.discovery,
                source: .postStreamDelta,
                publicationPlan: LibraryHydrationPublicationPlan(
                    stages: [.mruAndHero, .visibleRows, .backgroundArtwork]
                ),
                postStreamResult: .appliedDelta
            )
        }
    }
}
