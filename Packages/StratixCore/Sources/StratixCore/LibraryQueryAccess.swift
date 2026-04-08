// LibraryQueryAccess.swift
// Defines library query access.
//

import Foundation
import StratixModels

@MainActor
extension LibraryController {
    public func item(titleID: TitleID) -> CloudLibraryItem? {
        guard !titleID.rawValue.isEmpty else { return nil }
        return state.itemsByTitleID[titleID]
    }

    public func item(productID: ProductID) -> CloudLibraryItem? {
        guard !productID.rawValue.isEmpty else { return nil }
        return state.itemsByProductID[productID]
    }

    public func productDetail(productID: ProductID) -> CloudLibraryProductDetail? {
        guard !productID.rawValue.isEmpty else { return nil }
        return state.productDetails[productID]
    }
}
