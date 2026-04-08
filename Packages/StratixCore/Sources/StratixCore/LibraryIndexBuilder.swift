// LibraryIndexBuilder.swift
// Defines library index builder.
//

import Foundation
import StratixModels

enum LibraryIndexBuilder {
    static func makeIndexes(
        from sections: [CloudLibrarySection]
    ) -> (byTitleID: [TitleID: CloudLibraryItem], byProductID: [ProductID: CloudLibraryItem]) {
        var byTitleID: [TitleID: CloudLibraryItem] = [:]
        var byProductID: [ProductID: CloudLibraryItem] = [:]

        for section in sections {
            for item in section.items {
                let titleID = TitleID(item.titleId)
                if !titleID.rawValue.isEmpty {
                    byTitleID[titleID] = byTitleID[titleID] ?? item
                }
                let productID = ProductID(item.productId)
                if !productID.rawValue.isEmpty {
                    byProductID[productID] = byProductID[productID] ?? item
                }
            }
        }

        return (byTitleID, byProductID)
    }
}
