// CloudLibrarySearchScreen.swift
// Defines the cloud library search screen for the CloudLibrary / Search surface.
//

import SwiftUI
import StratixModels

struct CloudLibrarySearchScreen: View, Equatable {

    let queryTextValue: String
    let totalLibraryCount: Int
    let browseItems: [MediaTileViewState]
    let resultItems: [MediaTileViewState]
    let tileLookup: [TitleID: MediaTileViewState]
    var preferredTitleID: TitleID? = nil
    var onClearQuery: () -> Void = {}
    let onSelectTile: (MediaTileViewState) -> Void
    var onFocusTileID: (TitleID?) -> Void = { _ in }
    var onRequestSideRailEntry: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum SearchFocusTarget: Hashable {
        case tile(TitleID)
    }

    @FocusState private var focusedTarget: SearchFocusTarget?
    @State private var cachedGridColumnCount: Int = Self.defaultGridColumnCount
    @State private var cachedColumns: [GridItem] = Self.defaultColumns
    @State private var focusSettler = FocusSettleDebouncer()

    private let gridItemWidth = StratixTheme.Search.gridItemWidth
    private let gridItemSpacing = StratixTheme.Search.gridItemSpacing
    private let gridHorizontalPadding = StratixTheme.Search.gridHorizontalPadding
    private static let defaultGridColumnCount: Int = {
        let availableWidth = max(1920 - (StratixTheme.Search.gridHorizontalPadding * 2), StratixTheme.Search.gridItemWidth)
        return max(Int((availableWidth + StratixTheme.Search.gridItemSpacing) / (StratixTheme.Search.gridItemWidth + StratixTheme.Search.gridItemSpacing)), 1)
    }()
    private static let defaultColumns: [GridItem] = Array(
        repeating: GridItem(.fixed(StratixTheme.Search.gridItemWidth), spacing: StratixTheme.Search.gridItemSpacing, alignment: .top),
        count: defaultGridColumnCount
    )

