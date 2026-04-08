// ConsoleControllerTests.swift
// Exercises console controller behavior.
//

import Foundation
import Testing
@testable import StratixCore
import XCloudAPI

@MainActor
@Suite(.serialized)
struct ConsoleControllerTests {
    @Test
    func refresh_deduplicatesInflightRequests() async {
        let counter = CounterBox()
        let controller = ConsoleController(refreshWorkflow: { _, _ in
            counter.value += 1
            try? await Task.sleep(nanoseconds: 150_000_000)
            return []
        })
        let coordinator = AppCoordinator()
        controller.attach(coordinator.sessionController)
        await coordinator.testingApplyTokensFull(makeTokens())

        async let first: Void = controller.refresh()
        async let second: Void = controller.refresh()
        _ = await (first, second)

        #expect(counter.value == 1)
        #expect(controller.isLoading == false)
        #expect(controller.lastError == nil)
    }

    @Test
    func suspendForStreaming_cancelsInflightRefreshAndBlocksNewWork() async {
        let counter = CounterBox()
        let controller = ConsoleController(refreshWorkflow: { _, _ in
            counter.value += 1
            try await Task.sleep(nanoseconds: 250_000_000)
            return []
        })
        let coordinator = AppCoordinator()
        controller.attach(coordinator.sessionController)
        await coordinator.testingApplyTokensFull(makeTokens())

        async let first: Void = controller.refresh()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await controller.suspendForStreaming()
        await first

        #expect(counter.value == 1)
        #expect(controller.isLoading == false)
        #expect(controller.lastError == nil)

        await controller.refresh()
        #expect(counter.value == 1)

        controller.resumeAfterStreaming()
        await controller.refresh()
        #expect(counter.value == 2)
    }

    @Test
    func refresh_unauthenticatedSkipsWorkflow() async {
        let counter = CounterBox()
        let controller = ConsoleController(refreshWorkflow: { _, _ in
            counter.value += 1
            return []
        })
        let coordinator = AppCoordinator()
        controller.attach(coordinator.sessionController)

        await controller.refresh()

        #expect(counter.value == 0)
        #expect(controller.consoles.isEmpty)
        #expect(controller.isLoading == false)
        #expect(controller.lastError == nil)
    }

    @Test
    func refresh_workflowFailurePublishesError() async {
        let controller = ConsoleController(refreshWorkflow: { _, _ in
            throw NSError(domain: "ConsoleControllerTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "refresh failed"])
        })
        let coordinator = AppCoordinator()
        controller.attach(coordinator.sessionController)
        await coordinator.testingApplyTokensFull(makeTokens())

        await controller.refresh()

        #expect(controller.lastError == "refresh failed")
        #expect(controller.isLoading == false)
    }

    @Test
    func resetForSignOut_clearsConsoleState() {
        let controller = ConsoleController()
        controller.setIsLoading(true)
        controller.setLastError("boom")

        controller.resetForSignOut()

        #expect(controller.consoles.isEmpty)
        #expect(controller.isLoading == false)
        #expect(controller.lastError == nil)
    }

    private func makeTokens() -> StreamTokens {
        StreamTokens(
            xhomeToken: "xhome-token",
            xhomeHost: "https://xhome.example.com",
            xcloudToken: "xcloud-token",
            xcloudHost: "https://xcloud.example.com",
            webToken: nil,
            webTokenUHS: nil,
            xcloudRegions: []
        )
    }
}

@MainActor
private final class CounterBox {
    var value = 0
}
