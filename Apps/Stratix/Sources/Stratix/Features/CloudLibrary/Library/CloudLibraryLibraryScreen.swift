// CloudLibraryLibraryScreen.swift
// Defines the cloud library library screen for the CloudLibrary / Library surface.
//

import SwiftUI
import StratixModels

struct CloudLibraryLibraryScreen: View, Equatable {

    let state: CloudLibraryLibraryViewState
    let tileLookup: [TitleID: MediaTileViewState]
    var preferredTitleID: TitleID? = nil
    let onSelectTile: (MediaTileViewState) -> Void
    var onFocusTileID: (TitleID?) -> Void = { _ in }
    var onSettledTileID: (TitleID?) -> Void = { _ in }
    var onSelectTab: (String) -> Void = { _ in }
    var onSelectFilter: (ChipViewState) -> Void = { _ in }
    var onSelectSort: () -> Void = {}
    var onClearFilters: () -> Void = {}
    var onRequestSideRailEntry: () -> Void = {}

    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Namespace var gridFocusNamespace
    enum LibraryFocusTarget: Hashable {
        case tab(String)
        case headerButton(String)
        case filter(String)
        case tile(TitleID)
    }

    @FocusState var focusedTarget: LibraryFocusTarget?
    @State var lastFocusedGridTitleID: TitleID?
    @State var lastFocusedHeaderTarget: LibraryFocusTarget?
    @State var cachedGridColumnCount: Int = Self.defaultGridColumnCount
    @State var cachedColumns: [GridItem] = Self.defaultColumns
    @State var focusSettler = FocusSettleDebouncer()
    @State var pendingFocusTask: Task<Void, Never>?

    let gridItemWidth = StratixTheme.Library.gridItemWidth
    let gridItemSpacing = StratixTheme.Library.gridItemSpacing
    let gridEdgeFocusInset = StratixTheme.Library.gridEdgeFocusInset
    static let headerAnchorID = "library_header"
    static let defaultGridColumnCount: Int = {
        let availableWidth = max(1920 - (StratixTheme.Library.gridEdgeFocusInset * 2), StratixTheme.Library.gridItemWidth)
        return max(Int((availableWidth + StratixTheme.Library.gridItemSpacing) / (StratixTheme.Library.gridItemWidth + StratixTheme.Library.gridItemSpacing)), 1)
    }()
    static let defaultColumns: [GridItem] = Array(
        repeating: GridItem(.fixed(StratixTheme.Library.gridItemWidth), spacing: StratixTheme.Library.gridItemSpacing, alignment: .top),
        count: defaultGridColumnCount
    )

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StratixTheme.Library.sectionSpacing) {
                    header(scrollProxy: scrollProxy)

                    if state.gridItems.isEmpty {
                        CloudLibraryStatusPanel(
                            state: .init(
                                kind: .empty,
                                title: "Library is empty",
                                message: "Once cloud titles are available they will appear here.",
                                primaryActionTitle: nil
                            )
                        )
                        .frame(height: 480)
                    } else {
                        LazyVGrid(columns: cachedColumns, alignment: .leading, spacing: StratixTheme.Library.gridItemSpacing) {
                            ForEach(Array(state.gridItems.enumerated()), id: \.element.id) { index, item in
                                MediaTileView(
                                    state: item,
                                    onSelect: {
                                        onSelectTile(item)
                                    },
                                    forcedFocus: focusedTarget == .tile(item.titleID)
                                )
                                .focused($focusedTarget, equals: .tile(item.titleID))
                                .prefersDefaultFocus(item.id == defaultGridFocusTileID, in: gridFocusNamespace)
                                .onMoveCommand { direction in
                                    NavigationPerformanceTracker.recordRemoteMoveStart(surface: "library", direction: direction)
                                    recordMediaTileMoveDirection(direction)
                                    if direction == .left, isLeadingGridColumn(index: index) {
                                        onRequestSideRailEntry()
                                    } else if direction == .up, isTopGridRow(index: index) {
                                        requestHeaderFocusFromSideRail(scrollProxy: scrollProxy)
                                    }
                                }
                                .id(item.id)
                            }
                        }
                        .accessibilityIdentifier("library_grid_container")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusScope(gridFocusNamespace)
                        .focusSection()
                        .padding(.horizontal, gridEdgeFocusInset)
                        .padding(.bottom, 0)
                    }
                }
                .padding(.top, 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("route_library_root")
            .scrollIndicators(.hidden)
            .gamePassDisableSystemFocusEffect()
            .onChange(of: focusedTarget) { _, target in
                guard let target else {
                    onFocusTileID(nil)
                    onSettledTileID(nil)
                    focusSettler.cancel()
                    NavigationPerformanceTracker.recordFocusLoss(surface: "library")
                    return
                }

                switch target {
                case .tile(let titleID):
                    lastFocusedGridTitleID = titleID
                    NavigationPerformanceTracker.recordFocusTarget(surface: "library", target: titleID.rawValue)
                    onFocusTileID(titleID)
                    scheduleFocusSettled(targetLabel: titleID.rawValue, settledTitleID: titleID)
                case .tab(let id):
                    lastFocusedHeaderTarget = target
                    onFocusTileID(nil)
                    NavigationPerformanceTracker.recordFocusTarget(surface: "library", target: "tab:\(id)")
                    scheduleFocusSettled(targetLabel: "tab:\(id)", settledTitleID: nil)
                case .headerButton(let id):
                    lastFocusedHeaderTarget = target
                    onFocusTileID(nil)
                    NavigationPerformanceTracker.recordFocusTarget(surface: "library", target: "header:\(id)")
                    scheduleFocusSettled(targetLabel: "header:\(id)", settledTitleID: nil)
                case .filter(let id):
                    lastFocusedHeaderTarget = target
                    onFocusTileID(nil)
                    NavigationPerformanceTracker.recordFocusTarget(surface: "library", target: "filter:\(id)")
                    scheduleFocusSettled(targetLabel: "filter:\(id)", settledTitleID: nil)
                }
            }
            .onChange(of: state.sortLabel) { _, _ in
                // Grid reorders on sort — remembered position is no longer valid.
                lastFocusedGridTitleID = nil
            }
            .onChange(of: state.selectedTabID) { _, _ in
                // Tab switch changes which items are visible — reset grid focus.
                lastFocusedGridTitleID = nil
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

    nonisolated static func == (lhs: CloudLibraryLibraryScreen, rhs: CloudLibraryLibraryScreen) -> Bool {
        lhs.state == rhs.state &&
        lhs.tileLookup == rhs.tileLookup &&
        lhs.preferredTitleID == rhs.preferredTitleID
    }
}

#if DEBUG
#Preview("CloudLibraryLibrary Grid", traits: .fixedLayout(width: 1920, height: 1080)) {
        CloudLibraryShellView(
            sideRail: CloudLibraryPreviewData.sideRail,
            selectedNavID: .library,
            heroBackgroundURL: CloudLibraryPreviewData.library.heroBackdropURL,
            onSelectNav: { _ in }
        ) {
            let tileLookup: [TitleID: MediaTileViewState] = Dictionary(
                uniqueKeysWithValues: CloudLibraryPreviewData.library.gridItems.map {
                    ($0.titleID, $0)
                }
            )
            CloudLibraryLibraryScreen(
                state: CloudLibraryPreviewData.library,
                tileLookup: tileLookup,
                onSelectTile: { _ in }
            )
        }
}
#endif
