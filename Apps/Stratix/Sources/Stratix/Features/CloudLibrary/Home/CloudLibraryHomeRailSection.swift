// CloudLibraryHomeRailSection.swift
// Defines cloud library home rail section for the CloudLibrary / Home surface.
//

import SwiftUI

extension CloudLibraryHomeScreen {
    func rail(section: CloudLibraryRailSectionViewState, sectionIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(section.title)
                .font(StratixTypography.rounded(36, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(.white)
                .padding(.horizontal, StratixTheme.Home.sectionHeaderHorizontalPadding)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 18) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                        switch item {
                        case .title(let titleItem):
                            MediaTileView(
                                state: titleItem.tile,
                                onSelect: { onSelectRailItem(item) },
                                forcedFocus: focusedTarget == .titleTile(
                                    titleItem.tile.titleID,
                                    sectionID: section.id
                                ),
                                presentation: .artworkOnly,
                                artworkOverrideSize: CGSize(
                                    width: StratixTheme.Home.railTileWidth,
                                    height: StratixTheme.Home.railTileHeight
                                )
                            )
                            .focused(
                                $focusedTarget,
                                equals: .titleTile(titleItem.tile.titleID, sectionID: section.id)
                            )
                            .onMoveCommand { direction in
                                handleRailMove(
                                    sectionIndex: sectionIndex,
                                    itemIndex: itemIndex,
                                    direction: direction
                                )
                            }

                        case .showAll(let card):
                            HomeShowAllCardButton(card: card) {
                                onSelectRailItem(item)
                            }
                            .focused($focusedTarget, equals: .showAllCard(card.id))
                            .onMoveCommand { direction in
                                handleRailMove(
                                    sectionIndex: sectionIndex,
                                    itemIndex: itemIndex,
                                    direction: direction
                                )
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, StratixTheme.Home.railHorizontalPadding)
                .padding(.top, StratixTheme.Home.railTopPadding)
                .padding(.bottom, focusedTileExtraHeight)
                .padding(.leading, railEdgeFocusInset)
                .padding(.trailing, railEdgeFocusInset)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .id(section.id)
        .focusSection()
    }
}
