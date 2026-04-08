// ConsoleGridSection.swift
// Defines console grid section for the Consoles surface.
//

import SwiftUI

enum ConsoleGridSection {
    static func columnCount(for width: CGFloat) -> Int {
        let minimumCardWidth: CGFloat = 720
        let spacing: CGFloat = 28
        let availableWidth = max(width, minimumCardWidth)
        return max(Int((availableWidth + spacing) / (minimumCardWidth + spacing)), 1)
    }

    static func columns(for width: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 720), spacing: 28, alignment: .top),
            count: columnCount(for: width)
        )
    }

    static func isLeadingColumn(index: Int, columnCount: Int) -> Bool {
        index % max(columnCount, 1) == 0
    }
}

extension ConsoleListView {
    var consoleGrid: some View {
        ScrollView {
            LazyVGrid(columns: consoleGridColumns, spacing: 28) {
                ForEach(Array(consoleController.consoles.enumerated()), id: \.element.serverId) { index, console in
                    ConsoleCardView(console: console) {
                        launchHomeStream(console)
                    }
                    .focused($focusedTarget, equals: .console(console.serverId))
                    .onMoveCommand { direction in
                        guard direction == .left, isLeadingGridColumn(index: index) else { return }
                        onRequestSideRailEntry()
                    }
                }
            }
            .focusSection()
            .padding(.top, 8)
            .padding(.bottom, 18)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateConsoleGridLayout(for: proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, width in
                            updateConsoleGridLayout(for: width)
                        }
                }
            )
        }
        .scrollIndicators(.hidden)
    }

    func updateConsoleGridLayout(for width: CGFloat) {
        let newColumns = ConsoleGridSection.columns(for: width)
        guard newColumns != consoleGridColumns else { return }
        consoleGridColumns = newColumns
    }

    func isLeadingGridColumn(index: Int) -> Bool {
        ConsoleGridSection.isLeadingColumn(index: index, columnCount: consoleGridColumns.count)
    }
}
