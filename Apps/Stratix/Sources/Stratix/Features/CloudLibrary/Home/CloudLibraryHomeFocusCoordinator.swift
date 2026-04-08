// CloudLibraryHomeFocusCoordinator.swift
// Defines the cloud library home focus coordinator for the CloudLibrary / Home surface.
//

import SwiftUI
import DiagnosticsKit
import StratixModels

enum CloudLibraryHomeFocusCoordinator {
    static func preferredTitleID(
        for titleID: TitleID,
        tileLookup: [TitleID: CloudLibraryHomeScreen.TileLookupEntry]
    ) -> TitleID? {
        tileLookup[titleID].map(\.titleID)
    }

    static func lookupEntry(
        for titleID: TitleID,
        tileLookup: [TitleID: CloudLibraryHomeScreen.TileLookupEntry]
    ) -> CloudLibraryHomeScreen.TileLookupEntry? {
        tileLookup[titleID]
    }
}

extension CloudLibraryHomeScreen {
    static let logger = GLogger(category: .ui)

    struct TileLookupEntry: Hashable, Sendable {
        let sectionID: String
        let tile: MediaTileViewState
        let titleID: TitleID
    }

    enum HomeFocusTarget: Hashable {
        case carouselPlay
        case carouselDetails
        case titleTile(TitleID, sectionID: String)
        case showAllCard(String)
    }

    var currentCarouselItem: CloudLibraryHomeCarouselItemViewState? {
        guard !state.carouselItems.isEmpty else { return nil }
        let clamped = max(0, min(carouselIndex, state.carouselItems.count - 1))
        return state.carouselItems[clamped]
    }

    var focusedTileExtraHeight: CGFloat {
        (StratixTheme.Home.railTileHeight * (tileFocusScale - 1)) / 2 + tileFocusBreathing
    }

    func handleFocusedTargetChange(_ new: HomeFocusTarget?) {
        guard let target = new else {
            onFocusTileID(nil)
            onSettledTileID(nil)
            focusSettler.cancel()
            NavigationPerformanceTracker.recordFocusLoss(surface: "home")
            return
        }

        switch target {
        case .carouselPlay:
            let titleID = currentCarouselItem?.titleID
            onFocusTileID(titleID)
            NavigationPerformanceTracker.recordFocusTarget(surface: "home", target: "carousel_play")
            scheduleFocusSettled(targetLabel: "carousel_play", titleID: titleID)
        case .carouselDetails:
            let titleID = currentCarouselItem?.titleID
            onFocusTileID(titleID)
            NavigationPerformanceTracker.recordFocusTarget(surface: "home", target: "carousel_details")
            scheduleFocusSettled(targetLabel: "carousel_details", titleID: titleID)
        case .titleTile(let titleID, _):
            let lookupEntry = lookupEntry(for: titleID)
            if let lookupEntry {
                onFocusTileID(lookupEntry.titleID)
                scheduleFocusSettled(targetLabel: titleID.rawValue, titleID: lookupEntry.titleID)
            } else {
                onFocusTileID(nil)
                scheduleFocusSettled(targetLabel: titleID.rawValue, titleID: nil)
            }
            NavigationPerformanceTracker.recordFocusTarget(surface: "home", target: titleID.rawValue)
        case .showAllCard(let cardID):
            onFocusTileID(nil)
            scheduleFocusSettled(targetLabel: cardID, titleID: nil)
            NavigationPerformanceTracker.recordFocusTarget(surface: "home", target: cardID)
        }
    }

    func requestFocusFromSideRail() {
        if let preferredTitleID,
           let rememberedTitleID = self.preferredTitleID(for: preferredTitleID),
           requestPreferredTileFocus(titleID: rememberedTitleID) {
            return
        }
        if requestHeroActionFocus() { return }
        _ = requestFirstRailFocus()
    }

    @discardableResult
    func requestPreferredTileFocus(titleID: TitleID) -> Bool {
        guard let lookupEntry = lookupEntry(for: titleID) else { return false }
        scheduleFocusRequest(.titleTile(titleID, sectionID: lookupEntry.sectionID))
        return true
    }

