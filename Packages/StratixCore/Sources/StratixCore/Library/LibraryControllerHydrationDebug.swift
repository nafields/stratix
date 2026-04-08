// LibraryControllerHydrationDebug.swift
// Defines library controller hydration debug for the Library surface.
//

import DiagnosticsKit
import Foundation
import StratixModels
import XCloudAPI

@MainActor
extension LibraryController {
    func formattedCacheAge() -> String {
        if let last = lastHydratedAt ?? cacheSavedAt {
            let age = max(0, Int(Date().timeIntervalSince(last)))
            return "\(age)s"
        }
        return "unknown"
    }

    func formattedAge(since date: Date) -> String {
        "\(max(0, Int(Date().timeIntervalSince(date))))s"
    }

    func logHydrationDebug(_ message: @autoclosure () -> String) {
        guard GLogger.isEnabled else { return }
        logger.info("Hydration debug: \(message())")
    }

    func logHydrationWarning(_ message: @autoclosure () -> String) {
        guard GLogger.isEnabled else { return }
        logger.warning("Hydration debug: \(message())")
    }

    func sampleItems(_ items: [CloudLibraryItem], limit: Int = 5) -> String {
        items.prefix(limit)
            .map { item in
                let sanitizedName = item.name.replacingOccurrences(of: "\"", with: "'")
                return "\(item.titleId)|\(item.productId)|\(sanitizedName)"
            }
            .joined(separator: ", ")
    }

    func sampleTitleEntries(_ titles: [TitleEntry], limit: Int = 5) -> String {
        titles.prefix(limit)
            .map { title in
                let name = (title.fallbackName ?? "?").replacingOccurrences(of: "\"", with: "'")
                return "\(title.titleId)|\(title.productId)|\(name)"
            }
            .joined(separator: ", ")
    }

    func sampleMRUEntries(
        _ entries: [LibraryMRUEntry],
        limit: Int = 5
    ) -> String {
        entries.prefix(limit)
            .map { "\($0.titleId)|\($0.productId)" }
            .joined(separator: ", ")
    }

    func sectionBreakdown(_ sections: [CloudLibrarySection], limit: Int = 6) -> String {
        sections.prefix(limit)
            .map { "\($0.id):\($0.items.count)" }
            .joined(separator: ", ")
    }

    func homeRowBreakdown(_ snapshot: HomeMerchandisingSnapshot?, limit: Int = 8) -> String {
        guard let snapshot else { return "none" }
        return snapshot.rows.prefix(limit)
            .map { "\($0.alias):\($0.items.count)" }
            .joined(separator: ", ")
    }

    func describeSections(_ sections: [CloudLibrarySection]) -> String {
        let libraryItems = Self.allLibraryItems(from: sections)
        let mruItems = sections.first(where: { $0.id == "mru" })?.items ?? []
        let totalItems = sections.reduce(0) { $0 + $1.items.count }
        return "sections=\(sections.count) totalItems=\(totalItems) libraryTitles=\(Self.libraryTitleCount(in: sections)) libraryItems=\(libraryItems.count) mruItems=\(mruItems.count) breakdown=[\(sectionBreakdown(sections))] librarySample=[\(sampleItems(libraryItems))] mruSample=[\(sampleItems(mruItems))]"
    }

    func describeHomeMerchandising(_ snapshot: HomeMerchandisingSnapshot?) -> String {
        guard let snapshot else { return "home=none" }
        return "homeRows=\(snapshot.rows.count) recentlyAdded=\(snapshot.recentlyAddedItems.count) rowBreakdown=[\(homeRowBreakdown(snapshot))] recentSample=[\(sampleItems(snapshot.recentlyAddedItems))]"
    }

    func describeDiscovery(_ discovery: CachedHomeMerchandisingDiscovery?) -> String {
        guard let discovery else { return "discovery=none" }
        let aliases = discovery.entries.prefix(8).map(\.alias).joined(separator: ", ")
        return "discoveryCount=\(discovery.entries.count) discoveryAge=\(formattedAge(since: discovery.savedAt)) aliases=[\(aliases)]"
    }

    func missingTitleEntries(
        expected titles: [TitleEntry],
        from sections: [CloudLibrarySection]
    ) -> [TitleEntry] {
        let shapedTitleIDs = Set(Self.allLibraryItems(from: sections).map(\.titleId))
        return titles.filter { !shapedTitleIDs.contains($0.titleId) }
    }

    var hasFreshCompleteStartupSnapshot: Bool {
        hydrationPlanner.hasFreshCompleteStartupSnapshot(
            sections: sections,
            homeMerchandising: homeMerchandising,
            hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
            lastHydratedAt: lastHydratedAt,
            cacheSavedAt: cacheSavedAt
        )
    }

    var requiresUnifiedHydration: Bool {
        hydrationPlanner.requiresUnifiedHydration(
            sections: sections,
            homeMerchandising: homeMerchandising,
            hasCompletedInitialHomeMerchandising: hasCompletedInitialHomeMerchandising,
            lastHydratedAt: lastHydratedAt,
            cacheSavedAt: cacheSavedAt
        )
    }

    func isUnifiedHydrationStale(generatedAt: Date) -> Bool {
        hydrationPlanner.isUnifiedHydrationStale(generatedAt: generatedAt)
    }

    func hydrationFormattedAge(_ date: Date) -> String {
        formattedAge(since: date)
    }

    func hydrationInfo(_ message: String) {
        logger.info("\(message)")
    }

    func hydrationWarning(_ message: String) {
        logger.warning("\(message)")
        logHydrationWarning(message)
    }

    func hydrationDebug(_ message: String) {
        logger.debug("\(message)")
        logHydrationDebug(message)
    }

    func sampleHydrationTitleEntries(_ titles: [TitleEntry], limit: Int = 5) -> String {
        sampleTitleEntries(titles, limit: limit)
    }

    func sampleHydrationMRUEntries(
        _ entries: [LibraryMRUEntry],
        limit: Int = 5
    ) -> String {
        sampleMRUEntries(entries, limit: limit)
    }

    func hydrationSectionBreakdown(_ sections: [CloudLibrarySection], limit: Int = 6) -> String {
        sectionBreakdown(sections, limit: limit)
    }

    func describeHydrationSections(_ sections: [CloudLibrarySection]) -> String {
        describeSections(sections)
    }

    func describeHydrationHomeMerchandising(_ snapshot: HomeMerchandisingSnapshot?) -> String {
        describeHomeMerchandising(snapshot)
    }

    func describeHydrationDiscovery(_ discovery: CachedHomeMerchandisingDiscovery?) -> String {
        describeDiscovery(discovery)
    }

    func missingHydrationTitleEntries(
        expected titles: [TitleEntry],
        from sections: [CloudLibrarySection]
    ) -> [TitleEntry] {
        missingTitleEntries(expected: titles, from: sections)
    }

    func authenticatedLibraryTokens() throws -> StreamTokens {
        guard let tokens = dependencies?.authenticatedLibraryTokens() else {
            throw AuthError.invalidResponse("not_authenticated")
        }
        return tokens
    }

    func fetchLiveMRUEntriesForHydration() async throws -> [LibraryMRUEntry] {
        try await fetchLiveMRUEntries(tokens: authenticatedLibraryTokens())
    }
}
