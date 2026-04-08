// ShellBootstrapControllerTests.swift
// Exercises shell bootstrap controller behavior.
//

import Foundation
import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct ShellBootstrapControllerTests {
    @Test
    func resetForSignOut_clearsLoadingAndStatus() async {
        let controller = ShellBootstrapController()
        controller.setIsLoading(true)
        controller.setStatusText("Syncing your cloud library...")

        await controller.resetForSignOut()

        #expect(controller.isLoading == false)
        #expect(controller.initialHydrationInProgress == false)
        #expect(controller.initialRoutePublicationDeferred == false)
        #expect(controller.statusText == nil)
    }

    @Test
    func suspendForStreaming_cancelsHydrationAndBlocksNewRequests() async {
        let controller = ShellBootstrapController()
        let counter = Counter()

        await controller.beginHydrationIfNeeded(
            plan: .networkRefresh,
            refreshAction: { _ in
                counter.incrementSync()
                try? await Task.sleep(nanoseconds: 250_000_000)
            },
            prefetchAction: {
                counter.incrementSync()
            }
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        await controller.suspendForStreaming()
        try? await Task.sleep(nanoseconds: 350_000_000)

        #expect(counter.value == 1)
        #expect(controller.phase == .idle)
        #expect(controller.isLoading == false)

        await controller.beginHydrationIfNeeded(
            plan: .cachedPrefetch,
            refreshAction: { _ in
                counter.incrementSync()
            },
            prefetchAction: {
                counter.incrementSync()
            }
        )

        #expect(counter.value == 1)

        controller.resumeAfterStreaming()
        await controller.beginHydrationIfNeeded(
            plan: .cachedPrefetch,
            refreshAction: { _ in
                counter.incrementSync()
            },
            prefetchAction: {
                counter.incrementSync()
            }
        )

        try? await Task.sleep(nanoseconds: 250_000_000)
        #expect(counter.value == 2)
        #expect(controller.phase == .ready)
    }

    @Test
    func beginHydrationIfNeeded_unauthenticatedDoesNothing() async {
        let controller = ShellBootstrapController()
        let counter = Counter()

        await controller.beginHydrationIfNeeded(
            plan: nil,
            refreshAction: { _ in
                await counter.increment()
            },
            prefetchAction: {
                counter.incrementSync()
            }
        )

        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(controller.isLoading == false)
        #expect(controller.initialHydrationInProgress == false)
        #expect(controller.initialRoutePublicationDeferred == false)
        #expect(controller.statusText == nil)
        #expect(counter.value == 0)
    }

    @Test
    func beginHydrationIfNeeded_noCacheRefreshesAndClearsLoadingState() async {
        let controller = ShellBootstrapController()
        let refreshCounter = Counter()
        let prefetchCounter = Counter()

        await controller.beginHydrationIfNeeded(
            plan: .networkRefresh,
            refreshAction: { deferInitialRoutePublication in
                #expect(deferInitialRoutePublication == true)
                await refreshCounter.increment()
            },
            prefetchAction: {
                prefetchCounter.incrementSync()
            }
        )

        #expect(controller.isLoading == true)
        #expect(controller.initialHydrationInProgress == true)
        #expect(controller.initialRoutePublicationDeferred == true)
        #expect(controller.statusText == "Syncing your cloud library...")

        try? await Task.sleep(nanoseconds: 950_000_000)

        #expect(controller.isLoading == false)
        #expect(controller.initialHydrationInProgress == false)
        #expect(controller.initialRoutePublicationDeferred == false)
        #expect(controller.statusText == nil)
        #expect(refreshCounter.value == 1)
        #expect(prefetchCounter.value == 0)
    }

    @Test
    func beginHydrationIfNeeded_freshCompleteCachePrefetches() async {
        let controller = ShellBootstrapController()
        let refreshCounter = Counter()
        let prefetchCounter = Counter()

        await controller.beginHydrationIfNeeded(
            plan: .cachedPrefetch,
            refreshAction: { _ in
                await refreshCounter.increment()
            },
            prefetchAction: {
                prefetchCounter.incrementSync()
            }
        )

        #expect(controller.isLoading == true)
        #expect(controller.initialHydrationInProgress == true)
        #expect(controller.initialRoutePublicationDeferred == false)
        #expect(controller.statusText == "Loading cached library...")

        try? await Task.sleep(nanoseconds: 550_000_000)

        #expect(controller.isLoading == false)
        #expect(controller.initialHydrationInProgress == false)
        #expect(controller.initialRoutePublicationDeferred == false)
        #expect(controller.statusText == nil)
        #expect(refreshCounter.value == 0)
        #expect(prefetchCounter.value == 1)
    }

    @Test
    func beginHydrationIfNeeded_deduplicatesInflightRequests() async {
        let controller = ShellBootstrapController()
        let refreshCounter = Counter()

        await controller.beginHydrationIfNeeded(
            plan: .networkRefresh,
            refreshAction: { _ in
                await refreshCounter.increment()
                try? await Task.sleep(nanoseconds: 200_000_000)
            },
            prefetchAction: {}
        )
        await controller.beginHydrationIfNeeded(
            plan: .networkRefresh,
            refreshAction: { _ in
                await refreshCounter.increment()
            },
            prefetchAction: {}
        )

        try? await Task.sleep(nanoseconds: 1_050_000_000)
        #expect(refreshCounter.value == 1)
    }

    @Test
    func beginHydrationIfNeeded_reportsReady_only_afterPublicationCompletion() async {
        let controller = ShellBootstrapController()
        let gate = AsyncGate()

        await controller.beginHydrationIfNeeded(
            plan: ShellBootHydrationPlan(
                mode: .refreshNetwork,
                statusText: "Syncing your cloud library...",
                deferInitialRoutePublication: true,
                minimumVisibleDuration: .zero,
                decisionDescription: "test"
            ),
            refreshAction: { _ in
                await gate.wait()
            },
            prefetchAction: {}
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(controller.initialHydrationInProgress == true)
        #expect(controller.phase != .ready)

        await gate.open()

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(controller.phase == .ready)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var value = 0

        func incrementSync() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        func increment() async {
            incrementSync()
        }
    }

    private actor AsyncGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen {
                return
            }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }
}

private extension ShellBootHydrationPlan {
    static let networkRefresh = ShellBootHydrationPlan(
        mode: .refreshNetwork,
        statusText: "Syncing your cloud library...",
        deferInitialRoutePublication: true,
        minimumVisibleDuration: .milliseconds(300),
        decisionDescription: "test"
    )

    static let cachedPrefetch = ShellBootHydrationPlan(
        mode: .prefetchCached,
        statusText: "Loading cached library...",
        deferInitialRoutePublication: false,
        minimumVisibleDuration: .milliseconds(150),
        decisionDescription: "test"
    )
}
