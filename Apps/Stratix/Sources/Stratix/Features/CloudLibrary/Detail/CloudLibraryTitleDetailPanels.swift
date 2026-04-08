// CloudLibraryTitleDetailPanels.swift
// Defines cloud library title detail panels for the CloudLibrary / Detail surface.
//

import SwiftUI

extension CloudLibraryTitleDetailScreen {
    var detailPanelsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(StratixTheme.Fonts.sectionTitle)
                .foregroundStyle(StratixTheme.Colors.textPrimary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                spacing: 16
            ) {
                ForEach(state.detailPanels) { panel in
                    DetailPanelCardView(panel: panel)
                        .focused($focusedDetailPanelID, equals: panel.id)
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            requestGalleryFocus()
                        }
                }
            }
            .focusSection()
        }
    }
}

private struct DetailPanelCardView: View {
    let panel: OverlayPanelViewState

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(panel.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(StratixTheme.Colors.textPrimary)

            Text(panel.body)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(StratixTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .focusable(true)
        .gamePassDisableSystemFocusEffect()
        .gamePassFocusRing(isFocused: isFocused, cornerRadius: 20)
    }
}
