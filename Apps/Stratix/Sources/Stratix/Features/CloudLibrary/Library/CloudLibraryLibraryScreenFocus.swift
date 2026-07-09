// CloudLibraryLibraryScreenFocus.swift
// Defines cloud library library screen focus for the CloudLibrary / Library surface.
//

import SwiftUI
import StratixModels

extension CloudLibraryLibraryScreen {
    var defaultGridFocusTileID: String? {
        if let preferredTitleID,
           let preferredTileID = scrollTargetID(for: preferredTitleID),
           state.gridItems.contains(where: { $0.id == preferredTileID }) {
            return preferredTileID
        }

        return state.gridItems.first?.id
    }

    /// Applies a pending shell focus hand-off exactly once per generation, restoring the
    /// remembered (or preferred) grid tile when the shell asks Library to claim focus.
    func consumeFocusHandoffIfNeeded(scrollProxy: ScrollViewProxy) {
        guard let request = focusHandoffRequest,
              request.route == .library,
              request.generation != consumedFocusHandoffGeneration else { return }
        consumedFocusHandoffGeneration = request.generation
        requestGridFocus(scrollProxy: scrollProxy)
    }

    func requestGridFocus(scrollProxy: ScrollViewProxy, prefersFirstVisibleItem: Bool = false) {
        guard !state.gridItems.isEmpty else { return }
        let targetTitleID: TitleID?
        if !prefersFirstVisibleItem,
           let remembered = lastFocusedGridTitleID,
           tileLookup[remembered] != nil {
            targetTitleID = remembered
        } else if let preferredTitleID,
                  let preferredTileID = scrollTargetID(for: preferredTitleID),
                  state.gridItems.contains(where: { $0.id == preferredTileID }) {
            targetTitleID = preferredTitleID
        } else {
            targetTitleID = state.gridItems.first?.titleID
        }
        guard let targetTitleID,
              let targetID = scrollTargetID(for: targetTitleID) else { return }
        pendingFocusTask?.cancel()
        pendingFocusTask = Task { @MainActor in
            withAnimation(nil) { scrollProxy.scrollTo(targetID, anchor: .topLeading) }
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedTarget = .tile(targetTitleID)
        }
    }

    func scheduleFocusSettled(targetLabel: String, settledTitleID: TitleID?) {
        focusSettler.schedule {
            NavigationPerformanceTracker.recordFocusSettled(surface: "library", target: targetLabel)
            self.onSettledTileID(settledTitleID)
        }
    }

    func isLeadingGridColumn(index: Int) -> Bool {
        index % cachedGridColumnCount == 0
    }

    func updateGridLayout(for width: CGFloat) {
        let availableWidth = max(width - (gridEdgeFocusInset * 2), gridItemWidth)
        let newColumnCount = max(Int((availableWidth + gridItemSpacing) / (gridItemWidth + gridItemSpacing)), 1)
        guard newColumnCount != cachedGridColumnCount else { return }
        cachedGridColumnCount = newColumnCount
        cachedColumns = Array(
            repeating: GridItem(.fixed(gridItemWidth), spacing: gridItemSpacing, alignment: .top),
            count: newColumnCount
        )
    }

    func scrollTargetID(for titleID: TitleID) -> String? {
        tileLookup[titleID]?.id
    }
}