    @discardableResult
    func requestHeroActionFocus() -> Bool {
        guard !state.carouselItems.isEmpty else { return false }
        scheduleFocusRequest(.carouselPlay)
        return true
    }

    @discardableResult
    func requestFirstRailFocus() -> Bool {
        guard let firstSection = state.sections.first, !firstSection.items.isEmpty else { return false }
        guard let firstItem = firstSection.items.first else { return false }
        switch firstItem {
        case .title(let titleItem):
            scheduleFocusRequest(.titleTile(titleItem.tile.titleID, sectionID: firstSection.id))
        case .showAll(let card):
            scheduleFocusRequest(.showAllCard(card.id))
        }
        return true
    }

    func scheduleFocusRequest(_ target: HomeFocusTarget) {
        pendingFocusTask?.cancel()
        pendingFocusTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedTarget = target
        }
    }

    func scheduleFocusSettled(targetLabel: String, titleID: TitleID?) {
        focusSettler.schedule {
            NavigationPerformanceTracker.recordFocusSettled(surface: "home", target: targetLabel)
            onSettledTileID(titleID)
        }
    }

    func preferredTitleID(for titleID: TitleID) -> TitleID? {
        CloudLibraryHomeFocusCoordinator.preferredTitleID(for: titleID, tileLookup: tileLookup)
    }

    func lookupEntry(for titleID: TitleID) -> TileLookupEntry? {
        CloudLibraryHomeFocusCoordinator.lookupEntry(for: titleID, tileLookup: tileLookup)
    }

    func moveCarousel(by delta: Int) {
        guard state.carouselItems.count > 1 else { return }
        let count = state.carouselItems.count
        let next = ((carouselIndex + delta) % count + count) % count
        guard next != carouselIndex else { return }
        logHomeScreenDebug(
            "carousel_move from=\(carouselIndex) to=\(next) count=\(state.carouselItems.count) current=\(currentCarouselItem?.titleID.rawValue ?? "none")"
        )
        carouselIndex = next
    }

    func syncCarouselIndexIfNeeded() {
        if state.carouselItems.isEmpty {
            if carouselIndex != 0 {
                logHomeScreenDebug("carousel_sync_reset from=\(carouselIndex) to=0 reason=empty")
            }
            carouselIndex = 0
            return
        }

        let clamped = max(0, min(carouselIndex, state.carouselItems.count - 1))
        if clamped != carouselIndex {
            logHomeScreenDebug(
                "carousel_sync_clamp from=\(carouselIndex) to=\(clamped) count=\(state.carouselItems.count) sample=[\(carouselSample(state.carouselItems))]"
            )
        } else {
            logHomeScreenDebug(
                "carousel_sync_stable index=\(carouselIndex) count=\(state.carouselItems.count) current=\(state.carouselItems[clamped].titleID.rawValue)"
            )
        }
        carouselIndex = clamped
    }

    func handlePlayButtonMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            if carouselIndex > 0 {
                moveCarousel(by: -1)
            } else {
                onRequestSideRailEntry()
            }
        case .right:
            focusedTarget = .carouselDetails
        case .down:
            _ = requestFirstRailFocus()
        default:
            break
        }
    }

    func handleDetailsButtonMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            focusedTarget = .carouselPlay
        case .right:
            moveCarousel(by: 1)
        case .down:
            _ = requestFirstRailFocus()
        default:
            break
        }
    }

    func handleRailMove(sectionIndex: Int, itemIndex: Int, direction: MoveCommandDirection) {
        recordMediaTileMoveDirection(direction)

        guard !(direction == .left && itemIndex == 0) else {
            onRequestSideRailEntry()
            return
        }

        guard direction == .up, sectionIndex == 0 else { return }
        focusedTarget = .carouselPlay
    }

    func logHomeScreenDebug(_ message: @autoclosure () -> String) {
        guard GLogger.isEnabled else { return }
        Self.logger.info("Home screen: \(message())")
    }

    func stateSummary() -> String {
        "carousel=\(state.carouselItems.count) rails=\(state.sections.count) carouselSample=[\(carouselSample(state.carouselItems))] railSummary=[\(railSummary(state.sections))]"
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
}
