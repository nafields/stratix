// LibraryHydrationPostStreamDeltaWorkflowTests.swift
// Exercises library hydration post stream delta workflow behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing

@MainActor
@Suite(.serialized)
struct LibraryHydrationPostStreamDeltaWorkflowTests {
    @Test
    func run_returnsAppliedDelta_whenLiveMRUMapsCleanly() async throws {
        let savedAt = Date(timeIntervalSince1970: 1_717_171_717)
        let workflow = LibraryHydrationPostStreamDeltaWorkflow()
        let result = try await workflow.run(
            request: makeRequest(allowPersistenceWrite: true),
            dependencies: makeDependencies(
                fetchLiveMRUEntries: { [LibraryMRUEntry(titleID: TitleID("title-1"), productID: ProductID("product-1"))] },
                applySectionsDelta: { _ in
                    .updated([TestHydrationFixtures.section(items: [TestHydrationFixtures.item(titleId: "title-1", productId: "product-1", isInMRU: true)])])
                },
                refreshMerchandising: { sections, _, _ in
                    HomeMerchandisingRefreshResult(
                        snapshot: HomeMerchandisingSnapshot(
                            recentlyAddedItems: sections.first?.items ?? [],
                            rows: [
                                HomeMerchandisingRow(
                                    alias: "recently-added",
                                    label: "recently-added",
                                    source: .fixedPriority,
                                    items: sections.first?.items ?? []
                                )
                            ],
                            generatedAt: savedAt
                        ),
                        discovery: HomeMerchandisingDiscoveryCachePayload(
                            entries: [TestHydrationFixtures.discoveryEntry(alias: "recently-added", siglID: "sigl-recent")],
                            savedAt: savedAt
                        )
                    )
                },
                now: { savedAt }
            )
        )

        #expect(result.postStreamResult == .appliedDelta)
        #expect(result.actions.contains(where: {
            if case .hydrationPublishedStateApplied(let state) = $0 {
                return state.sections.first?.items.first?.isInMRU == true
            }
            return false
        }))
        switch result.persistenceIntent {
        case .unifiedSections(let snapshot):
            #expect(snapshot.sections.first?.items.first?.isInMRU == true)
        default:
            Issue.record("Expected delta apply to emit unified sections persistence.")
        }
    }

    @Test
    func run_returnsRequiresFullRefresh_whenMRUEntriesDoNotMap() async throws {
        let savedAt = Date(timeIntervalSince1970: 1_919_191_919)
        let result = try await LibraryHydrationPostStreamDeltaWorkflow().run(
            request: makeRequest(allowPersistenceWrite: true),
            dependencies: makeDependencies(
                fetchLiveMRUEntries: { [LibraryMRUEntry(titleID: TitleID("title-1"), productID: ProductID("product-1"))] },
                applySectionsDelta: { _ in .requiresFullRefresh("mru_unmapped") },
                refreshMerchandising: { _, _, _ in
                    HomeMerchandisingRefreshResult(
                        snapshot: HomeMerchandisingSnapshot(
                            recentlyAddedItems: [],
                            rows: [],
                            generatedAt: savedAt
                        ),
                        discovery: HomeMerchandisingDiscoveryCachePayload(entries: [], savedAt: savedAt)
                    )
                },
                now: Date.init
            )
        )

        #expect(result.postStreamResult == PostStreamRefreshResult.requiresFullRefresh("mru_unmapped"))
    }

    @Test
    func run_returnsNoChange_whenSectionsRemainUnchanged() async throws {
        let savedAt = Date(timeIntervalSince1970: 2_929_292_929)
        let result = try await LibraryHydrationPostStreamDeltaWorkflow().run(
            request: makeRequest(allowPersistenceWrite: true),
            dependencies: makeDependencies(
                fetchLiveMRUEntries: { [] },
                applySectionsDelta: { _ in .noChange },
                refreshMerchandising: { _, _, _ in
                    HomeMerchandisingRefreshResult(
                        snapshot: HomeMerchandisingSnapshot(
                            recentlyAddedItems: [],
                            rows: [],
                            generatedAt: savedAt
                        ),
                        discovery: HomeMerchandisingDiscoveryCachePayload(entries: [], savedAt: savedAt)
                    )
                },
                now: Date.init
            )
        )

        #expect(result.postStreamResult == PostStreamRefreshResult.noChange)
        if case .none = result.persistenceIntent {
        } else {
            Issue.record("Expected no-change post-stream delta to skip persistence.")
        }
    }

    private func makeRequest(allowPersistenceWrite: Bool) -> LibraryHydrationRequest {
        LibraryHydrationRequest(
            trigger: .postStreamDelta,
            market: "US",
            language: "en-US",
            preferDeltaRefresh: true,
            forceFullRefresh: false,
            allowCacheRestore: false,
            allowPersistenceWrite: allowPersistenceWrite,
            deferInitialRoutePublication: false,
            refreshReason: nil,
            sourceDescription: "post_stream"
        )
    }

    private func makeDependencies(
        fetchLiveMRUEntries: @escaping () async throws -> [LibraryMRUEntry],
        applySectionsDelta: @escaping (_ liveMRUEntries: [LibraryMRUEntry]) -> MRUDeltaSectionsResult,
        refreshMerchandising: @escaping (_ sections: [CloudLibrarySection], _ market: String, _ language: String) async -> HomeMerchandisingRefreshResult,
        now: @escaping () -> Date
    ) -> LibraryHydrationPostStreamDeltaWorkflow.Dependencies {
        .init(
            fetchLiveMRUEntries: fetchLiveMRUEntries,
            applySectionsDelta: applySectionsDelta,
            refreshMerchandising: refreshMerchandising,
            now: now,
            logInfo: { _ in },
            logWarning: { _ in },
            logDebug: { _ in },
            describeSections: { _ in "" },
            describeHomeMerchandising: { _ in "" },
            describeDiscovery: { _ in "" },
            formattedAge: { _ in "0s" }
        )
    }
}
