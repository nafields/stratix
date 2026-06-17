// CloudLibraryLibraryLetterIndexView.swift
// Shows the active alphabetical index position while browsing the library grid.
//

import SwiftUI

struct CloudLibraryLibraryLetterIndexView: View {
    let sections: [String]
    let currentLetter: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let currentLetter {
                Text(currentLetter)
                    .font(StratixTypography.rounded(28, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(StratixTheme.Colors.focusTint)
                    )
                    .accessibilityLabel("Current section \(currentLetter)")
            }

            VStack(alignment: .trailing, spacing: 3) {
                ForEach(sections, id: \.self) { letter in
                    Text(letter)
                        .font(StratixTypography.rounded(11, weight: .semibold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(
                            letter == currentLetter
                                ? StratixTheme.Colors.focusTint
                                : StratixTheme.Colors.textMuted.opacity(0.55)
                        )
                        .frame(width: 16, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: StratixTheme.Radius.md)
                .fill(Color.black.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StratixTheme.Radius.md)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .accessibilityIdentifier("library_letter_index")
    }
}

enum CloudLibraryLibraryLetterIndexSupport {
    static func indexLetter(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        let letter = String(first).uppercased()
        return letter.first?.isLetter == true ? letter : "#"
    }

    static func sections(from titles: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for title in titles {
            let letter = indexLetter(for: title)
            if seen.insert(letter).inserted {
                ordered.append(letter)
            }
        }
        return ordered
    }
}