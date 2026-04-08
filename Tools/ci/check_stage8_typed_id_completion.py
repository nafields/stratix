#!/usr/bin/env python3
from __future__ import annotations

from common import rel, fail

errors: list[str] = []

required = {
    rel("Apps/Stratix/Sources/Stratix/RouteState/NavigationTypes.swift"): [
        "case detail(titleID: TitleID)",
        "let allowedTitleIDs: Set<TitleID>",
        "enum ID: Hashable",
        "case cloud(TitleID)",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/ServiceProtocols.swift"): [
        "func item(titleID: TitleID) -> CloudLibraryItem?",
        "func item(productID: ProductID) -> CloudLibraryItem?",
        "func productDetail(productID: ProductID) -> CloudLibraryProductDetail?",
        "func loadDetail(productID: ProductID, locale: String, forceRefresh: Bool) async",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/AchievementsController.swift"): [
        "public func titleAchievementSnapshot(titleID: TitleID) -> TitleAchievementSnapshot?",
        "public func loadTitleAchievements(",
        "titleID: TitleID,",
        "public private(set) var titleAchievementSnapshots: [TitleID: TitleAchievementSnapshot] = [:]",
        "public private(set) var lastTitleAchievementsErrorByTitleID: [TitleID: String] = [:]",
    ],
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryStateSnapshot.swift"): [
        "var itemsByTitleID: [TitleID: CloudLibraryItem] { state.itemsByTitleID }",
        "var itemsByProductID: [ProductID: CloudLibraryItem] { state.itemsByProductID }",
        "var productDetails: [ProductID: CloudLibraryProductDetail] { state.productDetails }",
        "func item(titleID: TitleID) -> CloudLibraryItem?",
        "func item(productID: ProductID) -> CloudLibraryItem?",
        "func productDetail(productID: ProductID) -> CloudLibraryProductDetail?",
    ],
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Detail/State/DetailStateHotCache.swift"): [
        "private var entries: [TitleID: DetailStateCacheEntry] = [:]",
        "mutating func invalidateChangedEntries(currentSignatures: [TitleID: String]) -> [TitleID]",
    ],
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryViewModelDetailCache.swift"): [
        "hasher.combine(item.typedTitleID)",
        "hasher.combine(item.typedProductID)",
    ],
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneModelMutationTracking.swift"): [
        "map(\\.typedTitleID)",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationCatalogState.swift"): [
        "struct LibraryMRUEntry: Sendable, Hashable",
        "let titleID: TitleID",
        "let productID: ProductID",
        "let mruEntries: [LibraryMRUEntry]",
        "let allProductIds: [ProductID]",
        "let titleByProductId: [ProductID: TitleEntry]",
        "let titleByTitleId: [TitleID: TitleEntry]",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryMRUDeltaFetcher.swift"): [
        ") async throws -> [LibraryMRUEntry] {",
        "LibraryMRUEntry(titleID: titleId, productID: productId)",
    ],
}

forbidden = {
    rel("Apps/Stratix/Sources/Stratix/RouteState/NavigationTypes.swift"): [
        "case detail(titleId: String)",
        "let allowedTitleIDs: Set<String>",
        "var id: String",
        "case cloud(titleId: String)",
    ],
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibraryStateSnapshot.swift"): [
        "stringItemsByTitleID",
        "stringItemsByProductID",
        "stringProductDetails",
        "item(productIDRaw:",
        "productDetail(productIDRaw:",
        "[String: CloudLibraryItem]",
        "[String: CloudLibraryProductDetail]",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/ServiceProtocols.swift"): [
        "func item(titleId: String) -> CloudLibraryItem?",
        "func item(productId: String) -> CloudLibraryItem?",
        "func productDetail(productId: String) -> CloudLibraryProductDetail?",
        "func loadDetail(productId: String, locale: String, forceRefresh: Bool) async",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/AchievementsController.swift"): [
        "public func titleAchievementSnapshot(titleId: String) -> TitleAchievementSnapshot?",
        "loadTitleAchievements(titleId:",
        "public private(set) var titleAchievementSnapshots: [String: TitleAchievementSnapshot] = [:]",
        "public private(set) var lastTitleAchievementsErrorByTitleId: [String: String] = [:]",
        "public func setTitleAchievementSnapshots(_ value: [String: TitleAchievementSnapshot])",
        "public func setLastTitleAchievementsErrorByTitleId(_ value: [String: String])",
    ],
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Detail/State/DetailStateHotCache.swift"): [
        "private var entries: [String: DetailStateCacheEntry] = [:]",
        "invalidateChangedEntries(currentSignatures: [String: String])",
    ],
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryViewModelDetailCache.swift"): [
        "hasher.combine(item.titleId)",
        "hasher.combine(item.productId)",
    ],
    rel("Apps/Stratix/Sources/Stratix/Features/CloudLibrary/State/CloudLibrarySceneModelMutationTracking.swift"): [
        "map(\\.titleId)",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationCatalogState.swift"): [
        "let mruEntries: [(titleId: String, productId: String)]",
        "let allProductIds: [String]",
        "let titleByProductId: [String: TitleEntry]",
        "let titleByTitleId: [String: TitleEntry]",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryMRUDeltaFetcher.swift"): [
        ") async throws -> [(titleId: String, productId: String)] {",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/Hydration/LibraryHydrationPostStreamDeltaWorkflow.swift"): [
        "let fetchLiveMRUEntries: () async throws -> [(titleId: String, productId: String)]",
        "let applySectionsDelta: (_ liveMRUEntries: [(titleId: String, productId: String)]) -> MRUDeltaSectionsResult",
    ],
    rel("Packages/StratixCore/Sources/StratixCore/LibraryController.swift"): [
        "func fetchLiveMRUEntriesForHydration() async throws -> [(titleId: String, productId: String)]",
        "_ liveMRUEntries: [(titleId: String, productId: String)]",
        "liveMRUEntries: [(titleId: String, productId: String)]",
        "mruEntries: [(titleId: String, productId: String)]",
    ],
}

for path, needles in required.items():
    if not path.exists():
        errors.append(f"Missing required path: {path}")
        continue
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            errors.append(f"{path}: expected typed-ID completion content {needle!r}")

for path, needles in forbidden.items():
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle in text:
            errors.append(f"{path}: forbidden pre-closeout raw-ID seam {needle!r}")

fail(errors)
print("Stage 8 typed ID completion guard passed.")