    private var trimmedQueryText: String {
        queryTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StratixTheme.Search.sectionSpacing) {
                    if !trimmedQueryText.isEmpty {
                        if resultItems.isEmpty {
                            CloudLibraryStatusPanel(
                                state: .init(
                                    kind: .empty,
                                    title: "No matches",
                                    message: "No titles matched \"\(queryTextValue)\". Try shorter keywords.",
                                    primaryActionTitle: "Clear Search"
                                ),
                                onPrimaryAction: onClearQuery
                            )
                            .frame(height: 420)
                        } else {
                            Text("\(resultItems.count) results")
                                .font(StratixTypography.rounded(15, weight: .semibold, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(StratixTheme.Colors.textMuted)
                                .padding(.horizontal, gridHorizontalPadding)

                            tileGrid(items: resultItems)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("route_search_root")
            .scrollIndicators(.hidden)
            .gamePassDisableSystemFocusEffect()
            .onChange(of: focusedTarget) { _, target in
                guard let target else {
                    onFocusTileID(nil)
                    focusSettler.cancel()
                    NavigationPerformanceTracker.recordFocusLoss(surface: "search")
                    return
                }
                switch target {
                case .tile(let titleID):
                    NavigationPerformanceTracker.recordFocusTarget(surface: "search", target: titleID.rawValue)
                    onFocusTileID(titleID)
                    scheduleFocusSettled(targetID: titleID.rawValue)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateGridLayout(for: proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, width in
                            updateGridLayout(for: width)
                        }
                }
            )
        }
        .onDisappear {
            focusSettler.cancel()
        }
    }

    // MARK: - Tile Grid

    @ViewBuilder
    private func tileGrid(items: [MediaTileViewState]) -> some View {
        LazyVGrid(columns: cachedColumns, alignment: .leading, spacing: gridItemSpacing) {
            ForEach(items) { item in
                MediaTileView(
                    state: item,
                    onSelect: { onSelectTile(item) }
                )
                .focused($focusedTarget, equals: .tile(item.titleID))
                .onMoveCommand { direction in
                    NavigationPerformanceTracker.recordRemoteMoveStart(surface: "search", direction: direction)
                    let gridIndex = items.firstIndex(where: { $0.id == item.id }) ?? 0
                    guard direction == .left, isLeadingGridColumn(index: gridIndex) else { return }
                    onRequestSideRailEntry()
                }
                .id(item.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .padding(.horizontal, gridHorizontalPadding)
    }

    // MARK: - Focus management

    private func scheduleFocusSettled(targetID: String) {
        focusSettler.schedule {
            NavigationPerformanceTracker.recordFocusSettled(surface: "search", target: targetID)
        }
    }

    // MARK: - Grid helpers

    private func isLeadingGridColumn(index: Int) -> Bool {
        index % cachedGridColumnCount == 0
    }

    private func updateGridLayout(for width: CGFloat) {
        let availableWidth = max(width - (gridHorizontalPadding * 2), gridItemWidth)
        let newColumnCount = max(Int((availableWidth + gridItemSpacing) / (gridItemWidth + gridItemSpacing)), 1)
        guard newColumnCount != cachedGridColumnCount else { return }
        cachedGridColumnCount = newColumnCount
        cachedColumns = Array(
            repeating: GridItem(.fixed(gridItemWidth), spacing: gridItemSpacing, alignment: .top),
            count: newColumnCount
        )
    }

    nonisolated static func == (lhs: CloudLibrarySearchScreen, rhs: CloudLibrarySearchScreen) -> Bool {
        lhs.queryTextValue == rhs.queryTextValue &&
        lhs.totalLibraryCount == rhs.totalLibraryCount &&
        lhs.browseItems == rhs.browseItems &&
        lhs.resultItems == rhs.resultItems &&
        lhs.tileLookup == rhs.tileLookup &&
        lhs.preferredTitleID == rhs.preferredTitleID
    }

}

private enum CloudLibrarySearchPreviewFixtures {
    static let previewItems: [MediaTileViewState] = Array(
        Dictionary(
            CloudLibraryPreviewData.home.sections
                .flatMap(\.items)
                .compactMap { item -> (String, MediaTileViewState)? in
                    if case .title(let titleItem) = item {
                        return (titleItem.tile.id, titleItem.tile)
                    }
                    return nil
                },
            uniquingKeysWith: { current, _ in current }
        )
        .values
    )

    static let tileLookup: [TitleID: MediaTileViewState] = Dictionary(
        uniqueKeysWithValues: previewItems.map { ($0.titleID, $0) }
    )
}

#if DEBUG
#Preview("CloudLibrarySearch Results", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryShellView(
        sideRail: CloudLibraryPreviewData.sideRail,
        selectedNavID: .search,
        heroBackgroundURL: CloudLibraryPreviewData.home.heroBackgroundURL,
        onSelectNav: { _ in }
    ) {
        CloudLibrarySearchPreviewHost()
    }
}

#Preview("CloudLibrarySearch Empty Results", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryShellView(
        sideRail: CloudLibraryPreviewData.sideRail,
        selectedNavID: .search,
        heroBackgroundURL: CloudLibraryPreviewData.home.heroBackgroundURL,
        onSelectNav: { _ in }
    ) {
        CloudLibrarySearchEmptyResultsPreviewHost()
    }
}

private struct CloudLibrarySearchPreviewHost: View {
    @State private var queryText = "a"

    var body: some View {
        CloudLibrarySearchScreen(
            queryTextValue: queryText,
            totalLibraryCount: CloudLibraryPreviewData.cloudItems.count,
            browseItems: CloudLibrarySearchPreviewFixtures.previewItems,
            resultItems: CloudLibrarySearchPreviewFixtures.previewItems,
            tileLookup: CloudLibrarySearchPreviewFixtures.tileLookup,
            onSelectTile: { _ in }
        )
        .searchable(text: $queryText, prompt: "Search cloud titles")
    }
}

private struct CloudLibrarySearchEmptyResultsPreviewHost: View {
    @State private var queryText = "zzzzz"

    var body: some View {
        CloudLibrarySearchScreen(
            queryTextValue: queryText,
            totalLibraryCount: CloudLibraryPreviewData.cloudItems.count,
            browseItems: CloudLibrarySearchPreviewFixtures.previewItems,
            resultItems: [],
            tileLookup: CloudLibrarySearchPreviewFixtures.tileLookup,
            onSelectTile: { _ in }
        )
        .searchable(text: $queryText, prompt: "Search cloud titles")
    }
}
#endif
