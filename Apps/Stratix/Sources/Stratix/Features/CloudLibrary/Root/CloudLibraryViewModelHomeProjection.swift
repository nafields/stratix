// CloudLibraryViewModelHomeProjection.swift
// Defines cloud library view model home projection for the CloudLibrary / Root surface.
//

import DiagnosticsKit
import StratixCore
import StratixModels

@MainActor
extension CloudLibraryViewModel {
    func rebuildHomeProjection(
        using sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot?,
        productDetails: [ProductID: CloudLibraryProductDetail],
        showsContinueBadge: Bool,
        force: Bool = false
    ) {
        var hasher = Hasher()
        hasher.combine(sections.count)
        hasher.combine(sections.reduce(0) { $0 + $1.items.count })
        hasher.combine(merchandising?.rows.count ?? 0)
        hasher.combine(merchandising?.recentlyAddedItems.count ?? 0)
        hasher.combine(productDetails.count)
        hasher.combine(showsContinueBadge)
        let projectionToken = hasher.finalize()
        guard force || projectionToken != lastHomeProjectionToken else {
            logHomeProjection(
                "skip token=\(projectionToken) force=\(force) \(describeHomeInputs(sections: sections, merchandising: merchandising)) currentState=\(describeHomeState(cachedHomeState))"
            )
            return
        }
        lastHomeProjectionToken = projectionToken

        let newHomeState = CloudLibraryDataSource.homeState(
            sections: sections,
            merchandising: merchandising,
            productDetails: productDetails,
            showsContinueBadge: showsContinueBadge
        )
        logHomeProjection(
            "rebuild token=\(projectionToken) force=\(force) \(describeHomeInputs(sections: sections, merchandising: merchandising)) output=\(describeHomeState(newHomeState))"
        )
        if newHomeState != cachedHomeState {
            logHomeProjection(
                "apply token=\(projectionToken) old=\(describeHomeState(cachedHomeState)) new=\(describeHomeState(newHomeState))"
            )
            cachedHomeState = newHomeState
        } else {
            logHomeProjection(
                "noop token=\(projectionToken) stateUnchanged=\(describeHomeState(newHomeState))"
            )
        }

        let newHomeTileLookup = Dictionary(
            newHomeState.sections.flatMap { section in
                section.items.compactMap { item -> (TitleID, CloudLibraryHomeScreen.TileLookupEntry)? in
                    guard case .title(let titleItem) = item else { return nil }
                    return (
                        titleItem.tile.titleID,
                        CloudLibraryHomeScreen.TileLookupEntry(
                            sectionID: section.id,
                            tile: titleItem.tile,
                            titleID: titleItem.tile.titleID
                        )
                    )
                }
            },
            uniquingKeysWith: { current, _ in current }
        )
        if newHomeTileLookup != cachedHomeTileLookup {
            cachedHomeTileLookup = newHomeTileLookup
        }
    }

    func rebuildHomeProjection(
        using index: CloudLibraryDataSource.PreparedLibraryIndex,
        productDetails: [ProductID: CloudLibraryProductDetail],
        detailRevision: UInt64,
        homeRevision: UInt64,
        sceneContentRevision: UInt64,
        showsContinueBadge: Bool
    ) {
        var hasher = Hasher()
        hasher.combine(sceneContentRevision)
        hasher.combine(detailRevision)
        hasher.combine(homeRevision)
        hasher.combine(showsContinueBadge)
        let projectionToken = hasher.finalize()
        guard projectionToken != lastHomeProjectionToken else { return }
        lastHomeProjectionToken = projectionToken

        let newHomeState = CloudLibraryDataSource.homeState(
            index: index,
            productDetails: productDetails,
            showsContinueBadge: showsContinueBadge
        )
        if newHomeState != cachedHomeState {
            cachedHomeState = newHomeState
        }

        let newHomeTileLookup = Dictionary(
            newHomeState.sections.flatMap { section in
                section.items.compactMap { item -> (TitleID, CloudLibraryHomeScreen.TileLookupEntry)? in
                    guard case .title(let titleItem) = item else { return nil }
                    return (
                        titleItem.tile.titleID,
                        CloudLibraryHomeScreen.TileLookupEntry(
                            sectionID: section.id,
                            tile: titleItem.tile,
                            titleID: titleItem.tile.titleID
                        )
                    )
                }
            },
            uniquingKeysWith: { current, _ in current }
        )
        if newHomeTileLookup != cachedHomeTileLookup {
            cachedHomeTileLookup = newHomeTileLookup
        }
    }

    func logHomeProjection(_ message: @autoclosure () -> String) {
        guard GLogger.isEnabled else { return }
        logger.info("Home projection viewmodel: \(message())")
    }

    func itemSample(_ items: [CloudLibraryItem], limit: Int = 5) -> String {
        items.prefix(limit)
            .map { "\($0.titleId)|\($0.productId)|\($0.name.replacingOccurrences(of: "\"", with: "'"))" }
            .joined(separator: ", ")
    }

    func carouselSample(_ items: [CloudLibraryHomeCarouselItemViewState], limit: Int = 5) -> String {
        items.prefix(limit)
            .map { "\($0.titleID.rawValue)|\($0.title.replacingOccurrences(of: "\"", with: "'"))" }
            .joined(separator: ", ")
    }

    func railSummary(_ sections: [CloudLibraryRailSectionViewState], limit: Int = 8) -> String {
        sections.prefix(limit)
            .map { "\($0.alias ?? $0.id):\($0.items.count)" }
            .joined(separator: ", ")
    }

    func sectionSummary(_ sections: [CloudLibrarySection], limit: Int = 6) -> String {
        sections.prefix(limit)
            .map { "\($0.id):\($0.items.count)" }
            .joined(separator: ", ")
    }

    func describeHomeInputs(
        sections: [CloudLibrarySection],
        merchandising: HomeMerchandisingSnapshot?
    ) -> String {
        let libraryItems = CloudLibraryDataSource.allLibraryItems(from: sections)
        let mruItems = CloudLibraryDataSource.mruItems(from: sections)
        return "libraryTitles=\(libraryItems.count) mru=\(mruItems.count) merchRows=\(merchandising?.rows.count ?? 0) recent=\(merchandising?.recentlyAddedItems.count ?? 0) sections=[\(sectionSummary(sections))] recentSample=[\(itemSample(merchandising?.recentlyAddedItems ?? []))] mruSample=[\(itemSample(mruItems))]"
    }

    func describeHomeState(_ state: CloudLibraryHomeViewState) -> String {
        "carousel=\(state.carouselItems.count) rails=\(state.sections.count) carouselSample=[\(carouselSample(state.carouselItems))] railSummary=[\(railSummary(state.sections))]"
    }
}
