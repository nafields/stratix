// CloudLibraryLibraryScreenHeader.swift
// Defines cloud library library screen header for the CloudLibrary / Library surface.
//

import SwiftUI

extension CloudLibraryLibraryScreen {
    @ViewBuilder
    func header(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            if !state.tabs.isEmpty {
                HStack(spacing: 28) {
                    ForEach(state.tabs) { tab in
                        LibraryTabButton(
                            title: tab.title,
                            isSelected: tab.id == state.selectedTabID
                        ) {
                            onSelectTab(tab.id)
                        }
                        .focused($focusedTarget, equals: .tab(tab.id))
                        .onMoveCommand { direction in
                            NavigationPerformanceTracker.recordRemoteMoveStart(surface: "library", direction: direction)
                            if direction == .left {
                                onRequestSideRailEntry()
                            } else if direction == .down {
                                requestGridFocus(scrollProxy: scrollProxy)
                            }
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 14) {
                if let callout = state.categoryCalloutTitle {
                    Text(callout)
                        .font(StratixTypography.rounded(24, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(StratixTheme.Colors.focusTint)
                        .lineLimit(1)
                }

                if let summary = state.resultSummaryText {
                    Text(summary)
                        .font(StratixTypography.rounded(22, weight: .semibold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(StratixTheme.Colors.textMuted)
                        .lineLimit(1)
                }

                SortButton(title: state.sortLabel, onSelect: onSelectSort)
                    .focused($focusedTarget, equals: .headerButton("sort"))
                    .onMoveCommand { direction in
                        NavigationPerformanceTracker.recordRemoteMoveStart(surface: "library", direction: direction)
                        if direction == .left {
                            onRequestSideRailEntry()
                        } else if direction == .down {
                            requestGridFocus(scrollProxy: scrollProxy)
                        }
                    }

                if !state.activeFilterLabels.isEmpty {
                    SortButton(title: "Show all", icon: "line.3.horizontal.decrease.circle.fill", onSelect: onClearFilters)
                        .focused($focusedTarget, equals: .headerButton("clear-filters"))
                        .onMoveCommand { direction in
                            NavigationPerformanceTracker.recordRemoteMoveStart(surface: "library", direction: direction)
                            if direction == .left {
                                onRequestSideRailEntry()
                            } else if direction == .down {
                                requestGridFocus(scrollProxy: scrollProxy)
                            }
                        }
                }

                Spacer()
            }

            if !state.filters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(state.filters) { filter in
                            LibraryFilterChipButton(chip: filter) {
                                onSelectFilter(filter)
                            }
                            .focused($focusedTarget, equals: .filter(filter.id))
                            .onMoveCommand { direction in
                                NavigationPerformanceTracker.recordRemoteMoveStart(surface: "library", direction: direction)
                                if direction == .left {
                                    onRequestSideRailEntry()
                                } else if direction == .down {
                                    requestGridFocus(scrollProxy: scrollProxy)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
        }
        .focusSection()
        .id(Self.headerAnchorID)
    }
}
