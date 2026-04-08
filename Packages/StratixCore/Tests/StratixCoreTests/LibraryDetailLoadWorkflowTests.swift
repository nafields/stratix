// LibraryDetailLoadWorkflowTests.swift
// Exercises library detail load workflow behavior.
//

import Foundation
@testable import StratixCore
import StratixModels
import Testing

@MainActor
@Suite(.serialized)
struct LibraryDetailLoadWorkflowTests {
    @Test
    func loadDetail_skipsWhenRichMediaIsAlreadyCached() async {
        let controller = LibraryController(
            detailWorkflow: { _, _, _, _ in
                Issue.record("detail workflow should not run when rich media is cached")
            }
        )
        controller.apply(
            .productDetailsReplaced([
                ProductID("product-1"): CloudLibraryProductDetail(
                    productId: "product-1",
                    mediaAssets: [
                        CloudLibraryMediaAsset(
                            kind: .image,
                            url: URL(string: "https://example.com/screenshot-1.jpg")!,
                            source: .productDetails
                        )
                    ]
                )
            ])
        )

        await controller.loadDetail(productID: ProductID("product-1"))
    }

    @Test
    func loadDetail_deduplicatesInflightRequests() async {
        let recorder = DetailWorkflowRecorder()
        let controller = LibraryController(
            detailWorkflow: { _, _, _, _ in
                await recorder.recordCall()
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        )

        async let first: Void = controller.loadDetail(productID: ProductID("product-1"))
        async let second: Void = controller.loadDetail(productID: ProductID("product-1"))
        _ = await (first, second)

        #expect(await recorder.callCount == 1)
    }
}

private actor DetailWorkflowRecorder {
    private(set) var callCount = 0

    func recordCall() {
        callCount += 1
    }
}
